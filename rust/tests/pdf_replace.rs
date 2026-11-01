use otter_core::{
    error::ErrorCode,
    library::{self, Highlight},
    storage::{Document, Storage},
};
use serde_json::json;
use std::{fs, path::Path};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn populate(root: &Path) -> (Storage, Document) {
    let storage = Storage::open(root).unwrap();
    let source = root.join("original.pdf");
    fs::write(&source, include_bytes!("fixtures/two_pages.pdf")).unwrap();
    let document = Document {
        id: "paper".into(),
        title: "Paper".into(),
        authors: vec![],
        journal: None,
        year: None,
        doi: None,
        keywords: vec![],
        content_hash: None,
        added_at: 1,
    };
    let document = library::import_pdf(&storage, &source, document, &CancellationToken::new())
        .unwrap()
        .document;
    let directory = storage.directory().join("library/paper");
    fs::create_dir_all(directory.join("chats")).unwrap();
    fs::write(
        directory.join("chats/legacy-session.json"),
        include_bytes!("fixtures/chat-v017.json"),
    )
    .unwrap();
    fs::write(directory.join("user.txt"), b"User exported notes").unwrap();
    fs::write(
        directory.join("document.json"),
        serde_json::to_vec(&otter_core::document::DocumentModel::from_markdown(
            "Old parsed content",
        ))
        .unwrap(),
    )
    .unwrap();
    fs::write(
        directory.join("translations.json"),
        json!({"zh":{"old":"cached translation"}}).to_string(),
    )
    .unwrap();
    library::put_highlight(
        &storage,
        &Highlight {
            id: "note".into(),
            document_id: "paper".into(),
            content: "Old parsed content".into(),
            note: Some("User note".into()),
            color: "yellow".into(),
            group_id: None,
            anchor: Some(json!({"quote":"Old parsed content"})),
            created_at: 1,
        },
    )
    .unwrap();
    (storage, document)
}
fn newer(root: &Path) -> std::path::PathBuf {
    let mut bytes = include_bytes!("fixtures/two_pages.pdf").to_vec();
    bytes.extend_from_slice(b"\n% New downloaded revision\n");
    let path = root.join("new.pdf");
    fs::write(&path, bytes).unwrap();
    path
}

#[test]
fn changed_pdf_invalidates_generated_assets_but_preserves_notes_chats_and_user_files() {
    let root = tempdir().unwrap();
    let (storage, original) = populate(root.path());
    let source = newer(root.path());
    let replaced =
        library::replace_pdf(&storage, &source, &original, &CancellationToken::new()).unwrap();
    assert_ne!(replaced.content_hash, original.content_hash);
    let directory = storage.directory().join("library/paper");
    assert_eq!(
        fs::read(directory.join("source.pdf")).unwrap(),
        fs::read(&source).unwrap()
    );
    assert!(!directory.join("document.json").exists());
    assert!(!directory.join("translations.json").exists());
    assert_eq!(
        fs::read(directory.join("chats/legacy-session.json")).unwrap(),
        include_bytes!("fixtures/chat-v017.json")
    );
    assert_eq!(
        fs::read(directory.join("user.txt")).unwrap(),
        b"User exported notes"
    );
    assert_eq!(
        library::highlights(&storage, "paper").unwrap()[0]
            .note
            .as_deref(),
        Some("User note")
    );
    assert_eq!(storage.document("paper").unwrap().unwrap(), replaced);
}

#[test]
fn deferred_commit_failure_restores_old_pdf_and_preserves_new_uncommitted_copy() {
    let root = tempdir().unwrap();
    let (storage, original) = populate(root.path());
    let connection = rusqlite::Connection::open(storage.directory().join("otter.db")).unwrap();
    connection.execute_batch("CREATE TABLE commit_failure(docId TEXT REFERENCES documents(id) DEFERRABLE INITIALLY DEFERRED); CREATE TRIGGER fail_pdf_commit AFTER UPDATE ON documents BEGIN INSERT INTO commit_failure VALUES ('absent'); END;").unwrap();
    let source = newer(root.path());
    assert_eq!(
        library::replace_pdf(&storage, &source, &original, &CancellationToken::new())
            .unwrap_err()
            .code,
        ErrorCode::Conflict
    );
    assert_eq!(storage.document("paper").unwrap().unwrap(), original);
    let directory = storage.directory().join("library/paper");
    assert_eq!(
        fs::read(directory.join("source.pdf")).unwrap(),
        include_bytes!("fixtures/two_pages.pdf")
    );
    assert!(directory.join("document.json").exists());
    assert!(directory.join("translations.json").exists());
    let uncommitted = storage
        .directory()
        .read_dir()
        .unwrap()
        .map(|e| e.unwrap().path())
        .find(|p| {
            p.file_name()
                .unwrap()
                .to_string_lossy()
                .ends_with(".uncommitted")
        })
        .unwrap();
    assert_eq!(
        fs::read(uncommitted.join("source.pdf")).unwrap(),
        fs::read(&source).unwrap()
    );
    connection
        .execute_batch("DROP TRIGGER fail_pdf_commit;")
        .unwrap();
    library::replace_pdf(&storage, &source, &original, &CancellationToken::new()).unwrap();
    assert_eq!(library::highlights(&storage, "paper").unwrap().len(), 1);
}

#[test]
fn same_pdf_keeps_caches_and_recovery_rolls_back_a_directory_published_before_sqlite_commit() {
    let root = tempdir().unwrap();
    let (storage, original) = populate(root.path());
    let directory = storage.directory().join("library/paper");
    assert_eq!(
        library::replace_pdf(
            &storage,
            &directory.join("source.pdf"),
            &original,
            &CancellationToken::new()
        )
        .unwrap(),
        original
    );
    assert!(directory.join("document.json").exists());
    let stage_name = ".pdf-replace-interrupted";
    let previous = format!("{stage_name}.previous");
    let source = newer(root.path());
    use sha2::{Digest, Sha256};
    let hash = Sha256::digest(fs::read(&source).unwrap())
        .iter()
        .take(12)
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    fs::write(storage.directory().join(".pdf-replace-paper.json"),json!({"version":1,"document_id":"paper","stage":stage_name,"previous":previous,"new_hash":hash,"had_directory":true}).to_string()).unwrap();
    fs::rename(&directory, storage.directory().join(&previous)).unwrap();
    fs::create_dir_all(&directory).unwrap();
    fs::copy(&source, directory.join("source.pdf")).unwrap();
    library::recover_replacements(&storage).unwrap();
    assert_eq!(storage.document("paper").unwrap().unwrap(), original);
    assert_eq!(
        fs::read(directory.join("source.pdf")).unwrap(),
        include_bytes!("fixtures/two_pages.pdf")
    );
    assert!(!storage.directory().join(".pdf-replace-paper.json").exists());
    assert!(directory.join("chats/legacy-session.json").is_file());
}
