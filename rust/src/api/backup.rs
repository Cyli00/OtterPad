use super::Backend;
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    sync::{
        archive::{self, BackupProgress, BackupScope, Manifest},
        backup::{self, MergeReport, RestoreMode, RestoreScope},
    },
    tasks::cancellable,
};
use std::path::PathBuf;

#[derive(Clone)]
pub struct BackupManifest {
    pub format_version: u32,
    pub created_at: String,
    pub scope: BackupScope,
    pub device_name: Option<String>,
    pub file_count: u64,
}
pub struct DocumentMapping {
    pub source_id: String,
    pub document_id: String,
}
pub struct RestoreReport {
    pub documents_added: u64,
    pub highlights_added: u64,
    pub files_copied: u64,
    pub settings_added: u64,
    pub skipped_orphans: u64,
    pub document_ids: Vec<DocumentMapping>,
}
pub struct RestorePreview {
    pub id: String,
    pub manifest: BackupManifest,
    pub report: RestoreReport,
}
pub enum BackupEvent {
    Failed { error: OtterError },
    Progress { progress: BackupProgress },
    Created { manifest: BackupManifest },
    Prepared { preview: RestorePreview },
    Restored { report: RestoreReport },
}
impl From<Manifest> for BackupManifest {
    fn from(m: Manifest) -> Self {
        Self {
            format_version: m.format_version,
            created_at: m.created_at,
            scope: m.scope,
            device_name: m.device_name,
            file_count: m.file_checksums.map(|v| v.len() as u64).unwrap_or(0),
        }
    }
}
impl From<MergeReport> for RestoreReport {
    fn from(m: MergeReport) -> Self {
        Self {
            documents_added: m.documents_added as u64,
            highlights_added: m.highlights_added as u64,
            files_copied: m.files_copied as u64,
            settings_added: m.settings_added as u64,
            skipped_orphans: m.skipped_orphans as u64,
            document_ids: m
                .document_ids
                .into_iter()
                .map(|(source_id, document_id)| DocumentMapping {
                    source_id,
                    document_id,
                })
                .collect(),
        }
    }
}
impl Backend {
    pub async fn create_backup(
        &self,
        path: String,
        scope: BackupScope,
        device_name: Option<String>,
        task_id: String,
        sink: StreamSink<BackupEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let token = task.token.clone();
            self.runtime
                .with_storage(&task.token, "create_backup", move |storage| {
                    let manifest = archive::create(
                        storage,
                        &PathBuf::from(path),
                        scope,
                        device_name,
                        &token,
                        |progress| {
                            if sink.add(BackupEvent::Progress { progress }).is_err() {
                                token.cancel();
                            }
                        },
                    )?;
                    sink.add(BackupEvent::Created {
                        manifest: manifest.into(),
                    })
                    .map_err(stream_closed)
                })
                .await
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(BackupEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn prepare_restore(
        &self,
        path: String,
        scope: RestoreScope,
        mode: RestoreMode,
        task_id: String,
        sink: StreamSink<BackupEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let token = task.token.clone();
            self.runtime
                .call(&task.token, "prepare_restore", move |state| {
                    let prepared = backup::prepare(
                        state.storage()?,
                        &PathBuf::from(path),
                        scope,
                        mode,
                        &token,
                        |progress| {
                            if sink.add(BackupEvent::Progress { progress }).is_err() {
                                token.cancel();
                            }
                        },
                    )?;
                    let id = crate::ai::chat::new_id();
                    let preview = RestorePreview {
                        id: id.clone(),
                        manifest: prepared.manifest.clone().into(),
                        report: prepared.report.clone().into(),
                    };
                    // Only one pending preview is retained; it owns a complete replacement directory.
                    state.restores.clear();
                    sink.add(BackupEvent::Prepared { preview })
                        .map_err(stream_closed)?;
                    state.restores.insert(id, prepared);
                    Ok(())
                })
                .await
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(BackupEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn discard_restore(&self, id: String) -> Result<bool> {
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "discard_restore", move |state| {
                Ok(state.restores.remove(&id).is_some())
            })
            .await
    }
    pub async fn commit_restore(
        &self,
        id: String,
        task_id: String,
        sink: StreamSink<BackupEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id.clone())?;
            self.runtime.tasks.cancel_except(Some(&task_id))?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.write().await)
            })
            .await?;
            let token = task.token.clone();
            self.runtime
                .call(&task.token, "commit_restore", move |state| {
                    let prepared = state.restores.remove(&id).ok_or_else(|| {
                        OtterError::new(ErrorCode::NotFound, "restore preview missing")
                    })?;
                    state.close_pdfs()?;
                    let report = prepared.commit(&mut state.storage, &token, |progress| {
                        let _ = sink.add(BackupEvent::Progress { progress });
                    })?;
                    sink.add(BackupEvent::Restored {
                        report: report.into(),
                    })
                    .map_err(stream_closed)
                })
                .await
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(BackupEvent::Failed { error });
        }
        Ok(())
    }
}
fn stream_closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "backup stream closed")
}
