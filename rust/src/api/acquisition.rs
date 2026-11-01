use super::{Backend, network_settings};
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    library::{
        self,
        fetch::{PdfFetcher, PdfSource},
        identifier::{self, IdentifierKind, MetadataResolver},
    },
    network::{TransferObserver, TransferProgress},
    storage::Document,
    sync::archive::{self, Stage},
    tasks::{self, cancellable},
};
use std::sync::Arc;
use tokio_util::sync::CancellationToken;

pub struct PdfDownloadOptions {
    pub document_id: String,
    /// DOI, PMID, arXiv identifier or direct PDF URL; omitted uses document DOI.
    pub input: Option<String>,
    pub replace_existing: bool,
}
pub struct PdfDownloadReport {
    pub document: Document,
    pub source: Option<PdfSource>,
    pub changed: bool,
    pub warnings: Vec<ErrorCode>,
}
pub enum AcquisitionEvent {
    Failed { error: OtterError },
    ResolvingMetadata,
    MetadataSaved { document: Document, duplicate: bool },
    Downloading { progress: TransferProgress },
    ValidatingPdf,
    Completed { report: PdfDownloadReport },
}

impl Backend {
    pub async fn import_local_pdf(
        &self,
        source: String,
        allow_network: bool,
        task_id: String,
        sink: StreamSink<AcquisitionEvent>,
    ) -> Result<()> {
        let sink = Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            sink.add(AcquisitionEvent::ValidatingPdf).map_err(closed)?;
            let path = std::path::PathBuf::from(source);
            let input = path.clone();
            let token = task.token.clone();
            let (mut document, identifier, mut warnings, proxy, http2) = self
                .runtime
                .call(&task.token, "inspect_import_pdf", move |state| {
                    let (proxy, http2) = network_settings(state.storage()?)?;
                    let mut document = Document {
                        id: String::new(),
                        title: input
                            .file_stem()
                            .unwrap_or_default()
                            .to_string_lossy()
                            .into_owned(),
                        authors: Vec::new(),
                        journal: None,
                        year: None,
                        doi: None,
                        keywords: Vec::new(),
                        content_hash: None,
                        added_at: (time::OffsetDateTime::now_utc().unix_timestamp_nanos()
                            / 1_000_000) as i64,
                    };
                    library::metadata::parse_filename(&input.to_string_lossy())
                        .apply(&mut document);
                    let directory = state.storage()?.directory().to_owned();
                    match state.pdf().and_then(|pdf| {
                        library::metadata::inspect_local(pdf, &input, &directory, &document, &token)
                    }) {
                        Ok(inspected) => Ok((
                            inspected.document,
                            inspected.identifier,
                            inspected.warnings,
                            proxy,
                            http2,
                        )),
                        Err(error) if error.code == ErrorCode::Pdf => {
                            Ok((document, None, vec![error.code], proxy, http2))
                        }
                        Err(error) => Err(error),
                    }
                })
                .await?;
            if allow_network {
                let resolver =
                    MetadataResolver::new(crate::network::client(proxy.as_deref(), http2)?);
                sink.add(AcquisitionEvent::ResolvingMetadata)
                    .map_err(closed)?;
                if let Some(identifier) = identifier {
                    match resolver.resolve(&identifier.value, &task.token).await {
                        Ok(resolved) => super::metadata::resolved(&mut document, resolved),
                        Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                        Err(error) => warnings.push(error.code),
                    }
                }
                if !library::metadata::complete(&document)
                    && library::metadata::plausible_title(&document.title)
                {
                    match resolver
                        .search_by_title(
                            &document.title,
                            document.authors.first().map(String::as_str),
                            &task.token,
                        )
                        .await
                    {
                        Ok(Some(resolved)) => super::metadata::resolved(&mut document, resolved),
                        Ok(None) => {}
                        Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                        Err(error) => warnings.push(error.code),
                    }
                }
            }
            let token = task.token.clone();
            let result = self
                .runtime
                .call(&task.token, "import_local_pdf", move |state| {
                    library::import_pdf(state.storage()?, &path, document, &token)
                })
                .await?;
            sink.add(AcquisitionEvent::MetadataSaved {
                document: result.document.clone(),
                duplicate: result.duplicate,
            })
            .map_err(closed)?;
            sink.add(AcquisitionEvent::Completed {
                report: PdfDownloadReport {
                    document: result.document,
                    source: None,
                    changed: !result.duplicate,
                    warnings,
                },
            })
            .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(AcquisitionEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn download_document_pdf(
        &self,
        options: PdfDownloadOptions,
        task_id: String,
        sink: StreamSink<AcquisitionEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let report = acquire(self, options, &task.token, sink.clone()).await?;
            sink.add(AcquisitionEvent::Completed { report })
                .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(AcquisitionEvent::Failed { error });
        }
        Ok(())
    }

    /// Metadata is committed before acquisition, so a failed or cancelled PDF
    /// download leaves a usable bibliographic record that can be retried.
    pub async fn import_identifier(
        &self,
        input: String,
        download_pdf: bool,
        task_id: String,
        sink: StreamSink<AcquisitionEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            sink.add(AcquisitionEvent::ResolvingMetadata)
                .map_err(closed)?;
            let lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let (proxy, http2) = self
                .runtime
                .call(&task.token, "network_settings", |state| {
                    network_settings(state.storage()?)
                })
                .await?;
            let candidate = MetadataResolver::new(crate::network::client(proxy.as_deref(), http2)?)
                .resolve(&input, &task.token)
                .await?;
            let (document, duplicate) = self
                .runtime
                .call(&task.token, "import_identifier", move |state| {
                    let storage = state.storage()?;
                    if let Some(existing) = storage
                        .documents(u32::MAX, 0)?
                        .into_iter()
                        .find(|existing| library::metadata::duplicate(existing, &candidate))
                    {
                        return Ok((existing, true));
                    }
                    if storage.document(&candidate.id)?.is_some() {
                        return Err(OtterError::new(
                            ErrorCode::Conflict,
                            "identifier document ID already exists",
                        ));
                    }
                    storage.put_document(&candidate)?;
                    Ok((candidate, false))
                })
                .await?;
            sink.add(AcquisitionEvent::MetadataSaved {
                document: document.clone(),
                duplicate,
            })
            .map_err(closed)?;
            drop(lease);
            let report = if download_pdf {
                acquire(
                    self,
                    PdfDownloadOptions {
                        document_id: document.id,
                        input: Some(input),
                        replace_existing: false,
                    },
                    &task.token,
                    sink.clone(),
                )
                .await?
            } else {
                PdfDownloadReport {
                    document,
                    source: None,
                    changed: false,
                    warnings: Vec::new(),
                }
            };
            sink.add(AcquisitionEvent::Completed { report })
                .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(AcquisitionEvent::Failed { error });
        }
        Ok(())
    }
}

async fn acquire(
    backend: &Backend,
    options: PdfDownloadOptions,
    token: &CancellationToken,
    sink: Arc<StreamSink<AcquisitionEvent>>,
) -> Result<PdfDownloadReport> {
    let lease = cancellable(token, async { Ok(backend.runtime.operations.read().await) }).await?;
    let id = options.document_id;
    let check_token = token.clone();
    let (original, previous_hash, proxy, http2, stage) = backend
        .runtime
        .call(token, "prepare_pdf_download", move |state| {
            let storage = state.storage()?;
            let original = storage
                .document(&id)?
                .ok_or_else(|| OtterError::new(ErrorCode::NotFound, "download document missing"))?;
            let path = library::document_directory(storage, &id)?.join("source.pdf");
            let hash = if path.is_file() {
                Some(archive::hash_file(&path, &check_token)?)
            } else {
                None
            };
            let (proxy, http2) = network_settings(storage)?;
            let stage = Stage::new(storage.directory(), "document-download")?;
            Ok((original, hash, proxy, http2, stage))
        })
        .await?;
    if previous_hash.is_some() && !options.replace_existing {
        return Ok(PdfDownloadReport {
            document: original,
            source: None,
            changed: false,
            warnings: Vec::new(),
        });
    }
    let input = options
        .input
        .or_else(|| original.doi.clone())
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "PDF identifier missing"))?;
    let progress_sink = sink.clone();
    let progress_token = token.clone();
    let progress: TransferObserver = Arc::new(move |progress| {
        if progress_sink
            .add(AcquisitionEvent::Downloading { progress })
            .is_err()
        {
            progress_token.cancel();
        }
    });
    let fetcher = PdfFetcher::new(crate::network::client(proxy.as_deref(), http2)?);
    let path = stage.path.join("source.pdf");
    let identifier = identifier::parse(&input);
    let fetched = match identifier.kind {
        IdentifierKind::Doi => {
            fetcher
                .fetch_doi(&identifier.value, &path, token, Some(&progress))
                .await?
        }
        IdentifierKind::Pmid => {
            fetcher
                .fetch_pmid(&identifier.value, &path, token, Some(&progress))
                .await?
        }
        IdentifierKind::Arxiv => {
            fetcher
                .fetch_url(
                    &format!("https://arxiv.org/pdf/{}", identifier.value),
                    &path,
                    token,
                    Some(&progress),
                )
                .await?
        }
        IdentifierKind::Unknown
            if input.starts_with("https://") || input.starts_with("http://") =>
        {
            fetcher
                .fetch_url(&input, &path, token, Some(&progress))
                .await?
        }
        _ => {
            return Err(OtterError::new(
                ErrorCode::Unsupported,
                "identifier has no PDF source",
            ));
        }
    };
    sink.add(AcquisitionEvent::ValidatingPdf).map_err(closed)?;
    let validate_path = path.clone();
    let validate_token = token.clone();
    backend
        .runtime
        .call(token, "validate_downloaded_pdf", move |state| {
            let pdf = state.pdf()?;
            let info = pdf.open(&validate_path, None, &validate_token)?;
            pdf.close(info.handle)?;
            if info.pages.is_empty() {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "downloaded PDF has no pages",
                ));
            }
            Ok(())
        })
        .await?;
    drop(lease);
    let _lease = cancellable(token, async {
        Ok(backend.runtime.operations.write().await)
    })
    .await?;
    let commit_token = token.clone();
    let previous_fingerprint = previous_hash.as_deref().map(|hash| hash[..24].to_owned());
    let document = backend
        .runtime
        .call(token, "commit_downloaded_pdf", move |state| {
            // The stage must live through the worker job even if its awaiting future
            // is cancelled during the filesystem/SQLite commit.
            let _stage = stage;
            let storage = state.storage()?;
            let current_path =
                library::document_directory(storage, &original.id)?.join("source.pdf");
            let current_hash = if current_path.is_file() {
                Some(archive::hash_file(&current_path, &commit_token)?)
            } else {
                None
            };
            if current_hash != previous_hash
                || storage.document(&original.id)?.as_ref() != Some(&original)
            {
                return Err(OtterError::new(
                    ErrorCode::Conflict,
                    "document changed during PDF download",
                ));
            }
            let handles: Vec<_> = state
                .pdf_documents
                .iter()
                .filter(|(_, document)| **document == original.id)
                .map(|(handle, _)| *handle)
                .collect();
            for handle in handles {
                state.pdf()?.close(handle)?;
                state.pdf_documents.remove(&handle);
            }
            library::replace_pdf(state.storage()?, &path, &original, &commit_token)
        })
        .await?;
    tasks::check(token)?;
    Ok(PdfDownloadReport {
        changed: document.content_hash != previous_fingerprint,
        document,
        source: Some(fetched.source),
        warnings: fetched.warnings,
    })
}

fn closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "acquisition stream closed")
}
