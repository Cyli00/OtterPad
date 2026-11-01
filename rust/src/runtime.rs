use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
    sync::{Arc, LazyLock, Mutex, mpsc},
};

use serde::{Deserialize, Serialize};
use tokio::sync::{RwLock, oneshot};
use tokio_util::sync::CancellationToken;

use crate::{
    ai::chat::ChatStore,
    credentials::Credentials,
    error::{ErrorCode, OtterError, Result},
    library,
    logging::{LogLevel, Logger},
    migrate::{self, MigrationProgress, MigrationReport},
    pdf::PdfService,
    storage::Storage,
    sync::backup::{self, PreparedRestore},
    tasks::{self, Tasks},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeConfig {
    /// <AppSupport>/OtterPad, containing the separate legacy and v2 namespaces.
    pub root: PathBuf,
    pub pdfium_library: Option<PathBuf>,
    pub bitmap_cache_bytes: usize,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Startup {
    pub directory: PathBuf,
    pub migration: Option<MigrationReport>,
    pub migration_error: Option<ErrorCode>,
}
type Job = Box<dyn FnOnce(&mut State) + Send>;
static ROOTS: LazyLock<Mutex<HashSet<PathBuf>>> = LazyLock::new(|| Mutex::new(HashSet::new()));
struct RootLease(PathBuf);
impl Drop for RootLease {
    fn drop(&mut self) {
        if let Ok(mut roots) = ROOTS.lock() {
            roots.remove(&self.0);
        }
    }
}

/// SQLite and PDFium handles live on one Rust worker, never on the Flutter isolate.
/// Long network work holds a shared lease; restore/delete require exclusive access.
pub struct Runtime {
    sender: mpsc::Sender<Job>,
    pub credentials: Credentials,
    pub tasks: Arc<Tasks>,
    pub(crate) operations: RwLock<()>,
    pub(crate) backups: tokio::sync::Mutex<()>,
    pub directory: PathBuf,
}
pub(crate) struct State {
    pub storage: Option<Storage>,
    pub pdf: Option<PdfService>,
    pub pdf_documents: HashMap<u64, String>,
    pub chats: Arc<ChatStore>,
    pub logger: Logger,
    pub restores: HashMap<String, PreparedRestore>,
    config: RuntimeConfig,
}
impl State {
    pub fn storage(&self) -> Result<&Storage> {
        self.storage
            .as_ref()
            .ok_or_else(|| OtterError::new(ErrorCode::Conflict, "storage unavailable"))
    }
    pub fn pdf(&mut self) -> Result<&mut PdfService> {
        if self.pdf.is_none() {
            let path =
                self.config.pdfium_library.as_ref().ok_or_else(|| {
                    OtterError::new(ErrorCode::Pdf, "PDFium library not configured")
                })?;
            self.pdf = Some(PdfService::new(path, self.config.bitmap_cache_bytes)?);
        }
        Ok(self.pdf.as_mut().unwrap())
    }
    pub fn close_pdfs(&mut self) -> Result<()> {
        if let Some(pdf) = &mut self.pdf {
            pdf.close_all()?;
        }
        self.pdf_documents.clear();
        Ok(())
    }
}
impl Runtime {
    pub async fn open(
        mut config: RuntimeConfig,
        tasks: Arc<Tasks>,
        token: CancellationToken,
        mut progress: impl FnMut(MigrationProgress) + Send + 'static,
    ) -> Result<(Arc<Self>, Startup)> {
        if !config.root.is_absolute() || config.bitmap_cache_bytes > 1024 * 1024 * 1024 {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "runtime root/cache limit",
            ));
        }
        tasks::check(&token)?;
        tokio::fs::create_dir_all(&config.root).await?;
        config.root = tokio::fs::canonicalize(&config.root).await?;
        {
            let mut roots = ROOTS
                .lock()
                .map_err(|_| OtterError::new(ErrorCode::Conflict, "runtime roots lock"))?;
            if !roots.insert(config.root.clone()) {
                return Err(OtterError::new(
                    ErrorCode::Conflict,
                    "runtime already open for root",
                ));
            }
        }
        let root_lease = RootLease(config.root.clone());
        let directory = config.root.join("v2");
        let (sender, receiver) = mpsc::channel::<Job>();
        let (ready_tx, ready_rx) = oneshot::channel();
        std::thread::Builder::new().name("otter-storage-pdf".into()).spawn(move || {
            let _root_lease=root_lease;
            let result=(||->Result<(State,Startup)> {
                tasks::check(&token)?;
                backup::recover(&config.root)?;
                let mut storage=Storage::open(&config.root)?;
                library::recover_replacements(&storage)?;
                library::recover_imports(&storage)?;
                library::recover_deletions(&storage)?;
                let logger=Logger::new(storage.directory().join("logs"));
                let mut startup=Startup{directory:storage.directory().to_owned(),migration:None,migration_error:None};
                let complete:bool=storage.connection.query_row("SELECT EXISTS(SELECT 1 FROM meta WHERE metaKey='migration:v1:complete' AND value='1')",[],|r|r.get(0))?;
                if !complete && config.root.join("db/otter.db").is_file() {
                    match migrate::run(&mut storage,&config.root,&token,&mut progress) {
                        Ok(report)=>startup.migration=Some(report),
                        Err(error)=>{
                            startup.migration_error=Some(error.code);
                            let _=logger.record(&storage,"migration",LogLevel::Error,Some(error.code));
                        }
                    }
                }
                let _=logger.record(&storage,"startup",LogLevel::Info,None);
                if storage.setting("general_cache_auto_cleanup")?.and_then(|v|v.as_bool()).unwrap_or(false)
                    && let Err(error)=crate::maintenance::clear(&storage,&[crate::maintenance::StorageGroup::Cache],&token) {
                    let _=logger.record(&storage,"cache_cleanup",LogLevel::Error,Some(error.code));
                }
                let chats=Arc::new(ChatStore::new(storage.directory().to_owned()));
                Ok((State{storage:Some(storage),pdf:None,pdf_documents:HashMap::new(),chats,logger,restores:HashMap::new(),config},startup))
            })();
            // The initialization stream must close after Ready, not with the worker.
            drop(progress);
            match result {
                Ok((mut state,startup))=> {
                    if ready_tx.send(Ok(startup)).is_err() {return;}
                    while let Ok(job)=receiver.recv() {job(&mut state);}
                },
                Err(error)=>{let _=ready_tx.send(Err(error));}
            }
        })?;
        let startup = ready_rx.await.map_err(|_| {
            OtterError::new(ErrorCode::Conflict, "runtime worker stopped during startup")
        })??;
        let runtime = Arc::new(Self {
            sender,
            credentials: Credentials::default(),
            tasks,
            operations: RwLock::new(()),
            backups: tokio::sync::Mutex::new(()),
            directory,
        });
        Ok((runtime, startup))
    }

    pub(crate) async fn call<T: Send + 'static>(
        &self,
        token: &CancellationToken,
        operation: &'static str,
        job: impl FnOnce(&mut State) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        tasks::check(token)?;
        let token_owned = token.clone();
        let (send, receive) = oneshot::channel();
        self.sender
            .send(Box::new(move |state| {
                let result = tasks::check(&token_owned).and_then(|_| job(state));
                if let Err(error) = &result
                    && let Ok(storage) = state.storage()
                {
                    let _ =
                        state
                            .logger
                            .record(storage, operation, LogLevel::Error, Some(error.code));
                }
                let _ = send.send(result);
            }))
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "runtime worker stopped"))?;
        tasks::cancellable(token, async {
            receive.await.map_err(|_| {
                OtterError::new(ErrorCode::Conflict, "runtime worker did not return")
            })?
        })
        .await
    }

    /// Short storage operations are serialized by the worker and participate in restore exclusion.
    pub async fn with_storage<T: Send + 'static>(
        &self,
        token: &CancellationToken,
        operation: &'static str,
        job: impl FnOnce(&Storage) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let _lease = tasks::cancellable(token, async { Ok(self.operations.read().await) }).await?;
        self.call(token, operation, move |state| job(state.storage()?))
            .await
    }
}
