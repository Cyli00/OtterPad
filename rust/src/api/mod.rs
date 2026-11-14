pub mod acquisition;
pub mod ai;
pub mod backup;
pub mod chat;
pub mod document;
pub mod library;
pub mod metadata;
pub mod ocr;
pub mod pdf;
pub mod remote;
pub mod settings;
pub mod sync;
pub mod translate;
pub mod types;
pub mod update;
pub mod zotero;

use crate::{
    credentials::CredentialInput,
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    migrate::{MigrationProgress, MigrationReport},
    runtime::{Runtime, RuntimeConfig},
    tasks::Tasks,
};
use flutter_rust_bridge::frb;
use std::{
    path::PathBuf,
    sync::{Arc, LazyLock},
};

static TASKS: LazyLock<Arc<Tasks>> = LazyLock::new(|| Arc::new(Tasks::default()));

#[frb(opaque)]
pub struct Backend {
    pub(crate) runtime: Arc<Runtime>,
}

pub struct BackendOptions {
    pub root: String,
    pub pdfium_library: Option<String>,
    pub bitmap_cache_bytes: u64,
}
#[frb(non_opaque)]
pub enum InitializationEvent {
    Failed {
        error: OtterError,
    },
    Migration {
        progress: MigrationProgress,
    },
    Ready {
        backend: Backend,
        directory: String,
        migration: Option<MigrationReport>,
        migration_error: Option<ErrorCode>,
    },
}

pub(crate) fn network_settings(
    storage: &crate::storage::Storage,
) -> Result<(Option<String>, bool)> {
    let mode = storage
        .setting("proxy_mode")?
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_else(|| "system".into());
    let proxy = match mode.as_str() {
        "none" => Some(String::new()),
        "custom" => {
            let host = storage
                .setting("proxy_host")?
                .and_then(|v| v.as_str().map(str::to_owned))
                .unwrap_or_else(|| "127.0.0.1".into());
            let port = storage
                .setting("proxy_port")?
                .and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
                .unwrap_or(7897);
            if port == 0 || port > 65535 || host.is_empty() || host.contains(['/', '@', '?', '#']) {
                return Err(OtterError::new(
                    ErrorCode::InvalidArgument,
                    "custom proxy address",
                ));
            }
            let host = if host.contains(':') && !host.starts_with('[') {
                format!("[{host}]")
            } else {
                host
            };
            Some(format!("http://{host}:{port}"))
        }
        "system" => None,
        _ => return Err(OtterError::new(ErrorCode::InvalidArgument, "proxy mode")),
    };
    let http2 = storage
        .setting("general_http2_enabled")?
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    Ok((proxy, http2))
}

pub async fn initialize(
    options: BackendOptions,
    task_id: String,
    sink: StreamSink<InitializationEvent>,
) -> Result<()> {
    let sink = std::sync::Arc::new(sink);
    let failure_sink = sink.clone();
    let result: Result<()> = async move {
        let task = TASKS.begin(task_id)?;
        let progress_sink = sink.clone();
        let token = task.token.clone();
        let progress_token = token.clone();
        let (runtime, startup) = Runtime::open(
            RuntimeConfig {
                root: PathBuf::from(options.root),
                pdfium_library: options.pdfium_library.map(PathBuf::from),
                bitmap_cache_bytes: usize::try_from(options.bitmap_cache_bytes).map_err(|_| {
                    OtterError::new(ErrorCode::InvalidArgument, "bitmap cache range")
                })?,
            },
            TASKS.clone(),
            token,
            move |progress| {
                if progress_sink
                    .add(InitializationEvent::Migration { progress })
                    .is_err()
                {
                    progress_token.cancel();
                }
            },
        )
        .await?;
        sink.add(InitializationEvent::Ready {
            backend: Backend { runtime },
            directory: startup.directory.to_string_lossy().into_owned(),
            migration: startup.migration,
            migration_error: startup.migration_error,
        })
        .map_err(|_| OtterError::new(ErrorCode::Cancelled, "initialization stream closed"))?;
        Ok(())
    }
    .await;
    if let Err(error) = result {
        let _ = failure_sink.add(InitializationEvent::Failed { error });
    }
    Ok(())
}

#[frb(sync)]
pub fn cancel_task(task_id: String) -> Result<bool> {
    TASKS.cancel(&task_id)
}

impl Backend {
    pub async fn close(&self) -> Result<()> {
        self.runtime.tasks.cancel_except(None)?;
        let _lease = self.runtime.operations.write().await;
        self.runtime
            .call(&Default::default(), "close", |state| {
                state.close_pdfs()?;
                state.pdf.take();
                state.restores.clear();
                state.storage.take();
                Ok(())
            })
            .await?;
        self.runtime.credentials.clear()
    }
    pub fn inject_credentials(&self, entries: Vec<CredentialInput>) -> Result<()> {
        self.runtime.credentials.inject(entries)
    }
    /// 已存凭据（启动时由 Dart 读入，供设置页回显）。
    pub fn credentials(&self) -> Result<Vec<CredentialInput>> {
        self.runtime.credentials.entries()
    }
    pub fn clear_credentials(&self) -> Result<()> {
        self.runtime.credentials.clear()
    }
    pub fn cancel_tasks(&self) -> Result<u32> {
        self.runtime.tasks.cancel_except(None)
    }
    pub async fn log_files(&self) -> Result<Vec<String>> {
        let runtime = &self.runtime;
        let _lease = runtime.operations.read().await;
        runtime
            .call(&Default::default(), "list_logs", |state| {
                Ok(state
                    .logger
                    .files()?
                    .into_iter()
                    .map(|p| p.to_string_lossy().into_owned())
                    .collect())
            })
            .await
    }
    pub async fn clear_logs(&self) -> Result<()> {
        let runtime = &self.runtime;
        let _lease = runtime.operations.read().await;
        runtime
            .call(&Default::default(), "clear_logs", |state| {
                state.logger.clear()
            })
            .await
    }
}
