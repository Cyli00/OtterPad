mod support;

use otter_core::{
    ai::{
        AiClient,
        catalog::{CapabilityCatalog, ModelCapabilities, candidates},
        image::ImageRequest,
        types::*,
    },
    network,
};
use serde_json::{Value, json};
use support::{Reply, server};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn config(provider: Provider, base_url: String) -> ModelConfig {
    ModelConfig {
        provider,
        base_url,
        model: "image-model".into(),
        params: ModelParams::default(),
        thinking_spec: None,
        capabilities: None,
    }
}

#[tokio::test]
async fn capability_cache_refreshes_conditionally_and_model_listing_follows_pages() {
    let data = json!({"version":"2026-10-31","models":{"model-v1":{"imageInput":true,"tool":true,"webSearch":true,"thinking":{"adaptive":true,"levels":["low","high"],"sampling":false}}}});
    let (base,handle)=server(4,move|index,request|match index {
        0=>Reply{headers:vec![("ETag".into(),"\"catalog-version\"".into())],..Reply::json(data.clone())},
        1=>{assert!(request.head.to_lowercase().contains("if-none-match: \"catalog-version\""));Reply{status:304,..Reply::json(Value::Null)}},
        2=>{assert!(request.head.starts_with("GET /v1beta/models "));Reply::json(json!({"models":[{"name":"models/model-v1","displayName":"First"}],"nextPageToken":"page-two"}))},
        _=>{assert!(request.head.starts_with("GET /v1beta/models?pageToken=page-two "));Reply::json(json!({"models":[{"name":"models/embedding-model","supportedGenerationMethods":["embedContent"]}]}))},
    }).await;
    let root = tempdir().unwrap();
    let mut catalog = CapabilityCatalog::open(root.path()).unwrap();
    let token = CancellationToken::new();
    let client = network::client(None, false).unwrap();
    assert!(
        catalog
            .refresh(&client, &format!("{base}/caps"), false, &token)
            .await
            .unwrap()
    );
    assert!(
        !catalog
            .refresh(&client, &format!("{base}/caps"), false, &token)
            .await
            .unwrap()
    );
    assert!(
        !catalog
            .refresh(&client, &format!("{base}/caps"), true, &token)
            .await
            .unwrap()
    );
    let catalog = CapabilityCatalog::open(root.path()).unwrap();
    assert_eq!(catalog.version(), Some("2026-10-31"));
    assert!(
        catalog
            .capabilities("vendor/model-v1-fast-20261031", None)
            .web_search
    );
    assert_eq!(
        catalog.thinking("model-v1").unwrap().nearest("medium"),
        "low"
    );
    let manual = ModelCapabilities::default();
    assert!(!catalog.capabilities("model-v1", Some(&manual)).web_search);
    let models = AiClient::new(None, false)
        .unwrap()
        .models(
            &config(Provider::Gemini, base),
            "key",
            Some(&catalog),
            &token,
        )
        .await
        .unwrap();
    assert_eq!(models.len(), 2);
    assert!(
        models
            .iter()
            .any(|m| m.id == "embedding-model" && m.capabilities.embedding)
    );
    assert!(
        models
            .iter()
            .any(|m| m.id == "model-v1" && m.capabilities.image_input)
    );
    assert_eq!(handle.await.unwrap().len(), 4);
}

#[tokio::test]
async fn image_protocols_use_versioned_endpoints_and_decode_real_payload_bytes() {
    let input = ImageRequest {
        prompt: "paper infographic".into(),
        references: Vec::new(),
        aspect_ratio: "16:9".into(),
        fidelity: "high".into(),
        capabilities: ModelCapabilities {
            image_output: true,
            ..Default::default()
        },
    };
    let (base,handle)=server(2,|index,request| {
        let body:Value=serde_json::from_slice(&request.body).unwrap();
        if index==0 {
            assert!(request.head.starts_with("POST /v3/images/generations "));assert_eq!(body["size"],"1536x864");assert_eq!(body["quality"],"high");assert_eq!(body["output_format"],"webp");
            Reply::json(json!({"data":[{"b64_json":"UklGRgQAAABXRUJQ"}]}))
        } else {
            assert!(request.head.starts_with("POST /v3/models/image-model:generateContent "));assert_eq!(body["generationConfig"]["imageConfig"]["imageSize"],"2K");assert_eq!(body["contents"][0]["parts"][0]["text"],"paper infographic");
            Reply::json(json!({"candidates":[{"content":{"parts":[{"text":"Figure description"},{"inlineData":{"mimeType":"image/png","data":"iVBORw0KGgo="}},{"text":"Source details"}]},"finishReason":"STOP"}]}))
        }
    }).await;
    let ai = AiClient::new(None, false).unwrap();
    let token = CancellationToken::new();
    let openai = ai
        .generate_image(
            &config(Provider::Openai, format!("{base}/v3")),
            "key",
            &input,
            &token,
        )
        .await
        .unwrap();
    assert_eq!(openai.bytes, b"RIFF\x04\0\0\0WEBP");
    assert_eq!(openai.mime_type, "image/webp");
    let gemini = ai
        .generate_image(
            &config(Provider::Gemini, format!("{base}/v3")),
            "key",
            &input,
            &token,
        )
        .await
        .unwrap();
    assert_eq!(gemini.bytes, b"\x89PNG\r\n\x1a\n");
    assert_eq!(gemini.text, "Figure description\nSource details");
    handle.await.unwrap();
}

#[test]
fn candidate_normalization_never_strips_capability_changing_model_suffixes() {
    assert_eq!(
        candidates("us.anthropic.claude-opus-4.8-fast:free"),
        [
            "us.anthropic.claude-opus-4.8-fast:free",
            "claude-opus-4.8-fast",
            "claude-opus-4.8"
        ]
    );
    assert_eq!(
        candidates("vendor/gpt-5-mini-latest"),
        ["gpt-5-mini-latest", "gpt-5-mini"]
    );
}
