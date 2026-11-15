//! 标题分级：OCR 只给出“标题”标签时，按编号、字号与首页大标题推断层级。
use otter_core::document::{BlockKind, DocumentModel, structure::Structure};
use serde_json::{Value, json};

fn page(blocks: Vec<Value>) -> Value {
    json!({"page_size":[1200,1600],"prunedResult":{"parsing_res_list":blocks},"markdown":{"text":""}})
}
/// 单行标题：框高 = 字号 × 1.25，框足够宽。
fn heading(id: &str, text: &str, top: f64, size: f64) -> Value {
    json!({"block_id":id,"block_label":"paragraph_title","block_content":text,
           "block_bbox":[70.0, top, 1100.0, top + size * 1.25]})
}
fn body(id: &str, top: f64) -> Value {
    json!({"block_id":id,"block_label":"text","block_content":"Body paragraph text.",
           "block_bbox":[70.0, top, 1100.0, top + 80.0]})
}

/// 按出现顺序返回 (标题原文, 层级)。
fn levels(pages: Vec<Vec<Value>>) -> Vec<(String, u8)> {
    let raw = Value::Array(pages.into_iter().map(page).collect());
    DocumentModel::from_structure(&Structure::from_value(&raw).unwrap())
        .blocks
        .into_iter()
        .filter(|b| b.kind == BlockKind::Heading)
        .map(|b| (b.markdown, b.heading_level.unwrap()))
        .collect()
}
fn expect(pairs: &[(&str, u8)]) -> Vec<(String, u8)> {
    pairs.iter().map(|(t, l)| (t.to_string(), *l)).collect()
}

/// 《Deep learning》：首页大标题，其余节标题字号相同且无编号。
#[test]
fn first_page_title_sits_above_unnumbered_sections() {
    let found = levels(vec![
        vec![
            json!({"block_id":"t","block_label":"doc_title","block_content":"Deep learning",
                   "block_bbox":[70.0, 208.0, 433.0, 270.0]}),
            body("p0", 300.0),
            json!({"block_id":"h0","block_label":"paragraph_title",
                   "block_content":"Supervised learning","block_bbox":[596.0, 930.0, 787.0, 953.0]}),
        ],
        vec![
            json!({"block_id":"h1","block_label":"paragraph_title",
                   "block_content":"Backpropagation to train multilayer architectures",
                   "block_bbox":[69.0, 1203.0, 519.0, 1225.0]}),
            body("p1", 1300.0),
        ],
    ]);
    assert_eq!(
        found,
        expect(&[
            ("Deep learning", 1),
            ("Supervised learning", 2),
            ("Backpropagation to train multilayer architectures", 2),
        ])
    );
}

/// 两行的长标题按面积估算字号，仍识别为文档标题。
#[test]
fn wrapped_document_title_is_recognised_by_area() {
    let found = levels(vec![vec![
        json!({"block_id":"t","block_label":"paragraph_title",
               "block_content":"A very long document title that wraps onto a second line",
               "block_bbox":[70.0, 100.0, 570.0, 175.0]}),
        heading("h", "Introduction", 300.0, 18.0),
        body("p", 340.0),
        heading("h2", "Method", 500.0, 18.0),
    ]]);
    assert_eq!(
        found,
        expect(&[
            (
                "A very long document title that wraps onto a second line",
                1
            ),
            ("Introduction", 2),
            ("Method", 2),
        ])
    );
}

/// 十进制编号定层级；无编号的 Abstract、References 与一级节对齐。
#[test]
fn decimal_numbering_sets_depth_and_unnumbered_sections_align_by_size() {
    let found = levels(vec![
        vec![
            heading("a", "Abstract", 100.0, 18.0),
            body("pa", 140.0),
            heading("h1", "1 Introduction", 300.0, 18.0),
            body("p1", 340.0),
            heading("h2", "2. Method", 500.0, 18.0),
            heading("h21", "2.1 Data", 560.0, 16.0),
            heading("h211", "2.1.1 Cleaning", 620.0, 14.0),
        ],
        vec![
            heading("h3", "3 Results", 100.0, 18.0),
            body("p3", 140.0),
            heading("r", "References", 300.0, 18.0),
        ],
    ]);
    assert_eq!(
        found,
        expect(&[
            ("Abstract", 1),
            ("1 Introduction", 1),
            ("2. Method", 1),
            ("2.1 Data", 2),
            ("2.1.1 Cleaning", 3),
            ("3 Results", 1),
            ("References", 1),
        ])
    );
}

/// 漏识别了“1 Introduction”时，“1.1”仍排在“2”之下。
#[test]
fn deeper_decimal_seen_first_does_not_invert_levels() {
    let found = levels(vec![vec![
        heading("h11", "1.1 Background", 100.0, 16.0),
        body("p", 140.0),
        heading("h2", "2 Method", 300.0, 18.0),
    ]]);
    assert_eq!(found, expect(&[("1.1 Background", 2), ("2 Method", 1)]));
}

/// IEEE：罗马数字 > 大写字母 > 1)；C. 是字母不是罗马数字 100。
#[test]
fn ieee_roman_letter_and_parenthesised_numbering_nest() {
    let found = levels(vec![vec![
        heading("a", "I. INTRODUCTION", 100.0, 16.0),
        heading("b", "A. Background", 160.0, 16.0),
        heading("c", "1) Detail", 220.0, 16.0),
        heading("d", "II. METHOD", 280.0, 16.0),
        heading("e", "B. Setup", 340.0, 16.0),
        heading("f", "C. Results", 400.0, 16.0),
    ]]);
    assert_eq!(
        found,
        expect(&[
            ("I. INTRODUCTION", 1),
            ("A. Background", 2),
            ("1) Detail", 3),
            ("II. METHOD", 1),
            ("B. Setup", 2),
            ("C. Results", 2),
        ])
    );
}

/// 字母编号 H 之后的 I. 是字母，不是罗马数字 1。
#[test]
fn letter_i_after_h_stays_a_letter() {
    let found = levels(vec![vec![
        heading("a", "I. INTRODUCTION", 100.0, 16.0),
        heading("b", "H. Eighth", 160.0, 16.0),
        heading("c", "I. Ninth", 220.0, 16.0),
        heading("d", "II. METHOD", 280.0, 16.0),
    ]]);
    assert_eq!(
        found,
        expect(&[
            ("I. INTRODUCTION", 1),
            ("H. Eighth", 2),
            ("I. Ninth", 2),
            ("II. METHOD", 1),
        ])
    );
}

/// 中文论文：一、 > （一） > 1.，十进制编号排在中文编号之下。
#[test]
fn chinese_numbering_nests_by_first_appearance() {
    let found = levels(vec![vec![
        heading("a", "一、引言", 100.0, 18.0),
        heading("b", "（一）研究背景", 160.0, 16.0),
        heading("c", "1. 数据来源", 220.0, 15.0),
        heading("d", "二、方法", 280.0, 18.0),
    ]]);
    assert_eq!(
        found,
        expect(&[
            ("一、引言", 1),
            ("（一）研究背景", 2),
            ("1. 数据来源", 3),
            ("二、方法", 1),
        ])
    );
}

/// 无编号时按字号分层；差异在 10% 以内视为同一层。
#[test]
fn unnumbered_headings_tier_by_size() {
    let found = levels(vec![vec![
        heading("a", "Overview", 100.0, 18.0),
        heading("b", "Details", 160.0, 14.0),
        heading("c", "Findings", 220.0, 17.0),
        heading("d", "Notes", 280.0, 14.5),
    ]]);
    assert_eq!(
        found,
        expect(&[
            ("Overview", 1),
            ("Details", 2),
            ("Findings", 1),
            ("Notes", 2),
        ])
    );
}
