use otter_core::{
    error::ErrorCode,
    library,
    maintenance::{self, StorageGroup},
    prompts::{self, PromptKind},
    storage::{Document, Storage},
    sync::{
        archive::{self, BackupScope},
        status::{self, BackupSnapshot},
    },
    update,
};
use serde_json::json;
use std::fs;
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn populate(storage: &Storage) {
    let source = storage.directory().join("input.pdf");
    fs::write(&source, include_bytes!("fixtures/two_pages.pdf")).unwrap();
    library::import_pdf(
        storage,
        &source,
        Document {
            id: "paper".into(),
            title: "Actual PDF".into(),
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
    .unwrap();
    fs::remove_file(source).unwrap();
}

#[test]
fn prompt_contract_and_storage_cleanup_preserve_user_data_and_custom_settings() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    populate(&storage);
    let default = prompts::get(&storage, PromptKind::TranslationUser).unwrap();
    assert!(default.is_default);
    let custom = prompts::set(
        &storage,
        PromptKind::TranslationUser,
        "To {{targetLanguage}}: {{input}}",
    )
    .unwrap();
    assert!(!custom.is_default);
    assert_eq!(
        prompts::set(&storage, PromptKind::TranslationUser, "Lost input")
            .err()
            .unwrap()
            .code,
        ErrorCode::InvalidArgument
    );
    assert_eq!(
        prompts::get(&storage, PromptKind::TranslationUser)
            .unwrap()
            .text,
        custom.text
    );
    assert!(
        prompts::set(&storage, PromptKind::TranslationUser, " ")
            .unwrap()
            .is_default
    );
    let paper = storage.directory().join("library/paper");
    fs::create_dir_all(paper.join("chats")).unwrap();
    fs::write(
        paper.join("chats/session.json"),
        include_bytes!("fixtures/chat-v017.json"),
    )
    .unwrap();
    fs::create_dir_all(storage.directory().join("cache/translation")).unwrap();
    fs::write(
        storage.directory().join("cache/translation/cached.json"),
        json!({"text":"cached"}).to_string(),
    )
    .unwrap();
    let token = CancellationToken::new();
    let before = maintenance::report(&storage, &token).unwrap();
    assert_eq!(
        before
            .groups
            .iter()
            .find(|g| g.group == StorageGroup::Cache)
            .unwrap()
            .files,
        1
    );
    maintenance::clear(&storage, &[StorageGroup::Cache], &token).unwrap();
    assert_eq!(
        fs::read(paper.join("source.pdf")).unwrap(),
        include_bytes!("fixtures/two_pages.pdf")
    );
    assert!(paper.join("chats/session.json").is_file());
    assert_eq!(
        maintenance::report(&storage, &token)
            .unwrap()
            .groups
            .iter()
            .find(|g| g.group == StorageGroup::Cache)
            .unwrap()
            .files,
        0
    );
    assert!(storage.document("paper").unwrap().is_some());
    assert_eq!(
        maintenance::clear(&storage, &[StorageGroup::Recovery], &token)
            .unwrap_err()
            .code,
        ErrorCode::InvalidArgument
    );
}

#[test]
fn backup_fingerprints_track_metadata_chats_translations_deletions_and_due_rules() {
    use otter_core::sync::remote::RemoteConfig;
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    populate(&storage);
    let token = CancellationToken::new();
    let config = RemoteConfig::Webdav {
        server_url: "https://example.test/dav".into(),
        username: "user".into(),
        remote_dir: "backups".into(),
        file_name: "backup.zip".into(),
    };
    assert!(status::status(&storage, &token).unwrap().changed);
    let documents = status::fingerprints(&storage, &token).unwrap();
    archive::create(
        &storage,
        &root.path().join("actual.zip"),
        BackupScope::Full,
        None,
        None,
        &token,
        |_| {},
    )
    .unwrap();
    let now = (time::OffsetDateTime::now_utc().unix_timestamp_nanos() / 1_000_000) as i64;
    let snapshot = BackupSnapshot {
        version: 2,
        at: now,
        scope: BackupScope::Full,
        remote: status::remote_identity(&config).unwrap(),
        device: None,
        documents,
    };
    status::save(&storage, &snapshot).unwrap();
    storage
        .put_setting("auto_backup_interval", &json!("daily"))
        .unwrap();
    assert!(!status::status(&storage, &token).unwrap().changed);
    assert!(!status::automatic_due(&storage, &config, now + 2 * 24 * 3600 * 1000, &token).unwrap());
    let paper = storage.directory().join("library/paper");
    fs::write(
        paper.join("translations.json"),
        json!({"zh":{"hash":"译文"}}).to_string(),
    )
    .unwrap();
    assert!(status::status(&storage, &token).unwrap().changed);
    assert!(!status::automatic_due(&storage, &config, now + 1000, &token).unwrap());
    assert!(status::automatic_due(&storage, &config, now + 2 * 24 * 3600 * 1000, &token).unwrap());
    fs::remove_file(paper.join("translations.json")).unwrap();
    assert!(!status::status(&storage, &token).unwrap().changed);
    fs::create_dir(paper.join("chats")).unwrap();
    fs::write(
        paper.join("chats/session.json"),
        include_bytes!("fixtures/chat-v017.json"),
    )
    .unwrap();
    assert!(status::status(&storage, &token).unwrap().changed);
    fs::remove_file(paper.join("chats/session.json")).unwrap();
    let mut document = storage.document("paper").unwrap().unwrap();
    document.title = "User edited title".into();
    storage.put_document(&document).unwrap();
    assert!(status::status(&storage, &token).unwrap().changed);
    library::delete_document(&storage, "paper").unwrap();
    assert!(status::status(&storage, &token).unwrap().changed);
}

#[test]
fn releases_choose_device_abi_order_and_preserve_version_and_ignore_semantics() {
    let response = json!({"tag_name":"v0.2.0", "html_url":"https://github.com/Cyli00/OtterPad/releases/tag/v0.2.0", "body":"## Changes\n- Backend migration\n- PDF rendering", "assets":[
        {"name":"OtterPad-armeabi-v7a.apk","browser_download_url":"https://example.test/armv7.apk","size":100},
        {"name":"OtterPad-arm64-v8a.apk","browser_download_url":"https://example.test/arm64.apk","size":200}
    ]});
    let result = update::parse(
        &response,
        "0.1.7",
        &["arm64-v8a".into(), "armeabi-v7a".into()],
        Some("0.2.0"),
    )
    .unwrap();
    assert!(result.has_update && result.ignored);
    assert_eq!(result.apk.unwrap().abi, "arm64-v8a");
    assert_eq!(result.changelog, ["Backend migration", "PDF rendering"]);
    assert!(update::compare_versions("0.2", "0.2.0").is_eq());
    assert!(
        update::parse(&response, "0.2.0", &[], None)
            .unwrap()
            .apk
            .is_none()
    );
}
