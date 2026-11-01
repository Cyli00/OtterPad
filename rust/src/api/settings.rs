use super::Backend;
use crate::{
    error::Result,
    maintenance::{self, StorageGroup, StorageReport},
    prompts::{self, PromptDefinition, PromptKind},
    tasks::cancellable,
};

impl Backend {
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
