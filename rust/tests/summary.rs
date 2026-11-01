mod support;

use base64::{Engine, engine::general_purpose::STANDARD};
use otter_core::{
    ai::{
        AiClient,
        catalog::ModelCapabilities,
        summary::{SummaryConfig, SummaryService, compact},
        types::*,
    },
    document::figures::supplementary_caption,
    error::ErrorCode,
    storage::Document,
};
use serde_json::{Value, json};
use support::{Reply, server};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn png_pixel(color: [u8; 4]) -> Vec<u8> {
    let mut bytes = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut bytes, 1, 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().unwrap();
        writer.write_image_data(&color).unwrap();
        writer.finish().unwrap();
    }
    bytes
}

#[tokio::test]
async fn summary_selects_primary_figures_and_publishes_image_and_metadata_together() {
    let root = tempdir().unwrap();
    let directory = root.path().join("library/paper");
    std::fs::create_dir_all(directory.join("figures")).unwrap();
    std::fs::create_dir_all(directory.join("summary")).unwrap();
    std::fs::write(directory.join("extract.raw.md"),"# Findings\n\nMeasured findings.\n\n![image](discard.png)\n\n## References\n\nExcluded citation text.").unwrap();
    let main_png = png_pixel([255, 0, 0, 255]);
    let supplementary_png = png_pixel([0, 0, 255, 255]);
    std::fs::create_dir_all(directory.join("figures/generation_old")).unwrap();
    for (name, bytes) in [
        ("supp.png", &supplementary_png),
        ("generation_old/main.png", &main_png),
        ("anonymous.png", &main_png),
    ] {
        std::fs::write(directory.join("figures").join(name), bytes).unwrap();
    }
    std::fs::write(
        directory.join("figures/figures.json"),
        serde_json::to_vec(&json!({"algorithm_version":4,"figures":[
            {"img":"supp.png","figure_title":"Supplementary Figure 1: extra findings"},
            {"img":"anonymous.png","figure_title":"","pair_method":"visualOnly"},
            {"img":"generation_old/main.png","figure_title":"Figure 1: measured result"}
        ]}))
        .unwrap(),
    )
    .unwrap();
    std::fs::write(directory.join("summary/summary.png"), &main_png).unwrap();
    let document = Document {
        id: "paper".into(),
        title: "Paper title".into(),
        authors: vec!["A. Author".into()],
        journal: Some("Journal".into()),
        year: Some("2025".into()),
        doi: Some("10.1234/paper".into()),
        keywords: vec!["result".into()],
        content_hash: Some("fingerprint".into()),
        added_at: 1,
    };
    let service = SummaryService::new(root.path().into());
    assert_eq!(
        service.current(&document).unwrap().unwrap().mime_type,
        "image/png"
    );
    let config = SummaryConfig {
        max_reference_images: 1,
        language: Some("Chinese".into()),
        ..Default::default()
    };
    let exported = service
        .compose(&document, &config, Provider::Openai)
        .unwrap();
    assert!(exported.contains("attached separately"));
    assert!(!exported.contains("Measured findings."));
    let expected_main = main_png.clone();
    let response_png = png_pixel([0, 255, 0, 255]);
    let encoded_response = STANDARD.encode(&response_png);
    let (base, handle) = server(2, move |index, request| {
        assert!(request.head.starts_with("POST /v1/images/edits "));
        let multipart = String::from_utf8_lossy(&request.body);
        if index == 0 {
            assert!(multipart.contains("Measured findings."));
            assert!(!multipart.contains("Excluded citation text."));
            assert!(!multipart.contains("discard.png"));
            assert!(
                request
                    .body
                    .windows(expected_main.len())
                    .any(|b| b == expected_main)
            );
            assert!(
                !request
                    .body
                    .windows(supplementary_png.len())
                    .any(|b| b == supplementary_png)
            );
            assert!(multipart.contains("must be in Chinese"));
            Reply::json(json!({"data":[{"b64_json":encoded_response}]}))
        } else {
            Reply {
                status: 429,
                ..Reply::json(json!({"error":{"type":"insufficient_quota"}}))
            }
        }
    })
    .await;
    let model = ModelConfig {
        provider: Provider::Openai,
        base_url: base,
        model: "image-model".into(),
        params: ModelParams::default(),
        thinking_spec: None,
        capabilities: None,
    };
    let capabilities = ModelCapabilities {
        image_output: true,
        ..Default::default()
    };
    let ai = AiClient::new(None, false).unwrap();
    let token = CancellationToken::new();
    let record = service
        .generate(
            &document,
            &config,
            &model,
            "key",
            &capabilities,
            &ai,
            &token,
        )
        .await
        .unwrap();
    assert_eq!(record.reference_image_count, 1);
    assert!(record.image_path.ends_with("image.png"));
    assert_eq!(std::fs::read(&record.image_path).unwrap(), response_png);
    let metadata: Value =
        serde_json::from_slice(&std::fs::read(&record.metadata_path).unwrap()).unwrap();
    assert_eq!(metadata["mimeType"], "image/png");
    assert_eq!(metadata["referenceImageCount"], 1);
    assert_eq!(metadata["documentId"], "paper");
    let pointer = std::fs::read(directory.join("summary/current.json")).unwrap();
    assert_eq!(
        service
            .generate(
                &document,
                &config,
                &model,
                "key",
                &capabilities,
                &ai,
                &token
            )
            .await
            .unwrap_err()
            .code,
        ErrorCode::QuotaExceeded
    );
    assert_eq!(
        std::fs::read(directory.join("summary/current.json")).unwrap(),
        pointer
    );
    assert_eq!(
        service.current(&document).unwrap().unwrap().image_path,
        record.image_path
    );
    assert!(directory.join("summary/summary.png").is_file());
    handle.await.unwrap();
}

#[test]
fn summary_compaction_observes_utf16_limit_and_supplementary_caption_rules() {
    for caption in [
        "Supplementary Figure 2: result",
        "Figure S1. result",
        "Extended Data Figure 1. result",
        "附图1：结果",
    ] {
        assert!(supplementary_caption(caption), "{caption}");
    }
    assert!(!supplementary_caption("Figure 1. Main findings"));
    let text = format!("# Body\n\n{}", "🦦".repeat(13000));
    let (compacted, offset) = compact(&text);
    assert_eq!(offset, None);
    assert!(compacted.ends_with("[Content truncated for image generation.]"));
    assert!(
        compacted[..compacted.find("\n\n[Content truncated").unwrap()]
            .encode_utf16()
            .count()
            <= 24000
    );
}
