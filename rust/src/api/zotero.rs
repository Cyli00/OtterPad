use super::{Backend, network_settings};
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    sync::zotero::{
        self, FetchProgress, ImportCandidate, ImportReport, LocalLibrary, LocalSelection,
        ZoteroClient,
    },
    tasks::cancellable,
};
use flutter_rust_bridge::frb;
use std::path::PathBuf;

#[frb(opaque)]
pub struct LocalZoteroSnapshot {
    library: LocalLibrary,
}
#[frb(non_opaque)]
pub enum ZoteroEvent {
    Failed {
        error: OtterError,
    },
    Progress {
        progress: FetchProgress,
    },
    LocalReady {
        snapshot: LocalZoteroSnapshot,
        candidates: Vec<ImportCandidate>,
    },
    Imported {
        report: ImportReport,
    },
}
impl Backend {
    pub async fn sync_zotero(
        &self,
        full: bool,
        task_id: String,
        sink: StreamSink<ZoteroEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let key = self.runtime.credentials.get("zotero_api_key")?;
            let (proxy, http2) = self
                .runtime
                .call(&task.token, "network_settings", |state| {
                    network_settings(state.storage()?)
                })
                .await?;
            let client = ZoteroClient::new(proxy.as_deref(), http2)?;
            let user_id = client.user_id(&key, &task.token).await?;
            let since = self
                .runtime
                .call(&task.token, "zotero_cursor", move |state| {
                    zotero::cloud_since(state.storage()?, user_id, full)
                })
                .await?;
            let library = client
                .fetch_cloud(&key, user_id, since, &task.token, |progress| {
                    if sink.add(ZoteroEvent::Progress { progress }).is_err() {
                        task.token.cancel();
                    }
                })
                .await?;
            let token = task.token.clone();
            self.runtime
                .call(&task.token, "import_zotero", move |state| {
                    let report = zotero::import_cloud(
                        state.storage()?,
                        &library,
                        full,
                        &token,
                        |progress| {
                            if sink.add(ZoteroEvent::Progress { progress }).is_err() {
                                token.cancel();
                            }
                        },
                    )?;
                    sink.add(ZoteroEvent::Imported { report }).map_err(closed)
                })
                .await
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(ZoteroEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn fetch_local_zotero(
        &self,
        port: u16,
        task_id: String,
        sink: StreamSink<ZoteroEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let client = ZoteroClient::new(None, true)?;
            let library = client
                .fetch_local(port, &task.token, |progress| {
                    if sink.add(ZoteroEvent::Progress { progress }).is_err() {
                        task.token.cancel();
                    }
                })
                .await?;
            let candidates = zotero::local_candidates(
                &library.items,
                (time::OffsetDateTime::now_utc().unix_timestamp_nanos() / 1_000_000) as i64,
            );
            sink.add(ZoteroEvent::LocalReady {
                snapshot: LocalZoteroSnapshot { library },
                candidates,
            })
            .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(ZoteroEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn import_local_zotero(
        &self,
        snapshot: &LocalZoteroSnapshot,
        directory: Option<String>,
        selections: Vec<LocalSelection>,
        task_id: String,
        sink: StreamSink<ZoteroEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let client = ZoteroClient::new(None, true)?;
            let library = snapshot.library.clone();
            let token = task.token.clone();
            let handle = tokio::runtime::Handle::current();
            self.runtime
                .call(&task.token, "import_local_zotero", move |state| {
                    let directory = directory.map(PathBuf::from);
                    let report = handle.block_on(zotero::import_local(
                        state.storage()?,
                        &client,
                        &library,
                        directory.as_deref(),
                        &selections,
                        &token,
                        |progress| {
                            if sink.add(ZoteroEvent::Progress { progress }).is_err() {
                                token.cancel();
                            }
                        },
                    ))?;
                    sink.add(ZoteroEvent::Imported { report }).map_err(closed)
                })
                .await
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(ZoteroEvent::Failed { error });
        }
        Ok(())
    }
}
fn closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "Zotero stream closed")
}
