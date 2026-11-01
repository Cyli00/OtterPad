use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use tokio_util::sync::CancellationToken;

use crate::error::{ErrorCode, OtterError, Result};

#[derive(Default)]
pub struct Tasks(Mutex<HashMap<String, CancellationToken>>);

impl Tasks {
    pub fn begin(self: &Arc<Self>, id: String) -> Result<TaskGuard> {
        let token = self.start(id.clone())?;
        Ok(TaskGuard {
            tasks: self.clone(),
            id,
            token,
        })
    }
    pub fn start(&self, id: String) -> Result<CancellationToken> {
        let mut tasks = self
            .0
            .lock()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "task registry poisoned"))?;
        if tasks.contains_key(&id) {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "task id already running",
            ));
        }
        let token = CancellationToken::new();
        tasks.insert(id, token.clone());
        Ok(token)
    }

    pub fn cancel(&self, id: &str) -> Result<bool> {
        let tasks = self
            .0
            .lock()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "task registry poisoned"))?;
        if let Some(token) = tasks.get(id) {
            token.cancel();
            return Ok(true);
        }
        Ok(false)
    }

    pub fn finish(&self, id: &str) -> Result<()> {
        self.0
            .lock()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "task registry poisoned"))?
            .remove(id);
        Ok(())
    }

    pub(crate) fn cancel_except(&self, keep: Option<&str>) -> Result<u32> {
        let tasks = self
            .0
            .lock()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "task registry poisoned"))?;
        let mut count = 0;
        for (id, token) in tasks.iter() {
            if Some(id.as_str()) != keep {
                token.cancel();
                count += 1;
            }
        }
        Ok(count)
    }
}

pub struct TaskGuard {
    tasks: Arc<Tasks>,
    id: String,
    pub token: CancellationToken,
}
impl Drop for TaskGuard {
    fn drop(&mut self) {
        self.token.cancel();
        let _ = self.tasks.finish(&self.id);
    }
}

pub fn check(token: &CancellationToken) -> Result<()> {
    if token.is_cancelled() {
        Err(OtterError::new(ErrorCode::Cancelled, "task cancelled"))
    } else {
        Ok(())
    }
}

pub async fn cancellable<T>(
    token: &CancellationToken,
    future: impl std::future::Future<Output = Result<T>>,
) -> Result<T> {
    tokio::select! { biased;
        _ = token.cancelled() => Err(OtterError::new(ErrorCode::Cancelled, "task cancelled")),
        result = future => result,
    }
}

/// CPU-only conversion results are discarded when the caller cancels.
pub async fn blocking<T: Send + 'static>(
    token: &CancellationToken,
    job: impl FnOnce() -> Result<T> + Send + 'static,
) -> Result<T> {
    check(token)?;
    let token_owned = token.clone();
    let work = tokio::task::spawn_blocking(move || {
        check(&token_owned)?;
        let result = job()?;
        check(&token_owned)?;
        Ok(result)
    });
    cancellable(token, async {
        work.await
            .map_err(|_| OtterError::new(ErrorCode::InvalidData, "conversion worker stopped"))?
    })
    .await
}
