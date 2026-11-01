use super::{Backend, backup::BackupManifest, remote::remote};
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    network::{TransferObserver, TransferProgress},
    sync::{
        archive::{self, BackupProgress, BackupScope, Stage},
        remote::RemoteConfig,
        status::{self, BackupSnapshot, BackupStatus},
    },
    tasks::cancellable,
};
use std::sync::Arc;

#[derive(Clone)]
pub enum SyncEvent {
    Failed {
        error: OtterError,
    },
    Packing {
        progress: BackupProgress,
    },
    Uploading {
        progress: TransferProgress,
    },
    Skipped,
    Uploaded {
        name: String,
        manifest: BackupManifest,
        warnings: Vec<ErrorCode>,
    },
}
impl Backend {
    /// The host starts this stream with its app lifecycle and cancels its task
    /// on shutdown. Due/change decisions and hourly scheduling stay in Rust.
    pub async fn watch_auto_backup(
        &self,
        device: Option<String>,
        task_id: String,
        sink: StreamSink<SyncEvent>,
    ) -> Result<()> {
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id.clone())?;
            let mut delay = std::time::Duration::from_secs(120);
            let mut sequence = 0u64;
            loop {
                cancellable(&task.token, async {
                    tokio::time::sleep(delay).await;
                    Ok(())
                })
                .await?;
                delay = std::time::Duration::from_secs(3600);
                let configuration = self
                    .runtime
                    .with_storage(
                        &task.token,
                        "auto_backup_settings",
                        status::automatic_configuration,
                    )
                    .await?;
                if let Some((config, scope)) = configuration {
                    let key = match config {
                        RemoteConfig::S3 { .. } => "backup_s3_secret_access_key",
                        RemoteConfig::Webdav { .. } => "backup_webdav_password",
                    };
                    if self
                        .runtime
                        .credentials
                        .optional(key)?
                        .is_none_or(|key| key.is_empty())
                    {
                        continue;
                    }
                    sequence += 1;
                    cancellable(
                        &task.token,
                        self.backup_to_remote(
                            config,
                            scope,
                            device.clone(),
                            true,
                            format!("{task_id}:{sequence}"),
                            sink.clone(),
                        ),
                    )
                    .await?;
                }
            }
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(SyncEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn backup_status(&self, task_id: String) -> Result<BackupStatus> {
        let task = self.runtime.tasks.begin(task_id)?;
        let token = task.token.clone();
        self.runtime
            .with_storage(&task.token, "backup_status", move |storage| {
                status::status(storage, &token)
            })
            .await
    }
    pub async fn backup_to_remote(
        &self,
        config: RemoteConfig,
        scope: BackupScope,
        device: Option<String>,
        only_if_due: bool,
        task_id: String,
        sink: StreamSink<SyncEvent>,
    ) -> Result<()> {
        let sink = Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let _backup =
                cancellable(&task.token, async { Ok(self.runtime.backups.lock().await) }).await?;
            let token = task.token.clone();
            let due_config = config.clone();
            let preparation_sink = sink.clone();
            let remote_id = status::remote_identity(&config)?;
            let prepared = self
                .runtime
                .call(&task.token, "prepare_remote_backup", move |state| {
                    let storage = state.storage()?;
                    let now = time::OffsetDateTime::now_utc();
                    let at = (now.unix_timestamp_nanos() / 1_000_000) as i64;
                    if only_if_due && !status::automatic_due(storage, &due_config, at, &token)? {
                        return Ok(None);
                    }
                    let stage = Stage::new(storage.directory(), "upload-backup")?;
                    let documents = status::fingerprints(storage, &token)?;
                    let snapshot = BackupSnapshot {
                        version: 2,
                        at,
                        scope,
                        remote: remote_id,
                        device: device.clone(),
                        documents,
                    };
                    let path = stage.path.join("backup.zip");
                    let manifest =
                        archive::create(storage, &path, scope, device, &token, |progress| {
                            if preparation_sink
                                .add(SyncEvent::Packing { progress })
                                .is_err()
                            {
                                token.cancel();
                            }
                        })?;
                    let name = format!(
                        "otter_pad_backup_{}{:02}{:02}_{:02}{:02}{:02}.zip",
                        now.year(),
                        u8::from(now.month()),
                        now.day(),
                        now.hour(),
                        now.minute(),
                        now.second()
                    );
                    Ok(Some((stage, path, manifest, snapshot, name)))
                })
                .await?;
            let Some((_stage, path, manifest, snapshot, name)) = prepared else {
                sink.add(SyncEvent::Skipped).map_err(closed)?;
                return Ok(());
            };
            let remote = remote(self, config, &task.token).await?;
            let progress_sink = sink.clone();
            let progress_token = task.token.clone();
            let progress: TransferObserver = Arc::new(move |progress| {
                if progress_sink
                    .add(SyncEvent::Uploading { progress })
                    .is_err()
                {
                    progress_token.cancel();
                }
            });
            remote
                .upload(&path, &name, &task.token, Some(progress))
                .await?;
            self.runtime
                .call(&task.token, "save_backup_snapshot", move |state| {
                    status::save(state.storage()?, &snapshot)
                })
                .await?;
            let mut warnings = Vec::new();
            match remote.list(&task.token).await {
                Ok(mut entries) => {
                    entries.retain(|entry| versioned_name(&entry.name));
                    entries.sort_by(|a, b| b.name.cmp(&a.name));
                    for entry in entries.into_iter().skip(3) {
                        if let Err(error) = remote.delete(&entry.name, &task.token).await {
                            if error.code == ErrorCode::Cancelled {
                                return Err(error);
                            }
                            warnings.push(error.code);
                        }
                    }
                }
                Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                Err(error) => warnings.push(error.code),
            }
            sink.add(SyncEvent::Uploaded {
                name,
                manifest: manifest.into(),
                warnings,
            })
            .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(SyncEvent::Failed { error });
        }
        Ok(())
    }
}
fn versioned_name(name: &str) -> bool {
    name.strip_prefix("otter_pad_backup_")
        .and_then(|s| s.strip_suffix(".zip"))
        .is_some_and(|s| {
            s.len() == 15
                && s.as_bytes()[8] == b'_'
                && s.bytes()
                    .enumerate()
                    .all(|(i, b)| i == 8 || b.is_ascii_digit())
        })
}
fn closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "backup sync stream closed")
}
