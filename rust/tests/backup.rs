use otter_core::{
    error::ErrorCode,
    storage::{Document, Storage},
    sync::archive::{self, BackupScope, BackupStage},
};
use std::{
    fs,
    io::{Read, Write},
};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;
use zip::{ZipArchive, ZipWriter, write::SimpleFileOptions};

fn populate(storage: &Storage) {
    storage
        .put_document(&Document {
            id: "paper".into(),
            title: "纸张 Paper".into(),
            authors: vec!["Author".into()],
            journal: None,
            year: Some("2025".into()),
            doi: None,
            keywords: Vec::new(),
            content_hash: Some("fingerprint".into()),
            added_at: 1,
        })
        .unwrap();
    let document = storage.directory().join("library/paper");
    fs::create_dir_all(document.join("chats")).unwrap();
    fs::create_dir_all(document.join("ocr/generation")).unwrap();
    for (name, bytes) in [
        ("source.pdf", b"%PDF-1.7\nsource".as_slice()),
        ("extract.raw.md", b"Full text"),
        ("translations.json", br#"{"zh":{"hash":"translated"}}"#),
        ("chats/conversation.json", br#"{"id":"conversation"}"#),
        ("ocr-current.json", br#"{"generation":"generation"}"#),
        (
            "ocr/generation/document.json",
            br#"{"version":1,"blocks":[]}"#,
        ),
    ] {
        fs::write(document.join(name), bytes).unwrap();
    }
    fs::create_dir_all(storage.directory().join("library/.trash/removed")).unwrap();
    fs::write(
        storage
            .directory()
            .join("library/.trash/removed/source.pdf"),
        b"trash",
    )
    .unwrap();
}

#[test]
fn real_sqlite_snapshot_and_file_checksums_roundtrip_full_and_data_only_archives() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path().join("live")).unwrap();
    populate(&storage);
    let token = CancellationToken::new();
    for scope in [BackupScope::Full, BackupScope::DataOnly] {
        let path = root.path().join(format!("export/{scope:?}.zip"));
        let manifest = archive::create(
            &storage,
            &path,
            scope,
            Some("Test device".into()),
            &token,
            |_| {},
        )
        .unwrap();
        assert_eq!(manifest.format_version, 4);
        let extracted = archive::extract(&path, root.path(), &token, |_| {}).unwrap();
        assert_eq!(extracted.manifest.scope, scope);
        assert_eq!(
            extracted.manifest.device_name.as_deref(),
            Some("Test device")
        );
        let database =
            rusqlite::Connection::open(extracted.directory().join("db/otter.db")).unwrap();
        assert_eq!(
            database
                .query_row("SELECT title FROM documents WHERE id='paper'", [], |r| {
                    r.get::<_, String>(0)
                })
                .unwrap(),
            "纸张 Paper"
        );
        let library = extracted.directory().join("library");
        assert_eq!(
            fs::read(library.join("paper/chats/conversation.json")).unwrap(),
            br#"{"id":"conversation"}"#
        );
        assert!(library.join("paper/translations.json").is_file());
        assert!(!library.join(".trash").exists());
        assert_eq!(
            library.join("paper/source.pdf").is_file(),
            scope == BackupScope::Full
        );
        assert_eq!(
            library.join("paper/ocr/generation/document.json").is_file(),
            scope == BackupScope::Full
        );
        assert_eq!(
            library.join("paper/ocr-current.json").is_file(),
            scope == BackupScope::Full
        );
    }
}

#[test]
fn mutation_during_backup_fails_without_overwriting_previous_archive() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path().join("live")).unwrap();
    populate(&storage);
    let target = root.path().join("archive.zip");
    fs::write(&target, b"previous valid backup").unwrap();
    let token = CancellationToken::new();
    let mut changed = false;
    let error = archive::create(
        &storage,
        &target,
        BackupScope::Full,
        None,
        &token,
        |progress| {
            if matches!(progress.stage, BackupStage::Pack) && !changed {
                changed = true;
                fs::write(
                    storage.directory().join("library/paper/source.pdf"),
                    b"changed during backup",
                )
                .unwrap();
            }
        },
    )
    .unwrap_err();
    assert_eq!(error.code, ErrorCode::Conflict);
    assert_eq!(fs::read(target).unwrap(), b"previous valid backup");
}

#[test]
fn archive_rejects_path_traversal_and_checksum_tampering_before_restore() {
    let root = tempdir().unwrap();
    let malicious = root.path().join("malicious.zip");
    let mut writer = ZipWriter::new(fs::File::create(&malicious).unwrap());
    writer
        .start_file(
            "otter_pad_backup/library/paper/../../../../escape",
            SimpleFileOptions::default(),
        )
        .unwrap();
    writer.write_all(b"outside").unwrap();
    writer.finish().unwrap();
    assert_eq!(
        archive::extract(&malicious, root.path(), &CancellationToken::new(), |_| {})
            .err()
            .unwrap()
            .code,
        ErrorCode::InvalidData
    );
    assert!(!root.path().join("escape").exists());
    let storage = Storage::open(root.path().join("live")).unwrap();
    populate(&storage);
    let good = root.path().join("good.zip");
    let token = CancellationToken::new();
    archive::create(&storage, &good, BackupScope::Full, None, &token, |_| {}).unwrap();
    let mut original = ZipArchive::new(fs::File::open(good).unwrap()).unwrap();
    let tampered = root.path().join("tampered.zip");
    let mut writer = ZipWriter::new(fs::File::create(&tampered).unwrap());
    for index in 0..original.len() {
        let mut entry = original.by_index(index).unwrap();
        let name = entry.name().unwrap().into_owned();
        let mut bytes = Vec::new();
        entry.read_to_end(&mut bytes).unwrap();
        if name.ends_with("source.pdf") {
            bytes = b"tampered source".to_vec();
        }
        writer
            .start_file(name, SimpleFileOptions::default())
            .unwrap();
        writer.write_all(&bytes).unwrap();
    }
    writer.finish().unwrap();
    assert_eq!(
        archive::extract(&tampered, root.path(), &token, |_| {})
            .err()
            .unwrap()
            .code,
        ErrorCode::InvalidData
    );
}

#[test]
fn snapshot_erases_credential_bytes_and_keeps_search_after_rowid_gaps() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path().join("live")).unwrap();
    populate(&storage);
    let mut document = storage.document("paper").unwrap().unwrap();
    for (id, title) in [
        ("removed", "Removed"),
        ("last", "最后检索 UniqueSearchTerm"),
    ] {
        document.id = id.into();
        document.title = title.into();
        document.content_hash = None;
        storage.put_document(&document).unwrap();
    }
    storage.delete_document("removed").unwrap();
    let credential = "accidental-persisted-credential-74291";
    let connection = rusqlite::Connection::open(storage.directory().join("otter.db")).unwrap();
    connection
        .execute(
            "INSERT INTO settings(settingKey,value) VALUES ('agent_api_key_old',?1)",
            [serde_json::to_string(credential).unwrap()],
        )
        .unwrap();
    drop(connection);
    let token = CancellationToken::new();
    let archive = root.path().join("snapshot.zip");
    archive::create(&storage, &archive, BackupScope::Full, None, &token, |_| {}).unwrap();
    let extracted = archive::extract(&archive, root.path(), &token, |_| {}).unwrap();
    let database = extracted.directory().join("db/otter.db");
    assert!(
        !fs::read(&database)
            .unwrap()
            .windows(credential.len())
            .any(|b| b == credential.as_bytes())
    );
    let destination = root.path().join("restored");
    fs::create_dir_all(destination.join("v2")).unwrap();
    fs::copy(database, destination.join("v2/otter.db")).unwrap();
    let restored = Storage::open(destination).unwrap();
    assert!(restored.setting("agent_api_key_old").unwrap().is_none());
    assert_eq!(
        restored.search_documents("UniqueSearchTerm", 10).unwrap()[0].id,
        "last"
    );
    assert_eq!(
        storage.setting("agent_api_key_old").unwrap().unwrap(),
        credential
    );
}
