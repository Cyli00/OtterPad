use std::{fs, path::Path};

use otter_core::{
    document::{DocumentModel, revision},
    error::ErrorCode,
    migrate,
    storage::Storage,
};
use rusqlite::{Connection, params};
use serde_json::{Value, json};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn legacy(root: &Path) -> Connection {
    fs::create_dir_all(root.join("db")).unwrap();
    let source = Connection::open(root.join("db/otter.db")).unwrap();
    source
        .execute_batch(include_str!("fixtures/legacy_0_1_schema.drift"))
        .unwrap();
    source.pragma_update(None, "user_version", 2).unwrap();
    source
        .execute_batch(
            "INSERT INTO favorites VALUES ('f','📚','用户收藏',1);
      INSERT INTO settings VALUES ('translation_config_temperature','0.7');
      INSERT INTO settings VALUES ('unknown_old_setting','true');
      INSERT INTO settings VALUES ('agent_api_key_secret','\"must not migrate\"');
      INSERT INTO meta VALUES ('zotero_library_version','12');
      INSERT INTO zotero_items VALUES ('UNLINKED',NULL,5);",
        )
        .unwrap();
    for (id, added) in [("a", 1), ("b", 2)] {
        source
            .execute(
                "INSERT INTO documents VALUES (?1,?2,'[\"作者\"]',NULL,'2026',NULL,'[]',NULL,?3)",
                params![id, format!("文献{id}"), added],
            )
            .unwrap();
        let dir = root.join("library").join(id);
        fs::create_dir_all(dir.join("chats")).unwrap();
        fs::create_dir_all(dir.join("summary")).unwrap();
        fs::create_dir_all(dir.join("figures")).unwrap();
        fs::write(dir.join("extract.raw.md"), "A 🦦 quoted phrase end.").unwrap();
        fs::write(dir.join("extract.md"), "A 🦦 quoted phrase end.").unwrap();
        fs::write(dir.join("extract.json"),json!([{"page_index":0,"page_size":[600,800],"prunedResult":{"parsing_res_list":[{"block_id":0,"block_label":"text","block_bbox":[10,10,500,40],"block_content":"A 🦦 quoted phrase end."}]},"markdown":{"text":"A 🦦 quoted phrase end."}}]).to_string()).unwrap();
        fs::write(
            dir.join("source.pdf"),
            b"legacy PDF bytes preserved unchanged",
        )
        .unwrap();
        fs::write(
            dir.join("chats/session.json"),
            b"{\"user\":\"a saved conversation\"}",
        )
        .unwrap();
        fs::write(dir.join("summary/summary.png"), b"retained image bytes").unwrap();
        fs::write(dir.join("figures/asset.png"), b"retained figure bytes").unwrap();
        fs::write(dir.join("mineru.exports.zip"), b"retained export bytes").unwrap();
        fs::write(dir.join(".reader.html"), b"obsolete WebView output").unwrap();
        let old_anchor = json!({"version":1,"ranges":[{"paragraphId":"old-id","language":"source","revision":"old-revision","start":5,"end":18,"quote":"quoted phrase","prefix":"A 🦦 ","suffix":" end."}]});
        source.execute("INSERT INTO highlights VALUES (?1,?2,'quoted phrase','用户笔记','FFD54F','group',?3,123)",params![format!("note-{id}"),id,old_anchor.to_string()]).unwrap();
        source.execute("INSERT INTO highlights VALUES (?1,?2,'lost quotation','仍须保留','AED581',NULL,NULL,124)",params![format!("unlocated-{id}"),id]).unwrap();
        source
            .execute("INSERT INTO history VALUES (?1,125,0.6,0)", [id])
            .unwrap();
        source
            .execute("INSERT INTO favorite_documents VALUES ('f',?1)", [id])
            .unwrap();
        source
            .execute(
                "INSERT INTO zotero_items VALUES (?1,?2,7)",
                params![format!("Z-{id}"), id],
            )
            .unwrap();
        let hash = migrate::legacy_hash("A 🦦 quoted phrase end.");
        fs::write(
            dir.join("translations.json"),
            json!({"zh":{hash:"已有付费译文","unmatched":"可丢弃缓存"},"en":{}}).to_string(),
        )
        .unwrap();
    }
    source
}

#[test]
fn imports_all_retained_data_resumes_and_never_overwrites_user_edits() {
    let root = tempdir().unwrap();
    let source = legacy(root.path());
    drop(source);
    let before = fs::read(root.path().join("db/otter.db")).unwrap();
    let mut storage = Storage::open(root.path()).unwrap();
    let token = CancellationToken::new();
    let error = migrate::run(&mut storage, root.path(), &token, |p| {
        if p.done == 1 {
            token.cancel();
        }
    })
    .unwrap_err();
    assert_eq!(error.code, ErrorCode::Cancelled);
    assert_eq!(storage.documents(10, 0).unwrap().len(), 1);
    let report =
        migrate::run(&mut storage, root.path(), &CancellationToken::new(), |_| {}).unwrap();
    assert_eq!(
        (
            report.imported,
            report.already_imported,
            report.failures.len(),
            report.complete
        ),
        (1, 1, 0, true)
    );
    assert_eq!(storage.documents(10, 0).unwrap().len(), 2);
    assert_eq!(
        storage.setting("translation_config_temperature").unwrap(),
        Some(json!(0.7))
    );
    assert_eq!(storage.setting("unknown_old_setting").unwrap(), None);
    assert_eq!(storage.setting("agent_api_key_secret").unwrap(), None);
    for id in ["a", "b"] {
        let dir = storage.directory().join("library").join(id);
        let model: DocumentModel =
            serde_json::from_slice(&fs::read(dir.join("document.json")).unwrap()).unwrap();
        let translations: Value =
            serde_json::from_slice(&fs::read(dir.join("translations.json")).unwrap()).unwrap();
        assert_eq!(
            translations["zh"][revision(model.blocks[0].markdown.trim())],
            "已有付费译文"
        );
        assert_eq!(translations["zh"].as_object().unwrap().len(), 1);
        for name in [
            "source.pdf",
            "chats/session.json",
            "summary/summary.png",
            "figures/asset.png",
            "mineru.exports.zip",
        ] {
            assert_eq!(
                fs::read(dir.join(name)).unwrap(),
                fs::read(root.path().join("library").join(id).join(name)).unwrap()
            );
        }
        assert!(!dir.join(".reader.html").exists());
    }
    let observer = Connection::open(storage.directory().join("otter.db")).unwrap();
    assert_eq!(
        observer
            .query_row("SELECT count(*) FROM highlights", [], |r| r
                .get::<_, i64>(0))
            .unwrap(),
        4
    );
    let located: String = observer
        .query_row("SELECT anchor FROM highlights WHERE id='note-a'", [], |r| {
            r.get(0)
        })
        .unwrap();
    let anchor: Value = serde_json::from_str(&located).unwrap();
    assert_eq!(anchor["located"], true);
    assert_eq!(anchor["ranges"][0]["start"], 5);
    let unlocated: String = observer
        .query_row(
            "SELECT anchor FROM highlights WHERE id='unlocated-a'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&unlocated).unwrap()["located"],
        false
    );
    for (table, expected) in [
        ("favorites", 1),
        ("favorite_documents", 2),
        ("history", 2),
        ("zotero_items", 3),
    ] {
        assert_eq!(
            observer
                .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            expected
        );
    }
    let anchor: Option<String> = observer
        .query_row("SELECT anchorBlock FROM history WHERE docId='a'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert!(anchor.is_some());
    let mut edited = storage.document("a").unwrap().unwrap();
    edited.title = "迁移后用户修改".into();
    storage.put_document(&edited).unwrap();
    let report =
        migrate::run(&mut storage, root.path(), &CancellationToken::new(), |_| {}).unwrap();
    assert_eq!(report.imported, 0);
    assert_eq!(report.already_imported, 2);
    assert_eq!(storage.document("a").unwrap(), Some(edited));
    assert_eq!(fs::read(root.path().join("db/otter.db")).unwrap(), before);
}

#[test]
fn failed_document_sql_after_file_publication_is_retryable_and_keeps_other_documents() {
    let root = tempdir().unwrap();
    let source = legacy(root.path());
    source
        .execute(
            "UPDATE documents SET authors='malformed-json' WHERE id='a'",
            [],
        )
        .unwrap();
    let mut storage = Storage::open(root.path()).unwrap();
    for _ in 0..2 {
        let report =
            migrate::run(&mut storage, root.path(), &CancellationToken::new(), |_| {}).unwrap();
        assert!(!report.complete);
        assert_eq!(report.failures.len(), 1);
        assert_eq!(report.failures[0].document_id, "a");
        assert!(storage.document("a").unwrap().is_none());
        assert!(storage.document("b").unwrap().is_some());
    }
    source
        .execute("UPDATE documents SET authors='[]' WHERE id='a'", [])
        .unwrap();
    let report =
        migrate::run(&mut storage, root.path(), &CancellationToken::new(), |_| {}).unwrap();
    assert!(report.complete);
    assert_eq!(report.imported, 1);
    assert!(
        fs::read_dir(storage.directory().join("library"))
            .unwrap()
            .all(|e| !e
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".migrate-previous"))
    );
}
