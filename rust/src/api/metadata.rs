use super::{Backend, document::directory, network_settings};
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    library::{identifier::MetadataResolver, metadata},
    storage::Document,
    sync::archive,
    tasks::cancellable,
};

pub enum MetadataStatus {
    None,
    Partial,
    Complete,
}
pub struct MetadataRepair {
    pub document: Document,
    pub status: MetadataStatus,
    pub warnings: Vec<ErrorCode>,
}
pub enum MetadataEvent {
    Failed { error: OtterError },
    ReadingPdf,
    ResolvingIdentifier,
    SearchingTitle,
    Completed { report: MetadataRepair },
}
pub struct MetadataRepairOptions {
    pub document_id: String,
    pub allow_network: bool,
}

pub(super) fn resolved(target: &mut Document, value: Document) {
    metadata::Metadata {
        title: Some(value.title),
        authors: value.authors,
        journal: value.journal,
        year: value.year,
        doi: value.doi,
    }
    .apply(target);
    if !value.keywords.is_empty() {
        target.keywords = value.keywords;
    }
}
/// 有 PDF 但元数据缺失或可疑（未拆分的「标题_作者」、作者混入非人名），需要修复。
#[flutter_rust_bridge::frb(sync)]
pub fn metadata_needs_repair(document: Document) -> bool {
    metadata::needs_repair(&document)
}

impl Backend {
    pub async fn resolve_identifier(&self, input: String, task_id: String) -> Result<Document> {
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
        MetadataResolver::new(crate::network::client(proxy.as_deref(), http2)?)
            .resolve(&input, &task.token)
            .await
    }
    pub async fn search_metadata(
        &self,
        title: String,
        author: Option<String>,
        task_id: String,
    ) -> Result<Option<Document>> {
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
        MetadataResolver::new(crate::network::client(proxy.as_deref(), http2)?)
            .search_by_title(&title, author.as_deref(), &task.token)
            .await
    }
    pub async fn repair_metadata(
        &self,
        options: MetadataRepairOptions,
        task_id: String,
        sink: StreamSink<MetadataEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            sink.add(MetadataEvent::ReadingPdf).map_err(closed)?;
            let token = task.token.clone();
            let (original, inspection, pdf, hash, proxy, http2) = self
                .runtime
                .call(&task.token, "inspect_metadata", move |state| {
                    let storage = state.storage()?;
                    let original = storage.document(&options.document_id)?.ok_or_else(|| {
                        OtterError::new(ErrorCode::NotFound, "metadata document missing")
                    })?;
                    let root = directory(storage, &options.document_id)?;
                    let pdf = root.join("source.pdf");
                    let (proxy, http2) = network_settings(storage)?;
                    let hash = if original.content_hash.is_some() {
                        Some(archive::hash_file(&pdf, &token)?)
                    } else {
                        None
                    };
                    let inspection = if hash.is_some() {
                        metadata::inspect_local(state.pdf()?, &pdf, &root, &original, &token)?
                    } else {
                        metadata::LocalInspection {
                            document: original.clone(),
                            identifier: None,
                            warnings: Vec::new(),
                        }
                    };
                    Ok((original, inspection, pdf, hash, proxy, http2))
                })
                .await?;
            let mut candidate = inspection.document;
            let mut warnings = inspection.warnings;
            if options.allow_network && hash.is_some() {
                let resolver =
                    MetadataResolver::new(crate::network::client(proxy.as_deref(), http2)?);
                if let Some(identifier) = inspection.identifier {
                    sink.add(MetadataEvent::ResolvingIdentifier)
                        .map_err(closed)?;
                    match resolver.resolve(&identifier.value, &task.token).await {
                        Ok(document) => resolved(&mut candidate, document),
                        Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                        Err(error) => warnings.push(error.code),
                    }
                }
                if !metadata::complete(&candidate)
                    && metadata::plausible_title(&candidate.title)
                    && candidate.title != candidate.id
                {
                    sink.add(MetadataEvent::SearchingTitle).map_err(closed)?;
                    match resolver
                        .search_by_title(
                            &candidate.title,
                            candidate.authors.first().map(String::as_str),
                            &task.token,
                        )
                        .await
                    {
                        Ok(Some(document)) => resolved(&mut candidate, document),
                        Ok(None) => {}
                        Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                        Err(error) => warnings.push(error.code),
                    }
                }
            }
            let token = task.token.clone();
            self.runtime
                .call(&task.token, "save_metadata", move |state| {
                    let storage = state.storage()?;
                    if storage.document(&original.id)?.as_ref() != Some(&original) {
                        return Err(OtterError::new(
                            ErrorCode::Conflict,
                            "document changed during metadata repair",
                        ));
                    }
                    if let Some(hash) = hash
                        && archive::hash_file(&pdf, &token)? != hash
                    {
                        return Err(OtterError::new(
                            ErrorCode::Conflict,
                            "PDF changed during metadata repair",
                        ));
                    }
                    let status = if metadata::same_core(&original, &candidate) {
                        MetadataStatus::None
                    } else if metadata::complete(&candidate) {
                        MetadataStatus::Complete
                    } else {
                        MetadataStatus::Partial
                    };
                    if candidate != original {
                        storage.put_document(&candidate)?;
                    }
                    sink.add(MetadataEvent::Completed {
                        report: MetadataRepair {
                            document: candidate,
                            status,
                            warnings,
                        },
                    })
                    .map_err(closed)
                })
                .await
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(MetadataEvent::Failed { error });
        }
        Ok(())
    }
}
fn closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "metadata stream closed")
}
