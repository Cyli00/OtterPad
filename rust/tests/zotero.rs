mod support;

use otter_core::{
    error::ErrorCode,
    storage::Storage,
    sync::zotero::{self, CloudLibrary, LocalSelection, ZoteroClient},
};
use serde_json::{Value, json};
use support::Reply;
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn item(key: &str, title: &str) -> Value {
    json!({"key":key,"version":7,"data":{"itemType":"journalArticle","title":title,"creators":[{"creatorType":"author","firstName":"Jane","lastName":"Doe"}],"publicationTitle":"Journal","date":"Spring 2024","DOI":format!("10.1234/{key}"),"tags":[{"tag":"Science"},{"tag":"science"}]}})
}
fn reply(items: Vec<Value>, version: u64, total: usize) -> Reply {
    let mut response = Reply::json(json!(items));
    response.headers = vec![
        ("Last-Modified-Version".into(), version.to_string()),
        ("Total-Results".into(), total.to_string()),
        ("Zotero-Server-ID".into(), "instance-A".into()),
    ];
    response
}

#[tokio::test]
async fn cloud_pagination_incremental_cursor_deduplication_and_cancelled_transaction() {
    let (base, server) = support::server(4, |index, request| {
        assert!(request.body.is_empty());
        assert!(
            request
                .head
                .to_lowercase()
                .contains("zotero-api-version: 3")
        );
        if index == 0 {
            assert!(request.head.starts_with("GET /keys/TestKey123 "));
            return Reply::json(json!({"userID":42}));
        }
        assert!(
            request
                .head
                .to_lowercase()
                .contains("zotero-api-key: testkey123")
        );
        match index {
            1 => {
                assert!(request.head.contains("since=0"));
                assert!(request.head.contains("start=0"));
                reply(
                    (0..100)
                        .map(|i| item(&format!("K{i:07}"), &format!("Paper {i}")))
                        .collect(),
                    7,
                    101,
                )
            }
            2 => {
                assert!(request.head.contains("start=100"));
                reply(vec![item("K0000100", "Paper 100")], 7, 101)
            }
            _ => {
                assert!(request.head.contains("since=7"));
                reply(vec![item("K0000000", "Changed remotely")], 8, 1)
            }
        }
    })
    .await;
    let client = ZoteroClient::with_endpoint(&format!("{base}/"), None, true).unwrap();
    let token = CancellationToken::new();
    let user = client.user_id("TestKey123", &token).await.unwrap();
    let fetched = client
        .fetch_cloud("TestKey123", user, 0, &token, |_| {})
        .await
        .unwrap();
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    assert_eq!(
        zotero::import_cloud(&storage, &fetched, false, &token, |_| {})
            .unwrap()
            .added,
        101
    );
    assert_eq!(zotero::cloud_since(&storage, user, false).unwrap(), 7);
    let fetched = client
        .fetch_cloud("TestKey123", user, 7, &token, |_| {})
        .await
        .unwrap();
    assert_eq!(
        zotero::import_cloud(&storage, &fetched, false, &token, |_| {})
            .unwrap()
            .added,
        0
    );
    assert_eq!(storage.documents(200, 0).unwrap().len(), 101);
    assert_eq!(storage.search_documents("Paper 0", 200).unwrap().len(), 1);
    assert_eq!(zotero::library_version(&storage).unwrap(), 8);
    let cancelled = CancellationToken::new();
    let newer = CloudLibrary {
        user_id: user,
        version: 9,
        items: vec![
            item("NEW00001", "New first"),
            item("NEW00002", "New second"),
        ],
    };
    assert_eq!(
        zotero::import_cloud(&storage, &newer, false, &cancelled, |_| cancelled.cancel())
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
    assert_eq!(storage.documents(200, 0).unwrap().len(), 101);
    assert_eq!(zotero::library_version(&storage).unwrap(), 8);
    assert_eq!(
        zotero::import_cloud(&storage, &newer, false, &token, |_| {})
            .unwrap()
            .added,
        2
    );
    assert_eq!(zotero::cloud_since(&storage, 99, false).unwrap(), 0);
    server.await.unwrap();
}

#[tokio::test]
async fn changing_library_between_pages_is_rejected_before_any_database_write() {
    let (base, server) = support::server(2, |index, _| {
        if index == 0 {
            reply(
                (0..100)
                    .map(|i| item(&format!("K{i:07}"), "Paper"))
                    .collect(),
                7,
                101,
            )
        } else {
            reply(vec![item("K0000100", "Late paper")], 8, 101)
        }
    })
    .await;
    let client = ZoteroClient::with_endpoint(&format!("{base}/"), None, true).unwrap();
    assert_eq!(
        client
            .fetch_cloud("TestKey123", 42, 0, &CancellationToken::new(), |_| {})
            .await
            .unwrap_err()
            .code,
        ErrorCode::Conflict
    );
    server.await.unwrap();
}

#[tokio::test]
async fn local_import_copies_real_pdf_preserves_source_and_user_edits_on_reimport() {
    let root = tempdir().unwrap();
    let original = root.path().join("Zotero source attachment.pdf");
    let pdf = include_bytes!("fixtures/two_pages.pdf");
    std::fs::write(&original, pdf).unwrap();
    let file_url = reqwest::Url::from_file_path(&original).unwrap().to_string();
    let (base,server)=support::server(7,move |index,request| {
        assert!(!request.head.to_lowercase().contains("zotero-api-key:"));
        if index==0 || index==2 || index==4 || index==6 {
            assert!(request.head.starts_with("GET /api/ HTTP"));
            if index==2 || index==6 { assert!(request.head.to_lowercase().contains("zotero-server-id: instance-a")); }
            let mut reply=Reply::json(json!({}));
            reply.headers=vec![("Zotero-API-Version".into(),"3".into()),("Zotero-Server-ID".into(),"instance-A".into())];
            return reply;
        }
        if index==3 {
            assert!(request.head.starts_with("GET /api/users/0/items/ATTACH01/file/view/url "));
            let mut reply=Reply::json(json!(null));
            reply.body=file_url.as_bytes().to_vec();
            reply.headers=vec![("Zotero-Server-ID".into(),"instance-A".into())];
            return reply;
        }
        assert!(request.head.contains("GET /api/users/0/items?"));
        assert!(!request.head.contains("since="));
        let mut paper=item("PAPER001",if index==1 { "Original title" } else { "Changed Zotero title" });
        paper["data"]["publicationTitle"]=json!(if index==1 {"Old journal"} else {"New journal"});
        reply(vec![paper,json!({"key":"ATTACH01","version":7,"data":{"itemType":"attachment","parentItem":"PAPER001","contentType":"application/pdf","linkMode":"linked_file","filename":"source.pdf"}})],7,2)
    }).await;
    let port = reqwest::Url::parse(&base).unwrap().port().unwrap();
    let client = ZoteroClient::new(None, true).unwrap();
    let token = CancellationToken::new();
    let library = client.fetch_local(port, &token, |_| {}).await.unwrap();
    let candidates = zotero::local_candidates(&library.items, 1);
    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].document.authors, vec!["Jane Doe"]);
    assert_eq!(candidates[0].document.keywords, vec!["Science"]);
    let storage = Storage::open(root.path().join("live")).unwrap();
    let selections = [LocalSelection {
        item_key: "PAPER001".into(),
        attachment_key: Some("ATTACH01".into()),
    }];
    let result = zotero::import_local(
        &storage,
        &client,
        &library,
        None,
        &selections,
        &token,
        |_| {},
    )
    .await
    .unwrap();
    assert_eq!((result.added, result.copied), (1, 1));
    let mut document = storage.documents(10, 0).unwrap().remove(0);
    document.title = "User edited title".into();
    storage.put_document(&document).unwrap();
    let library = client.fetch_local(port, &token, |_| {}).await.unwrap();
    let result = zotero::import_local(
        &storage,
        &client,
        &library,
        None,
        &selections,
        &token,
        |_| {},
    )
    .await
    .unwrap();
    assert_eq!((result.added, result.updated, result.kept), (0, 1, 1));
    let current = storage.document(&document.id).unwrap().unwrap();
    assert_eq!(current.title, "User edited title");
    assert_eq!(current.journal.as_deref(), Some("New journal"));
    assert_eq!(std::fs::read(&original).unwrap(), pdf);
    assert_eq!(
        std::fs::read(
            storage
                .directory()
                .join("library")
                .join(document.id)
                .join("source.pdf")
        )
        .unwrap(),
        pdf
    );
    server.await.unwrap();
}

#[tokio::test]
async fn local_server_switch_and_remote_file_urls_are_rejected() {
    let (base, server) = support::server(2, |index, _| {
        let mut response = Reply::json(json!({}));
        response.headers = vec![(
            "Zotero-Server-ID".into(),
            if index == 0 {
                "other-instance"
            } else {
                "instance-A"
            }
            .into(),
        )];
        response.body = b"file://remote-host/private/file.pdf".to_vec();
        response
    })
    .await;
    let port = reqwest::Url::parse(&base).unwrap().port().unwrap();
    let client = ZoteroClient::new(None, true).unwrap();
    let token = CancellationToken::new();
    let library = zotero::LocalLibrary {
        port,
        server_id: Some("instance-A".into()),
        items: vec![],
    };
    assert_eq!(
        client
            .verify_local(&library, &token)
            .await
            .unwrap_err()
            .code,
        ErrorCode::Conflict
    );
    assert_eq!(
        client
            .attachment_path(&library, "ATTACH01", &token)
            .await
            .unwrap_err()
            .code,
        ErrorCode::InvalidData
    );
    server.await.unwrap();
}
