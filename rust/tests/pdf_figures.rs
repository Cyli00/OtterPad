use otter_core::{
    document::{figures::find_figures, structure::Structure},
    error::ErrorCode,
    pdf::{PdfService, PixelRect, RenderRequest, figures},
};
use serde_json::json;
use std::{io::Cursor, path::Path};
use tokio_util::sync::CancellationToken;

fn decode(bytes: &[u8]) -> (u32, u32, Vec<u8>) {
    let mut reader = png::Decoder::new(Cursor::new(bytes)).read_info().unwrap();
    let mut rgba = vec![0; reader.output_buffer_size().unwrap()];
    let info = reader.next_frame(&mut rgba).unwrap();
    assert_eq!(info.color_type, png::ColorType::Rgba);
    rgba.truncate(info.buffer_size());
    (info.width, info.height, rgba)
}

#[test]
fn real_pdf_crops_match_rendered_pixels_preserve_rotated_page_geometry_and_combine_continuations() {
    let library = std::env::var_os("PDFIUM_LIBRARY_PATH").expect("real PDFium required");
    let mut pdf = PdfService::new(Path::new(&library), 0).unwrap();
    let token = CancellationToken::new();
    let info = pdf
        .open(
            &Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/two_pages.pdf"),
            None,
            &token,
        )
        .unwrap();
    let structure=Structure::from_value(&json!({"layoutParsingResults":[
        {"page_size":[600,400],"prunedResult":{"parsing_res_list":[
            {"block_id":"image1","block_label":"image","block_bbox":[40,40,360,200],"block_content":""},
            {"block_id":"caption1","block_label":"figure_title","block_bbox":[40,210,500,240],"block_content":"Figure 1. Measured result"}
        ]}},
        {"page_size":[400,600],"prunedResult":{"parsing_res_list":[
            {"block_id":"image2","block_label":"image","block_bbox":[50,100,300,500],"block_content":""},
            {"block_id":"caption2","block_label":"figure_title","block_bbox":[50,510,350,540],"block_content":"Figure 2. Rotated result"}
        ]}}
    ]})).unwrap();
    let mut segments = find_figures(&structure);
    assert_eq!(segments.len(), 2);
    let crops = figures::render(&mut pdf, &info, &structure, &segments, &token, |_, _| {}).unwrap();
    assert_eq!(crops.figures.len(), 2);
    // Encode through the same public OCR publication path, then decode actual PNG files.
    let mut output = otter_core::ocr::OcrOutput {
        provider: otter_core::ocr::Provider::Paddleocr,
        raw: structure.legacy_json(Some("paddleocr")),
        raw_markdown: String::new(),
        structure: structure.clone(),
        model: otter_core::document::DocumentModel::from_structure(&structure),
        assets: crops.assets.clone(),
        export_zip: None,
    };
    let expected = pdf
        .render(
            &RenderRequest {
                document: info.handle,
                page: 0,
                scale: 3.0,
                tile: PixelRect {
                    x: 60,
                    y: 60,
                    width: 480,
                    height: 240,
                },
                annotations: false,
            },
            &token,
        )
        .unwrap();
    // The manifest exposes crop dimensions and source coordinates without provider JSON.
    assert_eq!(
        (crops.figures[0].width_px, crops.figures[0].height_px),
        (480, 240)
    );
    assert_eq!(
        crops.figures[0].visual_regions[0].bbox,
        vec![40.0, 40.0, 360.0, 200.0]
    );
    let root = tempfile::tempdir().unwrap();
    let first_png = crops.assets[&format!("figures/{}", crops.figures[0].image_path)].clone();
    output
        .assets
        .insert("images/reference.png".into(), first_png.clone());
    let generation = otter_core::ocr::publish(root.path(), &output, &token).unwrap();
    let saved = root
        .path()
        .join("ocr")
        .join(&generation)
        .join("figures")
        .join(&crops.figures[0].image_path);
    let (width, height, rgba) = decode(&std::fs::read(saved).unwrap());
    assert_eq!((width, height), (480, 240));
    assert_eq!(rgba, expected.rgba);
    let second_png = crops.assets[&format!("figures/{}", crops.figures[1].image_path)].clone();
    let rotated = pdf
        .render(
            &RenderRequest {
                document: info.handle,
                page: 1,
                scale: 3.0,
                tile: PixelRect {
                    x: 75,
                    y: 150,
                    width: 375,
                    height: 600,
                },
                annotations: false,
            },
            &token,
        )
        .unwrap();
    assert_eq!(decode(&second_png).2, rotated.rgba);
    output
        .assets
        .insert("images/reference.png".into(), second_png);
    let newer = otter_core::ocr::publish(root.path(), &output, &token).unwrap();
    assert_ne!(generation, newer);
    assert_eq!(
        std::fs::read(
            root.path()
                .join("ocr")
                .join(generation)
                .join("images/reference.png")
        )
        .unwrap(),
        first_png
    );
    let first = segments[0].caption_refs[0].clone();
    segments[1].caption_refs.push(first);
    let combined =
        figures::render(&mut pdf, &info, &structure, &segments, &token, |_, _| {}).unwrap();
    assert_eq!(combined.figures.len(), 1);
    assert_eq!(combined.figures[0].segment_ids.len(), 2);
    assert_eq!(
        (combined.figures[0].width_px, combined.figures[0].height_px),
        (480, 888)
    );
    let (_, _, combined_pixels) =
        decode(&combined.assets[&format!("figures/{}", combined.figures[0].image_path)]);
    assert_eq!(
        &combined_pixels[..expected.rgba.len()],
        expected.rgba.as_slice()
    );
    let second_row = 264usize * 480 * 4 + 52 * 4;
    assert_eq!(
        &combined_pixels[second_row..second_row + 375 * 4],
        &rotated.rgba[..375 * 4]
    );
    let cancelled = CancellationToken::new();
    cancelled.cancel();
    assert_eq!(
        figures::render(
            &mut pdf,
            &info,
            &structure,
            &segments,
            &cancelled,
            |_, _| {}
        )
        .err()
        .unwrap()
        .code,
        ErrorCode::Cancelled
    );
}
