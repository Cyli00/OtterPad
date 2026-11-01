use super::{
    Backend,
    types::{JsonData, JsonEntry, Note},
};
use crate::{
    error::{ErrorCode, OtterError, Result},
    library::{self, Favorite, History, ImportResult},
    storage::Document,
    tasks::cancellable,
};
use std::path::PathBuf;

impl Backend {
    pub async fn documents(&self, limit: u32, offset: u32) -> Result<Vec<Document>> {
        self.runtime
            .with_storage(&Default::default(), "documents", move |s| {
                s.documents(limit, offset)
            })
            .await
    }
    pub async fn document(&self, id: String) -> Result<Option<Document>> {
        self.runtime
            .with_storage(&Default::default(), "document", move |s| s.document(&id))
            .await
    }
    pub async fn search_library(&self, query: String, limit: u32) -> Result<Vec<Document>> {
        self.runtime
            .with_storage(&Default::default(), "search_library", move |s| {
                s.search_documents(&query, limit)
            })
            .await
    }
    pub async fn put_document(&self, document: Document) -> Result<()> {
        self.runtime
            .with_storage(&Default::default(), "put_document", move |s| {
                s.put_document(&document)
            })
            .await
    }
    pub async fn import_pdf(
        &self,
        source: String,
        document: Document,
        task_id: String,
    ) -> Result<ImportResult> {
        let task = self.runtime.tasks.begin(task_id)?;
        let token = task.token.clone();
        self.runtime
            .with_storage(&task.token, "import_pdf", move |s| {
                library::import_pdf(s, &PathBuf::from(source), document, &token)
            })
            .await
    }
    pub async fn delete_document(&self, id: String, task_id: String) -> Result<bool> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.write().await)
        })
        .await?;
        self.runtime
            .call(&task.token, "delete_document", move |state| {
                let handles: Vec<_> = state
                    .pdf_documents
                    .iter()
                    .filter(|(_, doc)| **doc == id)
                    .map(|(handle, _)| *handle)
                    .collect();
                for handle in handles {
                    state.pdf()?.close(handle)?;
                    state.pdf_documents.remove(&handle);
                }
                library::delete_document(state.storage()?, &id)
            })
            .await
    }
    pub async fn attach_pdf(
        &self,
        document_id: String,
        source: String,
        replace_existing: bool,
        task_id: String,
    ) -> Result<Document> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.write().await)
        })
        .await?;
        let token = task.token.clone();
        self.runtime
            .call(&task.token, "attach_pdf", move |state| {
                let storage = state.storage()?;
                let original = storage.document(&document_id)?.ok_or_else(|| {
                    OtterError::new(ErrorCode::NotFound, "attachment document missing")
                })?;
                let directory = library::document_directory(storage, &document_id)?;
                if directory.join("source.pdf").is_file() && !replace_existing {
                    return Ok(original);
                }
                let handles: Vec<_> = state
                    .pdf_documents
                    .iter()
                    .filter(|(_, id)| **id == document_id)
                    .map(|(handle, _)| *handle)
                    .collect();
                for handle in handles {
                    state.pdf()?.close(handle)?;
                    state.pdf_documents.remove(&handle);
                }
                let mut document = library::replace_pdf(
                    state.storage()?,
                    &PathBuf::from(&source),
                    &original,
                    &token,
                )?;
                if library::metadata::needs_repair(&document) {
                    library::metadata::parse_filename(&source).apply(&mut document);
                    match state.pdf().and_then(|pdf| {
                        library::metadata::inspect_local(
                            pdf,
                            &directory.join("source.pdf"),
                            &directory,
                            &document,
                            &token,
                        )
                    }) {
                        Ok(inspected) => document = inspected.document,
                        Err(error) if error.code == ErrorCode::Pdf => {}
                        Err(error) => return Err(error),
                    }
                    state.storage()?.put_document(&document)?;
                }
                Ok(document)
            })
            .await
    }
    pub async fn setting(&self, key: String) -> Result<Option<JsonData>> {
        self.runtime
            .with_storage(&Default::default(), "setting", move |s| {
                Ok(s.setting(&key)?.map(JsonData::from_value))
            })
            .await
    }
    /// 全部设置，供 Dart 启动时一次性载入同步读缓存。
    pub async fn settings(&self) -> Result<Vec<JsonEntry>> {
        self.runtime
            .with_storage(&Default::default(), "settings", |s| {
                Ok(s.settings()?
                    .into_iter()
                    .map(|(key, value)| JsonEntry {
                        key,
                        value: JsonData::from_value(value),
                    })
                    .collect())
            })
            .await
    }
    pub async fn put_setting(&self, key: String, value: JsonData) -> Result<()> {
        let value = value.into_value()?;
        self.runtime
            .with_storage(&Default::default(), "put_setting", move |s| {
                s.put_setting(&key, &value)
            })
            .await
    }
    pub async fn delete_setting(&self, key: String) -> Result<()> {
        self.runtime
            .with_storage(&Default::default(), "delete_setting", move |s| {
                s.delete_setting(&key)
            })
            .await
    }
    pub async fn favorites(&self) -> Result<Vec<Favorite>> {
        self.runtime
            .with_storage(&Default::default(), "favorites", library::favorites)
            .await
    }
    pub async fn put_favorite(&self, favorite: Favorite) -> Result<()> {
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "put_favorite", move |state| {
                library::put_favorite(
                    state.storage.as_mut().ok_or_else(|| {
                        crate::error::OtterError::new(
                            crate::error::ErrorCode::Conflict,
                            "storage unavailable",
                        )
                    })?,
                    &favorite,
                )
            })
            .await
    }
    pub async fn delete_favorite(&self, id: String) -> Result<bool> {
        self.runtime
            .with_storage(&Default::default(), "delete_favorite", move |s| {
                library::delete_favorite(s, &id)
            })
            .await
    }
    pub async fn favorite_document(
        &self,
        favorite: String,
        document: String,
        add: bool,
    ) -> Result<()> {
        self.runtime
            .with_storage(&Default::default(), "favorite_document", move |s| {
                library::favorite_document(s, &favorite, &document, add)
            })
            .await
    }
    pub async fn history(&self, limit: u32, offset: u32) -> Result<Vec<History>> {
        self.runtime
            .with_storage(&Default::default(), "history", move |s| {
                library::history(s, limit, offset)
            })
            .await
    }
    pub async fn record_history(&self, entry: History) -> Result<()> {
        self.runtime
            .with_storage(&Default::default(), "record_history", move |s| {
                library::record_history(s, &entry)
            })
            .await
    }
    pub async fn clear_history(&self, document: Option<String>) -> Result<()> {
        self.runtime
            .with_storage(&Default::default(), "clear_history", move |s| {
                library::clear_history(s, document.as_deref())
            })
            .await
    }
    pub async fn notes(&self, document: String) -> Result<Vec<Note>> {
        self.runtime
            .with_storage(&Default::default(), "notes", move |s| {
                Ok(library::highlights(s, &document)?
                    .into_iter()
                    .map(Note::from_highlight)
                    .collect())
            })
            .await
    }
    pub async fn put_note(&self, note: Note) -> Result<()> {
        let note = note.into_highlight()?;
        self.runtime
            .with_storage(&Default::default(), "put_note", move |s| {
                library::put_highlight(s, &note)
            })
            .await
    }
    pub async fn delete_note(&self, id: String) -> Result<bool> {
        self.runtime
            .with_storage(&Default::default(), "delete_note", move |s| {
                library::delete_highlight(s, &id)
            })
            .await
    }
}
