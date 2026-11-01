use otter_core::{
    error::ErrorCode,
    storage::{Document, Storage},
};
use rusqlite::{Connection, params};
use serde_json::json;
use tempfile::tempdir;

fn document(id: &str, title: &str) -> Document {
    Document {
        id: id.into(),
        title: title.into(),
        authors: vec!["张三".into(), "Ada Lovelace".into()],
        journal: Some("计算机学报".into()),
        year: Some("2026".into()),
        doi: Some("10.1/example".into()),
        keywords: vec!["深度学习".into()],
        content_hash: None,
        added_at: 1_730_000_000_000,
    }
}

#[test]
fn pinyin_full_spelling_initials_polyphonic_names_and_updates_use_real_fts() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    storage
        .put_document(&document("paper", "自然语言处理，重庆大学 RUST"))
        .unwrap();
    for query in [
        "ziranyuyan",
        "zryycl",
        "chongqing",
        "cqdx",
        "zhangsan",
        "zs",
        "RUST",
        "语言",
    ] {
        assert_eq!(
            storage.search_documents(query, 10).unwrap().len(),
            1,
            "{query}"
        );
    }
    storage
        .put_document(&document("paper", "深度学习"))
        .unwrap();
    assert!(
        storage
            .search_documents("chongqing", 10)
            .unwrap()
            .is_empty()
    );
    drop(storage);
    let storage = Storage::open(root.path()).unwrap();
    assert_eq!(
        storage.search_documents("shenduxuexi", 10).unwrap().len(),
        1
    );
    storage.delete_document("paper").unwrap();
    assert!(storage.search_documents("sdxx", 10).unwrap().is_empty());
}

#[test]
fn persists_metadata_and_json_settings_without_touching_legacy_database() {
    let root = tempdir().unwrap();
    std::fs::create_dir(root.path().join("db")).unwrap();
    let legacy_path = root.path().join("db/otter.db");
    let legacy = Connection::open(&legacy_path).unwrap();
    legacy.execute_batch("CREATE TABLE documents(id TEXT); INSERT INTO documents VALUES ('legacy'); PRAGMA user_version=2;").unwrap();
    drop(legacy);
    let before = std::fs::read(&legacy_path).unwrap();
    let storage = Storage::open(root.path()).unwrap();
    let original = document("one", "自然语言处理 🦦 Rust");
    storage.put_document(&original).unwrap();
    storage
        .put_setting("translation_config_temperature", &json!(0.3))
        .unwrap();
    storage
        .put_setting("agent_api_models_instance", &json!(["model-a", "model-b"]))
        .unwrap();
    storage.put_setting("nullable", &json!(null)).unwrap();
    drop(storage);

    let reopened = Storage::open(root.path()).unwrap();
    assert_eq!(reopened.document("one").unwrap(), Some(original));
    assert_eq!(
        reopened.setting("translation_config_temperature").unwrap(),
        Some(json!(0.3))
    );
    assert_eq!(
        reopened.setting("agent_api_models_instance").unwrap(),
        Some(json!(["model-a", "model-b"]))
    );
    assert_eq!(reopened.setting("nullable").unwrap(), Some(json!(null)));
    assert_eq!(reopened.setting("missing").unwrap(), None);
    reopened.delete_setting("nullable").unwrap();
    assert_eq!(reopened.setting("nullable").unwrap(), None);
    assert_eq!(std::fs::read(legacy_path).unwrap(), before);
    assert!(root.path().join("v2/library").is_dir());
    assert!(root.path().join("v2/logs").is_dir());
}

#[test]
fn fts_segments_chinese_and_syncs_updates_deletes_and_reopened_connections() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    let mut original = document("one", "自然语言处理 🦦 RUST");
    storage.put_document(&original).unwrap();
    for query in [
        "自然语言",
        "语言",
        "rust",
        "张三",
        "Lovelace",
        "计算机",
        "深度学习",
        "语言 RUST",
    ] {
        assert_eq!(
            storage.search_documents(query, 10).unwrap(),
            vec![original.clone()],
            "{query}"
        );
    }
    for query in ["不存在", "\" OR *", "🦦", "", "   ", "NEAR(foo)"] {
        assert!(
            storage.search_documents(query, 10).unwrap().is_empty(),
            "{query}"
        );
    }
    assert!(storage.search_documents("rust", 0).unwrap().is_empty());
    original.title = "量子计算".into();
    storage.put_document(&original).unwrap();
    assert!(storage.search_documents("rust", 10).unwrap().is_empty());
    assert_eq!(
        storage.search_documents("量子", 10).unwrap(),
        vec![original.clone()]
    );
    let second = Storage::open(root.path()).unwrap();
    assert_eq!(second.search_documents("量子", 10).unwrap(), vec![original]);
    assert!(second.delete_document("one").unwrap());
    assert!(!second.delete_document("one").unwrap());
    assert!(storage.search_documents("量子", 10).unwrap().is_empty());
}

#[test]
fn upsert_preserves_user_data_conflict_rolls_back_and_delete_cascades() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    let mut first = document("one", "旧标题");
    first.content_hash = Some("pdf-hash".into());
    storage.put_document(&first).unwrap();
    let observer = Connection::open(root.path().join("v2/otter.db")).unwrap();
    observer
        .execute_batch(
            "PRAGMA foreign_keys=ON;
         INSERT INTO highlights VALUES ('note','one','用户引文','用户笔记','FFD54F',NULL,NULL,1);
         INSERT INTO history VALUES ('one',1,0.4,NULL);
         INSERT INTO favorites VALUES ('folder','📚','用户收藏夹',1);
         INSERT INTO favorite_documents VALUES ('folder','one');
         INSERT INTO zotero_items VALUES ('ZOTERO','one',3);",
        )
        .unwrap();
    first.title = "新标题".into();
    storage.put_document(&first).unwrap();
    let note: String = observer
        .query_row("SELECT note FROM highlights WHERE docId='one'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(note, "用户笔记");
    for table in [
        "highlights",
        "history",
        "favorite_documents",
        "zotero_items",
    ] {
        let count: i64 = observer
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1, "{table}");
    }
    let mut duplicate = document("two", "重复文件");
    duplicate.content_hash = first.content_hash.clone();
    assert_eq!(
        storage.put_document(&duplicate).unwrap_err().code,
        ErrorCode::Conflict
    );
    assert_eq!(storage.document("one").unwrap(), Some(first));
    assert_eq!(storage.document("two").unwrap(), None);
    assert_eq!(storage.search_documents("新标题", 10).unwrap().len(), 1);
    assert!(storage.search_documents("重复文件", 10).unwrap().is_empty());
    assert!(storage.delete_document("one").unwrap());
    for table in [
        "highlights",
        "history",
        "favorite_documents",
        "zotero_items",
        "documents_fts",
    ] {
        let count: i64 = observer
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 0, "{table}");
    }
    let folders: i64 = observer
        .query_row("SELECT count(*) FROM favorites", [], |r| r.get(0))
        .unwrap();
    assert_eq!(folders, 1);
    // Deleting the original releases its unique PDF fingerprint.
    storage.put_document(&duplicate).unwrap();
    assert_eq!(storage.document("two").unwrap(), Some(duplicate));
}

#[test]
fn rejects_foreign_unversioned_and_future_databases_without_changing_them() {
    for (application, version, schema) in [
        (0x4f54_5032, 999, ""),
        (123, 1, ""),
        (0, 2, "CREATE TABLE documents(id TEXT);"),
        (0, 0, "CREATE TABLE unknown(data BLOB);"),
    ] {
        let root = tempdir().unwrap();
        std::fs::create_dir(root.path().join("v2")).unwrap();
        let path = root.path().join("v2/otter.db");
        let database = Connection::open(&path).unwrap();
        database.execute_batch(schema).unwrap();
        database
            .pragma_update(None, "application_id", application)
            .unwrap();
        database
            .pragma_update(None, "user_version", version)
            .unwrap();
        drop(database);
        let before = std::fs::read(&path).unwrap();
        let error = match Storage::open(root.path()) {
            Err(error) => error,
            Ok(_) => panic!("accepted an unsupported database"),
        };
        assert_eq!(error.code, ErrorCode::UnsupportedDatabase);
        assert_eq!(std::fs::read(path).unwrap(), before);
    }
}

#[test]
fn lists_metadata_with_stable_pagination_and_rejects_invalid_ids() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    let first = document("a", "A");
    let second = document("b", "B");
    let mut newest = document("c", "C");
    newest.added_at += 1;
    for value in [&second, &newest, &first] {
        storage.put_document(value).unwrap();
    }
    assert_eq!(storage.documents(2, 0).unwrap(), vec![newest, first]);
    assert_eq!(storage.documents(2, 2).unwrap(), vec![second]);
    assert!(storage.documents(0, 0).unwrap().is_empty());
    assert!(storage.documents(10, 100).unwrap().is_empty());
    assert_eq!(
        storage
            .put_document(&document("", "invalid"))
            .unwrap_err()
            .code,
        ErrorCode::InvalidArgument
    );
    let database = Connection::open(root.path().join("v2/otter.db")).unwrap();
    let journal: String = database
        .pragma_query_value(None, "journal_mode", |r| r.get(0))
        .unwrap();
    assert_eq!(journal, "wal");
    database
        .execute(
            "INSERT INTO settings VALUES (?1,?2)",
            params!["broken", "{"],
        )
        .unwrap();
    assert_eq!(
        storage.setting("broken").unwrap_err().code,
        ErrorCode::InvalidData
    );
}
