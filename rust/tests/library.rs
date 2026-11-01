use otter_core::{
    error::ErrorCode,
    library::{
        self, Favorite, Highlight, History,
        identifier::{self, IdentifierKind},
    },
    storage::{Document, Storage},
};
use serde_json::json;
use std::fs;
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn document(id: &str) -> Document {
    Document {
        id: id.into(),
        title: "测试文献".into(),
        authors: vec![],
        journal: None,
        year: None,
        doi: None,
        keywords: vec![],
        content_hash: None,
        added_at: 1,
    }
}

#[test]
fn imports_deduplicates_and_attaches_pdf_without_losing_existing_document_files() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    storage.put_document(&document("metadata")).unwrap();
    let directory = library::document_directory(&storage, "metadata").unwrap();
    fs::create_dir_all(directory.join("chats")).unwrap();
    fs::write(directory.join("chats/session.json"), b"saved chat").unwrap();
    let source = root.path().join("input.pdf");
    fs::write(&source, b"%PDF-1.7\nfile import payload").unwrap();
    let result = library::import_pdf(
        &storage,
        &source,
        document("metadata"),
        &CancellationToken::new(),
    )
    .unwrap();
    assert!(!result.duplicate);
    assert_eq!(
        fs::read(directory.join("source.pdf")).unwrap(),
        fs::read(&source).unwrap()
    );
    assert_eq!(
        fs::read(directory.join("chats/session.json")).unwrap(),
        b"saved chat"
    );
    let repeated = library::import_pdf(
        &storage,
        &source,
        document("different-id"),
        &CancellationToken::new(),
    )
    .unwrap();
    assert!(repeated.duplicate);
    assert_eq!(repeated.document.id, "metadata");
    assert_eq!(storage.documents(10, 0).unwrap().len(), 1);
    let cancelled = CancellationToken::new();
    cancelled.cancel();
    assert_eq!(
        library::import_pdf(&storage, &source, document("cancelled"), &cancelled)
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
    assert!(storage.document("cancelled").unwrap().is_none());
}

#[test]
fn favorite_updates_are_atomic_history_bubbles_and_annotation_groups_are_document_scoped() {
    let root = tempdir().unwrap();
    let mut storage = Storage::open(root.path()).unwrap();
    for id in ["a", "b"] {
        storage.put_document(&document(id)).unwrap();
    }
    let favorite = Favorite {
        id: "f".into(),
        emoji: "📚".into(),
        name: "自定义收藏".into(),
        document_ids: vec!["a".into()],
        created_at: 1,
    };
    library::put_favorite(&mut storage, &favorite).unwrap();
    let mut invalid = favorite.clone();
    invalid.document_ids.push("missing".into());
    assert_eq!(
        library::put_favorite(&mut storage, &invalid)
            .unwrap_err()
            .code,
        ErrorCode::Conflict
    );
    assert_eq!(library::favorites(&storage).unwrap(), vec![favorite]);
    for (id, time) in [("a", 10), ("b", 20), ("a", 30)] {
        library::record_history(
            &storage,
            &History {
                document_id: id.into(),
                opened_at: time,
                progress: 0.6,
                anchor_block: Some("stable-block".into()),
            },
        )
        .unwrap();
    }
    assert_eq!(
        library::history(&storage, 10, 0)
            .unwrap()
            .iter()
            .map(|h| h.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["a", "b"]
    );
    let highlight = Highlight {
        id: "a1".into(),
        document_id: "a".into(),
        content: "quote".into(),
        note: Some("不能丢失".into()),
        color: "FFD54F".into(),
        group_id: Some("shared-name".into()),
        anchor: Some(json!({"version":2,"located":false,"ranges":[]})),
        created_at: 1,
    };
    library::put_highlight(&storage, &highlight).unwrap();
    let mut second = highlight.clone();
    second.id = "a2".into();
    library::put_highlight(&storage, &second).unwrap();
    let mut other = highlight.clone();
    other.id = "b1".into();
    other.document_id = "b".into();
    library::put_highlight(&storage, &other).unwrap();
    let mut collision = highlight.clone();
    collision.document_id = "b".into();
    assert_eq!(
        library::put_highlight(&storage, &collision)
            .unwrap_err()
            .code,
        ErrorCode::Conflict
    );
    assert!(library::delete_highlight(&storage, "a1").unwrap());
    assert!(library::highlights(&storage, "a").unwrap().is_empty());
    assert_eq!(library::highlights(&storage, "b").unwrap(), vec![other]);
}

#[test]
fn document_deletion_recovers_interrupted_moves_and_cleans_files_after_commit() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    storage.put_document(&document("a")).unwrap();
    let directory = library::document_directory(&storage, "a").unwrap();
    fs::create_dir_all(&directory).unwrap();
    fs::write(directory.join("source.pdf"), b"user file").unwrap();
    // Actual interrupted move, before the SQLite delete committed.
    let pending = storage.directory().join(".trash/pending");
    fs::create_dir_all(&pending).unwrap();
    fs::write(
        pending.join("journal.json"),
        json!({"document_id":"a"}).to_string(),
    )
    .unwrap();
    fs::rename(&directory, pending.join("files")).unwrap();
    library::recover_deletions(&storage).unwrap();
    assert_eq!(
        fs::read(directory.join("source.pdf")).unwrap(),
        b"user file"
    );
    assert!(library::delete_document(&storage, "a").unwrap());
    assert!(storage.document("a").unwrap().is_none());
    assert!(!directory.exists());
    assert_eq!(
        fs::read_dir(storage.directory().join(".trash"))
            .unwrap()
            .count(),
        0
    );
}

#[test]
fn identifier_and_xml_metadata_parsing_preserve_existing_supported_formats() {
    for (input, kind, value) in [
        (
            "https://doi.org/10.1234/example.pdf)",
            IdentifierKind::Doi,
            "10.1234/example.pdf",
        ),
        (
            "arXiv:math.GT/0309136v2",
            IdentifierKind::Arxiv,
            "math.GT/0309136v2",
        ),
        (
            "https://arxiv.org/pdf/2412.14135.pdf?download=1",
            IdentifierKind::Arxiv,
            "2412.14135",
        ),
        ("PMID: 12345", IdentifierKind::Pmid, "12345"),
        (
            "ISBN: 978-1-4028-9462-6",
            IdentifierKind::Isbn,
            "9781402894626",
        ),
        ("ééééé", IdentifierKind::Unknown, "ééééé"),
    ] {
        let id = identifier::parse(input);
        assert_eq!((id.kind, id.value), (kind, value.into()));
    }
    assert_eq!(
        identifier::arxiv_doi("math.GT/0309136v2").as_deref(),
        Some("10.48550/arxiv.math/0309136")
    );
    let pubmed=identifier::parse_pubmed(r#"<PubmedArticleSet><PubmedArticle><MedlineCitation><Article><ArticleTitle>A <i>mixed</i> title.</ArticleTitle><AuthorList><Author><ForeName>Ada</ForeName><LastName>Lovelace</LastName></Author></AuthorList><Journal><Title>Journal</Title><JournalIssue><PubDate><MedlineDate>2026 Nov</MedlineDate></PubDate></JournalIssue></Journal></Article><MeshHeadingList><MeshHeading><DescriptorName>Language</DescriptorName></MeshHeading></MeshHeadingList><KeywordList><Keyword>language</Keyword><Keyword>Rust</Keyword></KeywordList></MedlineCitation><PubmedData><ArticleIdList><ArticleId IdType="doi">10.1234/EXAMPLE</ArticleId></ArticleIdList></PubmedData></PubmedArticle></PubmedArticleSet>"#,"12345").unwrap();
    assert_eq!(pubmed.title, "A mixed title");
    assert_eq!(pubmed.authors, vec!["Ada Lovelace"]);
    assert_eq!(pubmed.year.as_deref(), Some("2026"));
    assert_eq!(pubmed.keywords, vec!["Language", "Rust"]);
    let arxiv=identifier::parse_arxiv(r#"<feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom"><entry><id>https://arxiv.org/abs/2412.14135v1</id><title> A title </title><author><name>Author</name></author><published>2026-01-01</published><arxiv:journal_ref>Journal</arxiv:journal_ref></entry></feed>"#,"2412.14135v1").unwrap();
    assert_eq!(arxiv.doi.as_deref(), Some("10.48550/arxiv.2412.14135"));
    assert_eq!(arxiv.journal.as_deref(), Some("Journal"));
}
