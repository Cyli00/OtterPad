use otter_core::document::{DocumentModel, figures::find_figures, structure::Structure};
use serde_json::{Value, json};

fn page(blocks: Vec<Value>) -> Value {
    json!({"page_size":[600,800],"prunedResult":{"parsing_res_list":blocks},"markdown":{"text":""}})
}
fn block(id: &str, label: &str, text: &str, bbox: [f64; 4]) -> Value {
    json!({"block_id":id,"block_label":label,"block_content":text,"block_bbox":bbox})
}

#[test]
fn competing_equally_plausible_captions_do_not_arbitrarily_claim_the_image() {
    let raw = json!([page(vec![
        block("image", "image", "", [100.0, 100.0, 300.0, 300.0]),
        block(
            "above",
            "figure_title",
            "Figure 1. Upper caption.",
            [100.0, 70.0, 300.0, 90.0]
        ),
        block(
            "below",
            "figure_title",
            "Figure 2. Lower caption.",
            [100.0, 310.0, 300.0, 330.0]
        )
    ])]);
    assert!(find_figures(&Structure::from_value(&raw).unwrap()).is_empty());
}

#[test]
fn provider_hierarchy_pairs_caption_without_inventing_caption_coordinates() {
    let pages = vec![
        json!([{"type":"image","bbox":[0,0,1000,500],"content":{"image_source":{"path":"images/figure.png"},"image_caption":"Figure 1. Native caption."}}]),
    ];
    let structure = Structure::from_mineru_v2(&pages, &[vec![600.0, 800.0]]).unwrap();
    assert!(structure.pages[0].blocks[1].raw_bbox.is_empty());
    let figures = find_figures(&structure);
    assert_eq!(figures.len(), 1);
    assert_eq!(figures[0].caption_text, "Figure 1. Native caption.");
    assert_eq!(
        figures[0]
            .blocks
            .iter()
            .filter(|b| b.block_label == "image")
            .count(),
        1
    );
    let model = DocumentModel::from_structure(&structure);
    assert_eq!(
        model.blocks.iter().filter(|b| b.owner_id.is_none()).count(),
        1
    );
    assert_eq!(
        model
            .blocks
            .iter()
            .find(|b| b.owner_id.is_none())
            .unwrap()
            .image
            .as_deref(),
        Some("images/figure.png")
    );
}

#[test]
fn caption_on_following_page_can_own_a_dominant_full_page_figure() {
    let raw = json!([
        page(vec![block("image", "image", "", [0.0, 0.0, 600.0, 790.0])]),
        page(vec![
            block(
                "body",
                "text",
                "Discussion paragraph.",
                [10.0, 0.0, 590.0, 300.0]
            ),
            block(
                "caption",
                "figure_title",
                "Figure 1. Caption on the next page.",
                [0.0, 600.0, 590.0, 700.0]
            )
        ])
    ]);
    let figures = find_figures(&Structure::from_value(&raw).unwrap());
    assert_eq!(figures.len(), 1);
    assert!(figures[0].cross_page);
    assert_eq!(figures[0].page_index, 0);
    assert_eq!(figures[0].caption_refs[0].page_index, 1);
}

#[test]
fn consuming_a_caption_range_preserves_body_text_from_the_same_ocr_block() {
    let raw = json!([page(vec![
        block("image", "image", "", [10.0, 10.0, 500.0, 280.0]),
        block(
            "mixed",
            "text",
            "Body sentence.\n\nFigure 1. Caption.",
            [10.0, 300.0, 500.0, 400.0]
        )
    ])]);
    let model = DocumentModel::from_structure(&Structure::from_value(&raw).unwrap());
    assert_eq!(model.figures.len(), 1);
    assert!(
        model
            .blocks
            .iter()
            .any(|b| b.owner_id.is_none() && b.text == "Body sentence.")
    );
    assert!(
        model
            .blocks
            .iter()
            .any(|b| b.owner_id.is_none() && b.text == "Figure 1. Caption.")
    );
}
