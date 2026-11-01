use otter_core::{
    document::{BlockKind, DocumentModel, Table, utf16_slice},
    migrate::legacy_hash,
};

#[test]
fn anchor_offsets_follow_utf16_and_ambiguous_quotes_stay_unlocated() {
    let model = DocumentModel::from_markdown("# 标题\n\nA 🦦 quoted phrase end.");
    let paragraph = &model.blocks[1];
    assert_eq!(utf16_slice(&paragraph.text, 2, 3), None); // Half of an emoji is invalid.
    let anchor = model.anchor(&paragraph.id, 5, 18).unwrap();
    assert_eq!(anchor.quote, "quoted phrase");
    let changed =
        DocumentModel::from_markdown("# 标题\n\nA 🦦 quoted phrase end. Additional sentence.");
    let located = changed.resolve(&anchor).unwrap();
    assert_eq!(located.start, 5);
    assert_eq!(located.block_id, changed.blocks[1].id);
    let mut ambiguous = anchor.clone();
    ambiguous.block_id = "missing".into();
    ambiguous.prefix.clear();
    ambiguous.suffix.clear();
    let repeated = DocumentModel::from_markdown("quoted phrase\n\nquoted phrase");
    assert!(repeated.resolve(&ambiguous).is_none());
}

#[test]
fn blocks_keep_inline_math_styles_table_spans_and_stable_identities() {
    let source = "# Heading\n\n**Bold** *italic* $x^2$ and `code` [link](https://example.org).\n\n- one\n- two\n\n> quote\n\n$$E=mc^2$$\n\n| A | B |\n|---|---|\n| 1 | 2 |";
    let model = DocumentModel::from_markdown(source);
    assert_eq!(
        model
            .blocks
            .iter()
            .map(|b| b.kind.clone())
            .collect::<Vec<_>>(),
        vec![
            BlockKind::Heading,
            BlockKind::Paragraph,
            BlockKind::List,
            BlockKind::Quote,
            BlockKind::Equation,
            BlockKind::Table
        ]
    );
    let paragraph = &model.blocks[1];
    assert!(
        paragraph
            .runs
            .iter()
            .any(|r| r.math.as_deref() == Some("x^2"))
    );
    assert!(paragraph.runs.iter().any(|r| r.bold && r.text == "Bold"));
    assert_eq!(
        paragraph.text,
        paragraph
            .runs
            .iter()
            .map(|r| r.text.as_str())
            .collect::<String>()
    );
    let rebuilt = DocumentModel::from_markdown(&format!("New introduction.\n\n{source}"));
    assert_eq!(rebuilt.blocks[2].id, paragraph.id);
    let table = Table::parse(
        "<table><tr><th colspan='2'>A</th></tr><tr><td rowspan='2'>B</td><td>C</td></tr></table>",
    )
    .unwrap();
    assert_eq!(table.rows[0][0].col_span, 2);
    assert_eq!(table.rows[1][0].row_span, 2);
    assert!(table.rows[0][0].header);
    assert_eq!(
        model.blocks.last().unwrap().table.as_ref().unwrap().text(),
        "A\tB\n1\t2"
    );
}

#[test]
fn legacy_translation_hash_matches_dart_vm_reference_including_surrogates() {
    for (source, expected) in [
        ("", "0_1"),
        ("a", "1_a2e9442"),
        ("hello", "5_8fd181b"),
        ("自然语言", "4_3df6eac4"),
        ("🦦 a", "4_3311d40e"),
        ("Paragraph $x$", "13_46a4ef7"),
    ] {
        assert_eq!(legacy_hash(source), expected);
    }
}
