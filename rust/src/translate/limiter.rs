//! 全文翻译的自适应并发，每个服务端点一份，跨文档共享。
//!
//! 最多 [`MAX`] 个请求同时在途。供应商限流（429）时并发减半，并让该端点的新请求统一暂停
//! 一段时间（1s 起翻倍，封顶 [`MAX_PAUSE`]）；之后每连续成功 `limit` 次恢复 1 个并发。
//! 同一轮限流里先前发出的请求陆续返回 429 只算一次，避免并发被连续减到底。
//! 期间没有任何成功、累计减速 [`GIVE_UP`] 次后判定供应商暂不可用，由调用方停止整批翻译。

use std::{
    collections::HashMap,
    sync::{Arc, LazyLock, Mutex, MutexGuard},
    time::Duration,
};

use tokio::{sync::Notify, time::Instant};

use crate::ai::types::ModelConfig;

pub(crate) const MAX: usize = 20;
const MAX_PAUSE: Duration = Duration::from_secs(30);
/// 20→10→5→2→1 用掉 4 次，最低并发下再连续限流 4 次后放弃，暂停合计约 1 分钟。
const GIVE_UP: u32 = 8;
/// 端点空闲这么久后恢复满并发，上一批的限流状态不拖累下一批。
const IDLE_RESET: Duration = Duration::from_secs(60);

static LIMITERS: LazyLock<Mutex<HashMap<String, Arc<Limiter>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub(crate) struct Limiter {
    state: Mutex<State>,
    changed: Notify,
}

struct State {
    limit: usize,
    active: usize,
    streak: usize,
    strikes: u32,
    generation: u64,
    resume_at: Instant,
    last_event: Instant,
}

impl State {
    fn new() -> Self {
        let now = Instant::now();
        Self {
            limit: MAX,
            active: 0,
            streak: 0,
            strikes: 0,
            generation: 0,
            resume_at: now,
            last_event: now,
        }
    }
}

pub(crate) struct Permit {
    limiter: Arc<Limiter>,
    generation: u64,
}

impl Limiter {
    fn new() -> Self {
        Self {
            state: Mutex::new(State::new()),
            changed: Notify::new(),
        }
    }

    pub(crate) fn for_endpoint(model: &ModelConfig) -> Arc<Self> {
        let key = format!(
            "{:?}|{}",
            model.provider,
            model.base_url.trim_end_matches('/')
        );
        let mut map = LIMITERS.lock().unwrap_or_else(|e| e.into_inner());
        map.entry(key)
            .or_insert_with(|| Arc::new(Self::new()))
            .clone()
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub(crate) async fn acquire(self: &Arc<Self>) -> Permit {
        loop {
            let notified = self.changed.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            let resume_at = {
                let mut state = self.lock();
                let now = Instant::now();
                if state.active == 0 && now.duration_since(state.last_event) >= IDLE_RESET {
                    let generation = state.generation;
                    *state = State::new();
                    state.generation = generation + 1;
                }
                if now < state.resume_at {
                    Some(state.resume_at)
                } else if state.active < state.limit {
                    state.active += 1;
                    return Permit {
                        limiter: self.clone(),
                        generation: state.generation,
                    };
                } else {
                    None
                }
            };
            match resume_at {
                Some(at) => {
                    tokio::select! {
                        _ = tokio::time::sleep_until(at) => {}
                        _ = notified => {}
                    }
                }
                None => notified.await,
            }
        }
    }

    #[cfg(test)]
    fn limit(&self) -> usize {
        self.lock().limit
    }
}

impl Permit {
    pub(crate) fn succeeded(&self) {
        let mut state = self.limiter.lock();
        state.last_event = Instant::now();
        state.strikes = 0;
        state.streak += 1;
        if state.streak >= state.limit && state.limit < MAX {
            state.limit += 1;
            state.streak = 0;
            drop(state);
            self.limiter.changed.notify_waiters();
        }
    }

    /// 记录一次限流；返回 true 表示应放弃整批翻译。
    pub(crate) fn rate_limited(&self) -> bool {
        let mut state = self.limiter.lock();
        let now = Instant::now();
        state.last_event = now;
        if self.generation != state.generation {
            return false;
        }
        state.generation += 1;
        state.limit = (state.limit / 2).max(1);
        state.streak = 0;
        let pause = Duration::from_secs(1 << state.strikes.min(5)).min(MAX_PAUSE);
        state.strikes += 1;
        state.resume_at = now + pause;
        state.strikes >= GIVE_UP
    }
}

impl Drop for Permit {
    fn drop(&mut self) {
        self.limiter.lock().active -= 1;
        self.limiter.changed.notify_one();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn permit(limiter: &Arc<Limiter>) -> Permit {
        let mut state = limiter.lock();
        state.active += 1;
        Permit {
            limiter: limiter.clone(),
            generation: state.generation,
        }
    }

    #[test]
    fn halves_once_per_round_recovers_additively_and_gives_up_without_success() {
        let limiter = Arc::new(Limiter::new());
        let early = permit(&limiter);
        let late = permit(&limiter);
        assert!(!early.rate_limited());
        assert_eq!(limiter.limit(), 10);
        // 同一轮先前发出的请求再报 429 不再减速。
        assert!(!late.rate_limited());
        assert_eq!(limiter.limit(), 10);
        drop((early, late));
        for _ in 0..10 {
            permit(&limiter).succeeded();
        }
        assert_eq!(limiter.limit(), 11);
        let mut gave_up = false;
        for round in 1..=GIVE_UP {
            gave_up = permit(&limiter).rate_limited();
            assert_eq!(gave_up, round == GIVE_UP);
        }
        assert!(gave_up);
        assert_eq!(limiter.limit(), 1);
        let state = limiter.lock();
        assert!(state.resume_at - Instant::now() <= MAX_PAUSE);
        assert_eq!(state.active, 0);
    }
}
