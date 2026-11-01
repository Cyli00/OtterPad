use super::document_directory;
use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
    storage::{Document, Storage},
    sync::archive,
};
use serde::{Deserialize, Serialize};
use std::{fs, path::Path};
use tokio_util::sync::CancellationToken;

#[derive(Serialize, Deserialize)]
struct Journal {
    version: u32,
    document: Document,
    previous: Option<Document>,
}

pub(super) fn prepare(storage: &Storage, stage: &Path, document: &Document) -> Result<()> {
    files::write_json(
        &stage.join("journal.json"),
        &Journal {
            version: 1,
            document: document.clone(),
            previous: storage.document(&document.id)?,
        },
    )?;
    sync_directory(stage.parent().unwrap())
}

/// Complete imports whose PDF was published before SQLite committed. The copied
/// input and journal survive an outer transaction rollback or a process crash.
pub fn recover_imports(storage: &Storage) -> Result<()> {
    for entry in fs::read_dir(storage.directory().join("library"))? {
        let entry = entry?;
        if !entry.file_type()?.is_dir()
            || !entry.file_name().to_string_lossy().starts_with(".import-")
        {
            continue;
        }
        let stage = entry.path();
        if !stage.join("journal.json").is_file() {
            // An unfinished copy has never published a PDF or metadata.
            fs::remove_dir_all(&stage)?;
            continue;
        }
        let journal: Journal = serde_json::from_slice(&fs::read(stage.join("journal.json"))?)?;
        let document = &journal.document;
        let directory = document_directory(storage, &document.id)?;
        let token = CancellationToken::new();
        let hash = archive::hash_file(&stage.join("source.pdf"), &token)?;
        if journal.version != 1 || document.content_hash.as_deref() != Some(&hash[..24]) {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "import journal fingerprint",
            ));
        }
        let transaction = storage.connection.unchecked_transaction()?;
        let current = storage.document(&document.id)?;
        if current.as_ref() != Some(document) && current != journal.previous && current.is_some() {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "import metadata changed",
            ));
        }
        fs::create_dir_all(&directory)?;
        if fs::symlink_metadata(&directory)?.file_type().is_symlink() {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "import directory symlink",
            ));
        }
        let target = directory.join("source.pdf");
        if target.exists() {
            if archive::hash_file(&target, &token)? != hash {
                return Err(OtterError::new(ErrorCode::Conflict, "import PDF changed"));
            }
        } else {
            fs::hard_link(stage.join("source.pdf"), &target)?;
            sync_directory(&directory)?;
        }
        if current.as_ref() != Some(document) {
            storage.put_document(document)?;
        }
        transaction.commit()?;
        fs::remove_dir_all(stage)?;
        sync_directory(directory.parent().unwrap())?;
    }
    Ok(())
}

pub(super) fn sync_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    fs::File::open(path)?.sync_all()?;
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn outer_transaction_rollback_keeps_pdf_and_recoverable_import_journal() {
        let root = tempdir().unwrap();
        let storage = Storage::open(root.path()).unwrap();
        let source = root.path().join("input.pdf");
        fs::write(
            &source,
            include_bytes!("../../tests/fixtures/two_pages.pdf"),
        )
        .unwrap();
        let transaction = storage.connection.unchecked_transaction().unwrap();
        let imported = crate::library::import_pdf(
            &storage,
            &source,
            Document {
                id: "recovered".into(),
                title: "Recovered PDF".into(),
                authors: vec![],
                journal: None,
                year: None,
                doi: None,
                keywords: vec![],
                content_hash: None,
                added_at: 1,
            },
            &CancellationToken::new(),
        )
        .unwrap()
        .document;
        transaction.rollback().unwrap();
        assert!(storage.document("recovered").unwrap().is_none());
        let target = storage.directory().join("library/recovered/source.pdf");
        assert_eq!(fs::read(&target).unwrap(), fs::read(&source).unwrap());
        recover_imports(&storage).unwrap();
        assert_eq!(storage.document("recovered").unwrap().unwrap(), imported);
        recover_imports(&storage).unwrap();
        assert_eq!(storage.documents(10, 0).unwrap().len(), 1);
        assert!(
            fs::read_dir(storage.directory().join("library"))
                .unwrap()
                .all(|entry| !entry
                    .unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".import-"))
        );
    }
}
