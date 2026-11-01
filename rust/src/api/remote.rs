use super::{Backend, network_settings};
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    network::{TransferObserver, TransferProgress},
    sync::remote::{BackupRemote, RemoteConfig, RemoteEntry},
    tasks::cancellable,
};
use std::{path::PathBuf, sync::Arc};

pub enum TransferDirection {
    Upload,
    Download,
}
pub enum RemoteTransferEvent {
    Failed { error: OtterError },
    Progress { progress: TransferProgress },
    Completed,
}
pub(crate) async fn remote(
    backend: &Backend,
    config: RemoteConfig,
    token: &tokio_util::sync::CancellationToken,
) -> Result<BackupRemote> {
    let key = match config {
        RemoteConfig::Webdav { .. } => "backup_webdav_password",
        RemoteConfig::S3 { .. } => "backup_s3_secret_access_key",
    };
    let secret = if matches!(config, RemoteConfig::Webdav { .. }) {
        backend
            .runtime
            .credentials
            .optional(key)?
            .unwrap_or_default()
    } else {
        backend.runtime.credentials.get(key)?
    };
    let (proxy, http2) = backend
        .runtime
        .call(token, "network_settings", |state| {
            network_settings(state.storage()?)
        })
        .await?;
    BackupRemote::new(config, secret, proxy.as_deref(), http2)
}
impl Backend {
    pub async fn check_backup_remote(&self, config: RemoteConfig, task_id: String) -> Result<()> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        remote(self, config, &task.token)
            .await?
            .ping(&task.token)
            .await
    }
    pub async fn remote_backups(
        &self,
        config: RemoteConfig,
        task_id: String,
    ) -> Result<Vec<RemoteEntry>> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        remote(self, config, &task.token)
            .await?
            .list(&task.token)
            .await
    }
    pub async fn delete_remote_backup(
        &self,
        config: RemoteConfig,
        name: String,
        task_id: String,
    ) -> Result<()> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        remote(self, config, &task.token)
            .await?
            .delete(&name, &task.token)
            .await
    }
    pub async fn transfer_backup(
        &self,
        config: RemoteConfig,
        name: String,
        path: String,
        direction: TransferDirection,
        task_id: String,
        sink: StreamSink<RemoteTransferEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let remote = remote(self, config, &task.token).await?;
            let progress_sink = sink.clone();
            let token = task.token.clone();
            let progress: TransferObserver = Arc::new(move |progress| {
                if progress_sink
                    .add(RemoteTransferEvent::Progress { progress })
                    .is_err()
                {
                    token.cancel();
                }
            });
            match direction {
                TransferDirection::Upload => {
                    remote
                        .upload(&PathBuf::from(path), &name, &task.token, Some(progress))
                        .await?
                }
                TransferDirection::Download => {
                    remote
                        .download(
                            &name,
                            &PathBuf::from(path),
                            64 * 1024 * 1024 * 1024,
                            &task.token,
                            Some(&progress),
                        )
                        .await?
                }
            }
            sink.add(RemoteTransferEvent::Completed)
                .map_err(|_| OtterError::new(ErrorCode::Cancelled, "backup transfer stream closed"))
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(RemoteTransferEvent::Failed { error });
        }
        Ok(())
    }
}
