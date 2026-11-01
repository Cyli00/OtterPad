use super::{Backend, network_settings};
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    network::{TransferObserver, TransferProgress},
    tasks::cancellable,
    update::{self, ApkAsset, UpdateInfo},
};
use std::{path::PathBuf, sync::Arc};

pub enum UpdateDownloadEvent {
    Failed { error: OtterError },
    Progress { progress: TransferProgress },
    Completed { path: String },
}
impl Backend {
    pub async fn check_update_after_startup(
        &self,
        current_version: String,
        supported_abis: Vec<String>,
        task_id: String,
    ) -> Result<Option<UpdateInfo>> {
        let task = self.runtime.tasks.begin(task_id.clone())?;
        cancellable(&task.token, async {
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
            Ok(())
        })
        .await?;
        let enabled = self
            .runtime
            .with_storage(&task.token, "auto_update_setting", |storage| {
                Ok(storage
                    .setting("general_auto_check_update")?
                    .and_then(|v| v.as_bool())
                    .unwrap_or(true))
            })
            .await?;
        if !enabled {
            return Ok(None);
        }
        match cancellable(
            &task.token,
            self.check_for_update(current_version, supported_abis, format!("{task_id}:check")),
        )
        .await
        {
            Ok(info) => Ok((info.has_update && !info.ignored).then_some(info)),
            Err(error) if error.code == ErrorCode::Cancelled => Err(error),
            Err(error) => {
                self.runtime
                    .call(&task.token, "auto_update", move |state| {
                        state.logger.record(
                            state.storage()?,
                            "auto_update",
                            crate::logging::LogLevel::Error,
                            Some(error.code),
                        )?;
                        Ok(None)
                    })
                    .await
            }
        }
    }
    /// Package version and ordered device ABIs come from the host's platform APIs.
    pub async fn check_for_update(
        &self,
        current_version: String,
        supported_abis: Vec<String>,
        task_id: String,
    ) -> Result<UpdateInfo> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let ((proxy, http2), ignored) = self
            .runtime
            .call(&task.token, "update_settings", |state| {
                let storage = state.storage()?;
                Ok((
                    network_settings(storage)?,
                    storage
                        .setting("general_ignored_update_version")?
                        .and_then(|v| v.as_str().map(str::to_owned)),
                ))
            })
            .await?;
        update::check(
            &crate::network::client(proxy.as_deref(), http2)?,
            update::RELEASES_URL,
            &current_version,
            &supported_abis,
            ignored.as_deref(),
            &task.token,
        )
        .await
    }
    pub async fn download_update(
        &self,
        asset: ApkAsset,
        path: String,
        task_id: String,
        sink: StreamSink<UpdateDownloadEvent>,
    ) -> Result<()> {
        let sink = Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let (proxy, http2) = self
                .runtime
                .call(&task.token, "network_settings", |state| {
                    network_settings(state.storage()?)
                })
                .await?;
            let progress_sink = sink.clone();
            let token = task.token.clone();
            let progress: TransferObserver = Arc::new(move |progress| {
                if progress_sink
                    .add(UpdateDownloadEvent::Progress { progress })
                    .is_err()
                {
                    token.cancel();
                }
            });
            update::download(
                &crate::network::client(proxy.as_deref(), http2)?,
                &asset,
                &PathBuf::from(&path),
                &task.token,
                Some(&progress),
            )
            .await?;
            sink.add(UpdateDownloadEvent::Completed { path })
                .map_err(|_| OtterError::new(ErrorCode::Cancelled, "update stream closed"))
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(UpdateDownloadEvent::Failed { error });
        }
        Ok(())
    }
}
