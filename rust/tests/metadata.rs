use otter_core::{
    document::structure::Structure,
    library::{
        identifier::IdentifierKind,
        metadata::{self, PdfProperties},
    },
};
use serde_json::json;

#[test]
fn filenames_pdf_properties_and_identifiers_preserve_legacy_precedence_and_filter_placeholders() {
    let named = metadata::parse_filename(r"C:\Downloads\2024-Alice-Title-with-hyphens.PdF");
    assert_eq!(named.title.as_deref(), Some("Title-with-hyphens"));
    assert_eq!(named.authors, vec!["Alice"]);
    assert_eq!(named.year.as_deref(), Some("2024"));
    let cnki = metadata::parse_filename("/papers/先进材料的研究_张三.pdf");
    assert_eq!(cnki.title.as_deref(), Some("先进材料的研究"));
    assert_eq!(cnki.authors, vec!["张三"]);
    assert!(
        metadata::parse_filename("attention_is_all_you_need.pdf")
            .title
            .is_none()
    );
    let properties = metadata::from_properties(&PdfProperties {
        title: Some("/tmp/tp426.eps".into()),
        author: Some("CNKI; Jane Doe and John Smith".into()),
        subject: Some("doi: 10.1234/Result.2025".into()),
        keywords: None,
    });
    assert!(properties.title.is_none());
    assert_eq!(properties.authors, vec!["Jane Doe", "John Smith"]);
    assert!(properties.journal.is_none());
    assert_eq!(properties.doi.as_deref(), Some("10.1234/Result.2025"));
    assert!(!metadata::plausible_title("Microsoft Word - Document2"));
    assert_eq!(
        metadata::identifier_from_text("See arXiv:2501.12345v2 for details")
            .unwrap()
            .kind,
        IdentifierKind::Arxiv
    );
    assert_eq!(
        metadata::identifier_from_text("ISBN-13: 978-0-306-40615-7")
            .unwrap()
            .kind,
        IdentifierKind::Isbn
    );
    assert!(metadata::identifier_from_text("ordinary numeric ID 9780306406157").is_none());
}

#[test]
fn chinese_first_page_uses_title_and_institution_anchors_without_turning_header_words_into_authors()
{
    let text = "中国科学 第40卷 文章编号：1000-0747(2026)01-001\n先进材料的研究\n张三1，李四2（1.中国科学院）\n摘要：测量结果。 DOI:10.1234/submitted.2024";
    let extracted = metadata::from_chinese_text(text, Some("先进材料的研究"));
    assert_eq!(extracted.authors, vec!["张三", "李四"]);
    assert_eq!(extracted.year.as_deref(), Some("2026"));
    assert_eq!(extracted.journal.as_deref(), Some("中国科学"));
    assert_eq!(extracted.doi.as_deref(), Some("10.1234/submitted.2024"));
    let fuzzy = metadata::from_chinese_text(
        "中国科学先进材料的研宄张三，李四（1.中国科学院）摘要",
        Some("先进材料的研究"),
    );
    assert_eq!(fuzzy.authors, vec!["张三", "李四"]);
    assert_eq!(fuzzy.journal.as_deref(), Some("中国科学"));
    assert!(metadata::non_person_name("文章编号"));
}

#[test]
fn book_layout_uses_longest_chinese_title_and_author_roles_but_excludes_reviewers() {
    let structure=Structure::from_value(&json!({"layoutParsingResults":[{"prunedResult":{"parsing_res_list":[
        {"block_id":1,"block_label":"doc_title","block_content":"English subtitle\n先进材料学导论\n教程"},
        {"block_id":2,"block_label":"text","block_content":"王五 主审\n张三 李四 主编"}
    ]}}]})).unwrap();
    let extracted = metadata::from_first_page(&structure.pages[0].blocks);
    assert_eq!(extracted.title.as_deref(), Some("先进材料学导论"));
    assert_eq!(extracted.authors, vec!["张三", "李四"]);
    let mut document = otter_core::storage::Document {
        id: "paper".into(),
        title: "old".into(),
        authors: vec![],
        journal: None,
        year: None,
        doi: None,
        keywords: vec!["existing keyword".into()],
        content_hash: Some("existing PDF".into()),
        added_at: 1,
    };
    extracted.apply(&mut document);
    assert_eq!(document.keywords, vec!["existing keyword"]);
    assert_eq!(document.content_hash.as_deref(), Some("existing PDF"));
}

#[test]
fn real_pdfium_decodes_unicode_info_and_streamed_xmp_overrides_properties() {
    use std::{io::Write, path::Path};
    use tokio_util::sync::CancellationToken;
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("metadata.pdf");
    let xml = r#"<x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:prism="http://prismstandard.org/namespaces/basic/2.0/"><rdf:RDF><rdf:Description><dc:title><rdf:Alt><rdf:li>XMP 正式标题</rdf:li></rdf:Alt></dc:title><dc:creator><rdf:Seq><rdf:li>Jane Doe</rdf:li><rdf:li>John Smith</rdf:li></rdf:Seq></dc:creator><prism:publicationName>Scientific Journal</prism:publicationName><prism:publicationDate>2025-10-01</prism:publicationDate><prism:doi>10.1234/xmp</prism:doi></rdf:Description></rdf:RDF></x:xmpmeta>"#;
    let title = std::iter::once(0xfeffu16)
        .chain("信息字典标题".encode_utf16())
        .map(|unit| format!("{unit:04x}"))
        .collect::<String>();
    let text = "BT /F1 12 Tf 20 150 Td (DOI: 10.1234/body) Tj ET";
    let objects=[
        "<< /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>".into(),
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".into(),
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>".into(),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".into(),
        format!("<< /Length {} >>\nstream\n{text}\nendstream",text.len()),
        format!("<< /Type /Metadata /Subtype /XML /Length {} >>\nstream\n{xml}\nendstream",xml.len()),
        format!("<< /Title <{title}> /Author (CNKI) /Subject (Info Journal) /Keywords (2024) >>"),
    ];
    let mut bytes = b"%PDF-1.7\n".to_vec();
    let mut offsets = vec![0usize];
    for (index, object) in objects.iter().enumerate() {
        offsets.push(bytes.len());
        writeln!(bytes, "{} 0 obj\n{object}\nendobj", index + 1).unwrap();
    }
    let xref = bytes.len();
    writeln!(bytes, "xref\n0 {}\n0000000000 65535 f ", offsets.len()).unwrap();
    for offset in offsets.iter().skip(1) {
        writeln!(bytes, "{offset:010} 00000 n ").unwrap();
    }
    writeln!(
        bytes,
        "trailer\n<< /Size {} /Root 1 0 R /Info 7 0 R >>\nstartxref\n{xref}\n%%EOF",
        offsets.len()
    )
    .unwrap();
    std::fs::write(&path, bytes).unwrap();
    let library = std::env::var_os("PDFIUM_LIBRARY_PATH").expect("real PDFium required");
    let mut pdf = otter_core::pdf::PdfService::new(Path::new(&library), 0).unwrap();
    let token = CancellationToken::new();
    let info = pdf.open(&path, None, &token).unwrap();
    assert_eq!(info.pages.len(), 1);
    let properties = pdf.metadata(info.handle).unwrap();
    assert_eq!(properties.title.as_deref(), Some("信息字典标题"));
    let local = metadata::from_properties(&properties);
    assert!(local.authors.is_empty());
    let combined = local.merge(metadata::xmp_from_pdf(&path, &token).unwrap());
    assert_eq!(combined.title.as_deref(), Some("XMP 正式标题"));
    assert_eq!(combined.authors, vec!["Jane Doe", "John Smith"]);
    assert_eq!(combined.journal.as_deref(), Some("Scientific Journal"));
    assert_eq!(combined.year.as_deref(), Some("2025"));
    assert_eq!(combined.doi.as_deref(), Some("10.1234/xmp"));
    let body = pdf
        .characters(info.handle, 0, &token)
        .unwrap()
        .into_iter()
        .map(|c| c.text)
        .collect::<String>();
    assert_eq!(
        metadata::identifier_from_text(&body).unwrap().value,
        "10.1234/body"
    );
}
