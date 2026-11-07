use otter_core::{
    error::ErrorCode,
    library::{self, Favorite, Highlight, History},
    storage::{Document, Storage},
    sync::{
        archive::{self, BackupScope, BackupStage},
        backup::{self, RestoreMode, RestoreScope},
    },
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fs, io::Write, path::Path};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn document(
    storage: &Storage,
    id: &str,
    title: &str,
    doi: Option<&str>,
    pdf: Option<&[u8]>,
) -> Document {
    let directory = storage.directory().join("library").join(id);
    fs::create_dir_all(&directory).unwrap();
    let hash = pdf.map(|bytes| {
        fs::write(directory.join("source.pdf"), bytes).unwrap();
        Sha256::digest(bytes)
            .iter()
            .take(12)
            .map(|b| format!("{b:02x}"))
            .collect()
    });
    let doc = Document {
        id: id.into(),
        title: title.into(),
        authors: vec!["First Author".into()],
        journal: None,
        year: Some("2025".into()),
        doi: doi.map(str::to_owned),
        keywords: Vec::new(),
        content_hash: hash,
        added_at: 1,
    };
    storage.put_document(&doc).unwrap();
    doc
}
fn note(storage: &Storage, id: &str, document: &str) {
    library::put_highlight(
        storage,
        &Highlight {
            id: id.into(),
            document_id: document.into(),
            content: "source quote".into(),
            note: Some("user note".into()),
            color: "yellow".into(),
            group_id: Some("group".into()),
            anchor: Some(
                json!({"version":2,"located":false,"ranges":[],"legacy_raw":"retained anchor"}),
            ),
            created_at: 3,
        },
    )
    .unwrap();
}
fn favorite(storage: &mut Storage, documents: Vec<String>, name: &str) {
    library::put_favorite(
        storage,
        &Favorite {
            id: "f".into(),
            name: name.into(),
            emoji: "📚".into(),
            document_ids: documents,
            created_at: 1,
        },
    )
    .unwrap();
}
fn create_archive(storage: &Storage, path: &Path, scope: BackupScope) {
    archive::create(
        storage,
        path,
        scope,
        None,
        &CancellationToken::new(),
        |_| {},
    )
    .unwrap();
}

#[test]
fn prepared_merge_remaps_children_preserves_local_files_and_merges_paid_translations() {
    let root = tempdir().unwrap();
    let mut live = Storage::open(root.path().join("live")).unwrap();
    let mut source = Storage::open(root.path().join("source")).unwrap();
    document(
        &live,
        "local",
        "Local title",
        Some("10.1234/paper"),
        Some(b"%PDF local original"),
    );
    document(
        &source,
        "incoming",
        "Backup title",
        Some("10.1234/paper"),
        Some(b"%PDF backup version"),
    );
    document(&source, "new", "New paper", None, None);
    note(&live, "local-note", "local");
    note(&source, "backup-note", "incoming");
    favorite(&mut live, vec!["local".into()], "Local favorite");
    favorite(
        &mut source,
        vec!["incoming".into(), "new".into()],
        "Backup favorite",
    );
    library::record_history(
        &live,
        &History {
            document_id: "local".into(),
            opened_at: 100,
            progress: 0.2,
            anchor_block: Some("local-block".into()),
        },
    )
    .unwrap();
    library::record_history(
        &source,
        &History {
            document_id: "incoming".into(),
            opened_at: 200,
            progress: 0.8,
            anchor_block: Some("backup-block".into()),
        },
    )
    .unwrap();
    live.put_setting("theme_mode", &json!("dark")).unwrap();
    source.put_setting("theme_mode", &json!("light")).unwrap();
    source
        .put_setting("translation_config_target_language", &json!("zh"))
        .unwrap();
    source
        .put_setting("proxy_host", &json!("must-not-merge"))
        .unwrap(); // Simulate an older database that accidentally persisted a credential.
    {
        let db = rusqlite::Connection::open(source.directory().join("otter.db")).unwrap();
        db.execute(
            "INSERT INTO settings VALUES ('agent_api_key_old','\"do-not-back-up\"')",
            [],
        )
        .unwrap();
        db.execute(
            "INSERT INTO zotero_items VALUES ('PAPER001','incoming',12)",
            [],
        )
        .unwrap();
        for (key,value) in [
            ("zotero_library_version","12".to_owned()),
            ("zotero_user_id","42".to_owned()),
            ("zotero_local:source:PAPER001",json!({"documentId":"incoming","metadata":{"title":"Backup title"},"attachmentKey":"ATTACH01"}).to_string()),
        ] {
            db.execute("INSERT INTO meta VALUES (?1,?2)",rusqlite::params![key,value]).unwrap();
        }
    }
    let local = live.directory().join("library/local");
    let incoming = source.directory().join("library/incoming");
    fs::write(
        local.join("translations.json"),
        json!({"ja":{"a":"既存"},"zh":{"same":"local"}}).to_string(),
    )
    .unwrap();
    fs::write(
        incoming.join("translations.json"),
        json!({"fr":{"b":"payé"},"zh":{"same":"backup","new":"付费译文"}}).to_string(),
    )
    .unwrap();
    fs::create_dir_all(incoming.join("chats")).unwrap();
    fs::write(
        incoming.join("chats/backup.json"),
        b"saved backup conversation",
    )
    .unwrap();
    let archive = root.path().join("backup.zip");
    create_archive(&source, &archive, BackupScope::Full);
    let token = CancellationToken::new();
    let prepared = backup::prepare(
        &live,
        &archive,
        RestoreScope::Full,
        RestoreMode::Merge,
        &token,
        |_| {},
    )
    .unwrap();
    assert!(live.document("new").unwrap().is_none());
    assert!(!local.join("chats/backup.json").exists());
    let mut live = Some(live);
    let report = prepared.commit(&mut live, &token, |_| {}).unwrap();
    let live = live.as_ref().unwrap();
    assert_eq!(report.documents_added, 1);
    assert_eq!(report.highlights_added, 1);
    assert_eq!(report.document_ids["incoming"], "local");
    assert_eq!(live.documents(10, 0).unwrap().len(), 2);
    assert_eq!(
        live.document("local").unwrap().unwrap().title,
        "Local title"
    );
    let notes = library::highlights(live, "local").unwrap();
    assert_eq!(notes.len(), 2);
    assert_eq!(
        notes
            .iter()
            .find(|n| n.id == "backup-note")
            .unwrap()
            .anchor
            .as_ref()
            .unwrap()["legacy_raw"],
        "retained anchor"
    );
    assert_eq!(library::favorites(live).unwrap()[0].name, "Local favorite");
    assert_eq!(
        library::favorites(live).unwrap()[0].document_ids,
        vec!["local", "new"]
    );
    assert_eq!(library::history(live, 10, 0).unwrap()[0].progress, 0.8);
    let directory = live.directory().join("library/local");
    assert_eq!(
        fs::read(directory.join("source.pdf")).unwrap(),
        b"%PDF local original"
    );
    assert!(directory.join("chats/backup.json").is_file());
    let layers: Value =
        serde_json::from_slice(&fs::read(directory.join("translations.json")).unwrap()).unwrap();
    assert_eq!(layers["zh"]["same"], "local");
    assert_eq!(layers["zh"]["new"], "付费译文");
    assert_eq!(layers["ja"]["a"], "既存");
    assert_eq!(layers["fr"]["b"], "payé");
    assert_eq!(live.setting("theme_mode").unwrap(), Some(json!("dark")));
    assert!(live.setting("proxy_host").unwrap().is_none());
    assert!(live.setting("agent_api_key_old").unwrap().is_none());
    let db = rusqlite::Connection::open(live.directory().join("otter.db")).unwrap();
    assert_eq!(
        db.query_row(
            "SELECT docId FROM zotero_items WHERE zoteroKey='PAPER001'",
            [],
            |r| r.get::<_, String>(0)
        )
        .unwrap(),
        "local"
    );
    let record: String = db
        .query_row(
            "SELECT value FROM meta WHERE metaKey='zotero_local:source:PAPER001'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&record).unwrap()["documentId"],
        "local"
    );
    assert_eq!(
        otter_core::sync::zotero::cloud_since(live, 42, false).unwrap(),
        12
    );
}

#[test]
fn data_only_overwrite_preserves_heavy_files_for_surviving_ids_and_keeps_settings_by_scope() {
    let root = tempdir().unwrap();
    let live = Storage::open(root.path().join("live")).unwrap();
    let source = Storage::open(root.path().join("source")).unwrap();
    document(
        &live,
        "paper",
        "Current title",
        None,
        Some(b"%PDF keep local bytes"),
    );
    document(
        &live,
        "removed",
        "Deleted in backup",
        None,
        Some(b"%PDF removed"),
    );
    document(
        &source,
        "paper",
        "Backup title",
        None,
        Some(b"%PDF older bytes"),
    );
    live.put_setting("theme_mode", &json!("dark")).unwrap();
    source.put_setting("theme_mode", &json!("light")).unwrap();
    let path = root.path().join("data.zip");
    create_archive(&source, &path, BackupScope::DataOnly);
    let token = CancellationToken::new();
    let prepared = backup::prepare(
        &live,
        &path,
        RestoreScope::LibraryOnly,
        RestoreMode::Overwrite,
        &token,
        |_| {},
    )
    .unwrap();
    let mut live = Some(live);
    prepared.commit(&mut live, &token, |_| {}).unwrap();
    let live = live.as_ref().unwrap();
    assert_eq!(
        live.document("paper").unwrap().unwrap().title,
        "Backup title"
    );
    assert!(live.document("removed").unwrap().is_none());
    assert_eq!(
        fs::read(live.directory().join("library/paper/source.pdf")).unwrap(),
        b"%PDF keep local bytes"
    );
    assert_eq!(live.setting("theme_mode").unwrap(), Some(json!("dark")));
    let empty = Storage::open(root.path().join("empty")).unwrap();
    let prepared = backup::prepare(
        &empty,
        &path,
        RestoreScope::Full,
        RestoreMode::Overwrite,
        &token,
        |_| {},
    )
    .unwrap();
    let mut empty = Some(empty);
    prepared.commit(&mut empty, &token, |_| {}).unwrap();
    assert!(
        empty
            .as_ref()
            .unwrap()
            .document("paper")
            .unwrap()
            .unwrap()
            .content_hash
            .is_none()
    );
}

#[test]
fn changes_after_prepare_reject_publication_and_cancelled_prepare_keeps_live_data() {
    let root = tempdir().unwrap();
    let live = Storage::open(root.path().join("live")).unwrap();
    let source = Storage::open(root.path().join("source")).unwrap();
    document(&live, "local", "Local", None, None);
    document(&source, "incoming", "Incoming", None, None);
    let path = root.path().join("backup.zip");
    create_archive(&source, &path, BackupScope::Full);
    let token = CancellationToken::new();
    let prepared = backup::prepare(
        &live,
        &path,
        RestoreScope::Full,
        RestoreMode::Overwrite,
        &token,
        |_| {},
    )
    .unwrap();
    document(&live, "new-local", "Created after prepare", None, None);
    let mut live = Some(live);
    assert_eq!(
        prepared.commit(&mut live, &token, |_| {}).unwrap_err().code,
        ErrorCode::Conflict
    );
    assert!(
        live.as_ref()
            .unwrap()
            .document("new-local")
            .unwrap()
            .is_some()
    );
    let cancel = CancellationToken::new();
    assert_eq!(
        backup::prepare(
            live.as_ref().unwrap(),
            &path,
            RestoreScope::Full,
            RestoreMode::Overwrite,
            &cancel,
            |p| {
                if matches!(p.stage, BackupStage::Prepare) {
                    cancel.cancel();
                }
            }
        )
        .err()
        .unwrap()
        .code,
        ErrorCode::Cancelled
    );
    assert!(live.as_ref().unwrap().document("local").unwrap().is_some());
    assert!(
        live.as_ref()
            .unwrap()
            .document("incoming")
            .unwrap()
            .is_none()
    );
}

#[test]
fn startup_recovers_uncommitted_restore_but_retains_a_committed_replacement() {
    for committed in [false, true] {
        let root = tempdir().unwrap();
        let old = Storage::open(root.path()).unwrap();
        document(&old, "old", "Old database", None, None);
        drop(old);
        fs::rename(
            root.path().join("v2"),
            root.path().join(".restore-sim.previous"),
        )
        .unwrap();
        let new = Storage::open(root.path()).unwrap();
        document(&new, "new", "New database", None, None);
        drop(new);
        fs::create_dir(root.path().join(".restore-sim")).unwrap();
        fs::write(root.path().join(".restore-pending.json"),json!({"stage":".restore-sim","previous":".restore-sim.previous","committed":committed}).to_string()).unwrap();
        backup::recover(root.path()).unwrap();
        let recovered = Storage::open(root.path()).unwrap();
        assert_eq!(recovered.document("new").unwrap().is_some(), committed);
        assert_eq!(recovered.document("old").unwrap().is_some(), !committed);
        assert_eq!(
            root.path()
                .join(".restore-sim.uncommitted/otter.db")
                .is_file(),
            !committed
        );
        assert!(!root.path().join(".restore-pending.json").exists());
    }
}

#[test]
fn legacy_v3_backup_uses_real_old_schema_and_migrates_without_editing_archive() {
    use zip::{ZipWriter, write::SimpleFileOptions};
    let root = tempdir().unwrap();
    let legacy_path = root.path().join("legacy.db");
    let legacy = rusqlite::Connection::open(&legacy_path).unwrap();
    legacy
        .execute_batch(include_str!("fixtures/legacy_0_1_schema.drift"))
        .unwrap();
    legacy.pragma_update(None, "user_version", 2).unwrap();
    legacy.execute_batch("PRAGMA foreign_keys=OFF;INSERT INTO documents VALUES ('old','旧文献','[]',NULL,NULL,NULL,'[]',NULL,1);INSERT INTO highlights VALUES ('note','old','quoted phrase','旧笔记','yellow',NULL,NULL,2);INSERT INTO highlights VALUES ('orphan','missing','orphan note',NULL,'yellow',NULL,NULL,2);INSERT INTO settings VALUES ('translation_config_temperature','0.3');").unwrap();
    drop(legacy);
    let path = root.path().join("legacy.zip");
    let mut zip = ZipWriter::new(fs::File::create(&path).unwrap());
    let options = SimpleFileOptions::default();
    for (name,bytes) in [("manifest.json",json!({"app":"OtterPad","formatVersion":3,"createdAt":"2025-01-01T00:00:00Z","scope":"full"}).to_string().into_bytes()),("db/otter.db",fs::read(&legacy_path).unwrap()),("library/old/extract.raw.md",b"A quoted phrase end.".to_vec()),("library/old/source.pdf",b"%PDF legacy bytes".to_vec())]{zip.start_file(format!("otter_pad_backup/{name}"),options).unwrap();zip.write_all(&bytes).unwrap();}
    zip.finish().unwrap();
    let before = fs::read(&path).unwrap();
    let live = Storage::open(root.path().join("live")).unwrap();
    let token = CancellationToken::new();
    let prepared = backup::prepare(
        &live,
        &path,
        RestoreScope::Full,
        RestoreMode::Merge,
        &token,
        |_| {},
    )
    .unwrap();
    let mut live = Some(live);
    let report = prepared.commit(&mut live, &token, |_| {}).unwrap();
    assert_eq!(report.documents_added, 1);
    assert_eq!(report.highlights_added, 1);
    assert_eq!(report.skipped_orphans, 1);
    assert_eq!(
        library::highlights(live.as_ref().unwrap(), "old").unwrap()[0]
            .note
            .as_deref(),
        Some("旧笔记")
    );
    assert!(
        live.as_ref()
            .unwrap()
            .directory()
            .join("library/old/document.json")
            .is_file()
    );
    assert_eq!(fs::read(path).unwrap(), before);
}

#[test]
fn settings_only_restore_preserves_library_and_uses_overwrite_or_merge_semantics() {
    for mode in [RestoreMode::Overwrite, RestoreMode::Merge] {
        let root = tempdir().unwrap();
        let live = Storage::open(root.path().join("live")).unwrap();
        let source = Storage::open(root.path().join("source")).unwrap();
        document(&live, "local", "Local paper", None, Some(b"%PDF retained"));
        document(&source, "source", "Source paper", None, None);
        live.put_setting("theme_mode", &json!("dark")).unwrap();
        source.put_setting("theme_mode", &json!("light")).unwrap();
        source
            .put_setting("translation_config_target_language", &json!("zh"))
            .unwrap();
        let path = root.path().join("backup.zip");
        create_archive(&source, &path, BackupScope::Full);
        let token = CancellationToken::new();
        let prepared = backup::prepare(
            &live,
            &path,
            RestoreScope::SettingsOnly,
            mode,
            &token,
            |_| {},
        )
        .unwrap();
        let mut live = Some(live);
        prepared.commit(&mut live, &token, |_| {}).unwrap();
        let live = live.as_ref().unwrap();
        assert!(live.document("local").unwrap().is_some());
        assert!(live.document("source").unwrap().is_none());
        assert_eq!(
            fs::read(live.directory().join("library/local/source.pdf")).unwrap(),
            b"%PDF retained"
        );
        assert_eq!(
            live.setting("translation_config_target_language").unwrap(),
            Some(json!("zh"))
        );
        assert_eq!(
            live.setting("theme_mode").unwrap(),
            Some(json!(if mode == RestoreMode::Overwrite {
                "light"
            } else {
                "dark"
            }))
        );
    }
}
