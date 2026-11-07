use super::Backend;
use crate::{
    error::Result,
    maintenance::{self, StorageGroup, StorageReport},
    prompts::{self, PromptDefinition, PromptKind},
    tasks::cancellable,
};

impl Backend {
    /// 按当前代理设置对 [url] 发 HEAD 请求，返回往返毫秒数（网络设置页的连通性测试）。
    pub async fn probe_url(&self, url: String, task_id: String) -> Result<u64> {
        let task = self.runtime.tasks.begin(task_id)?;
        let (proxy, http2) = self
            .runtime
            .call(&task.token, "network_settings", |state| {
                super::network_settings(state.storage()?)
            })
            .await?;
        let started = std::time::Instant::now();
        crate::network::send(
            crate::network::client(proxy.as_deref(), http2)?.head(url),
            &task.token,
        )
        .await?;
        Ok(started.elapsed().as_millis() as u64)
    }

    pub async fn prompt(&self, kind: PromptKind) -> Result<PromptDefinition> {
        self.runtime
            .with_storage(&Default::default(), "prompt", move |storage| {
                prompts::get(storage, kind)
            })
            .await
    }
    pub async fn set_prompt(&self, kind: PromptKind, text: String) -> Result<PromptDefinition> {
        self.runtime
            .with_storage(&Default::default(), "set_prompt", move |storage| {
                prompts::set(storage, kind, &text)
            })
            .await
    }
    pub async fn storage_report(&self, task_id: String) -> Result<StorageReport> {
        let task = self.runtime.tasks.begin(task_id)?;
        let token = task.token.clone();
        self.runtime
            .with_storage(&task.token, "storage_report", move |storage| {
                maintenance::report(storage, &token)
            })
            .await
    }
    pub async fn clear_storage(&self, groups: Vec<StorageGroup>, task_id: String) -> Result<()> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.write().await)
        })
        .await?;
        let token = task.token.clone();
        self.runtime
            .call(&task.token, "clear_storage", move |state| {
                if groups.contains(&StorageGroup::Papers) {
                    state.close_pdfs()?;
                }
                if groups.contains(&StorageGroup::Cache)
                    && let Some(pdf) = &mut state.pdf
                {
                    pdf.clear_cache();
                }
                maintenance::clear(state.storage()?, &groups, &token)
            })
            .await
    }
}
