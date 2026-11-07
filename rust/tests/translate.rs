mod support;

use otter_core::{
    ai::{AiClient, types::*},
    document::revision,
    error::ErrorCode,
    translate::{TranslationConfig, TranslationEvent, Translator, paragraph, protected::Protected},
};
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashSet};
use support::{Reply, server};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn model(base_url: String) -> ModelConfig {
    ModelConfig {
        provider: Provider::OpenaiCompatible,
        base_url,
        model: "translation-model".into(),
        params: ModelParams::default(),
        thinking_spec: None,
        capabilities: None,
    }
}

#[tokio::test]
async fn stream_fallback_keeps_formulas_and_caches_only_completed_translation() {
    let (base,handle)=server(3,|index,request| {
        assert!(request.head.starts_with("POST /v1/chat/completions "));
        let body:Value=serde_json::from_slice(&request.body).unwrap();
        assert_eq!(body["thinking"]["type"],"disabled");
        assert_eq!(body["messages"][1]["content"],"Translate to zh:\n\nSource [[m0]] and [[m1]].");
        if index==0 {Reply::sse("data: {\"choices\":[{\"delta\":{\"content\":\"残缺 \"}}]}\n\n")}
        else {Reply::json(json!({"choices":[{"message":{"content":if index == 1 {"译文 [[ m0 ]] 和 [[m1]]."} else {"新译文 [[m0]] 和 [[m1]]."}},"finish_reason":"stop"}]}))}
    }).await;
    let root = tempdir().unwrap();
    let translator = Translator::new(AiClient::new(None, false).unwrap(), root.path().into());
    let model = model(base);
    let config = TranslationConfig::new("zh".into());
    let token = CancellationToken::new();
    let mut snapshots = Vec::new();
    let text = translator
        .selection_stream(
            "Source $a+b$ and `code`.",
            &model,
            "key",
            &config,
            true,
            &token,
            |text| {
                snapshots.push(text);
                Ok(())
            },
        )
        .await
        .unwrap();
    assert_eq!(text, "译文 $a+b$ 和 `code`.");
    assert_eq!(snapshots.first().unwrap(), "残缺 ");
    assert_eq!(snapshots.last().unwrap(), &text);
    // A cache hit must retain the old result while the server is waiting to supply a different one.
    let reopened = Translator::new(AiClient::new(None, false).unwrap(), root.path().into());
    assert_eq!(
        reopened
            .selection(
                "Source $a+b$ and `code`.",
                &model,
                "key",
                &config,
                true,
                &token
            )
            .await
            .unwrap(),
        text
    );
    let cache = std::fs::read_dir(root.path().join("cache/translation"))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let mut value: Value = serde_json::from_slice(&std::fs::read(&cache).unwrap()).unwrap();
    value["created_at"] = json!(1);
    std::fs::write(&cache, serde_json::to_vec(&value).unwrap()).unwrap();
    let expired = reopened
        .selection(
            "Source $a+b$ and `code`.",
            &model,
            "key",
            &config,
            true,
            &token,
        )
        .await
        .unwrap();
    assert_eq!(expired, "新译文 $a+b$ 和 `code`.");
    assert_eq!(handle.await.unwrap().len(), 3);
}

#[tokio::test]
async fn cancellation_flushes_completed_document_paragraph_and_resume_uses_it() {
    let (base, handle) = server(1, |_, _| {
        Reply::json(json!({"choices":[{"message":{"content":"已完成"},"finish_reason":"stop"}]}))
    })
    .await;
    let root = tempdir().unwrap();
    std::fs::create_dir_all(root.path().join("library/paper")).unwrap();
    let translator = Translator::new(AiClient::new(None, false).unwrap(), root.path().into());
    translator
        .save(
            "paper",
            "ja",
            &BTreeMap::from([("old".into(), "既存".into())]),
        )
        .await
        .unwrap();
    let paragraphs = paragraph::extract("First paragraph.", &HashSet::new());
    let token = CancellationToken::new();
    let error = translator
        .document(
            "paper",
            &paragraphs,
            &model(base.clone()),
            "key",
            &TranslationConfig::new("zh".into()),
            true,
            &token,
            |event| {
                if matches!(event, TranslationEvent::Result { .. }) {
                    token.cancel();
                }
                Ok(())
            },
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::Cancelled);
    handle.await.unwrap();
    assert_eq!(
        translator.load("paper", "zh").await.unwrap()[&revision("First paragraph.")],
        "已完成"
    );
    assert_eq!(translator.load("paper", "ja").await.unwrap()["old"], "既存");
    let report = translator
        .document(
            "paper",
            &paragraphs,
            &model(base),
            "key",
            &TranslationConfig::new("zh".into()),
            true,
            &CancellationToken::new(),
            |_| Ok(()),
        )
        .await
        .unwrap();
    assert_eq!(report.completed, 1);
    assert_eq!(report.cached, 1);
    translator.clear("paper", "zh").await.unwrap();
    assert!(translator.load("paper", "zh").await.unwrap().is_empty());
    assert_eq!(translator.load("paper", "ja").await.unwrap()["old"], "既存");
}

#[test]
fn protected_spans_and_section_selection_preserve_real_source_boundaries() {
    let source = "Cost $5 and $10; $a+b$ `x=$c$` \\(u\\) \\[v\\] ⟪$inside$⟫ [[m0]]";
    let protected = Protected::mask(source);
    assert!(protected.masked.contains("$5 and $10"));
    assert_eq!(protected.restore(&protected.masked, true).unwrap(), source);
    assert!(protected.restore("missing everything", true).is_err());
    assert!(
        protected
            .restore(&(protected.masked.clone() + " [[m1]]"), true)
            .is_err()
    );
    let markdown = "# Title\n\n正文🦦 $inline$.\n\n```rust\nlet a=1;\n\nlet b=2;\n```\n\n$$E=mc^2$$\n\n![figure](a.png)\n\n| a | b |\n|---|---|\n|1|2|\n\n## References\n\nOne citation.\n\nAnother citation.\n\n## Acknowledgments\n\nThank you.";
    let paragraphs = paragraph::extract(
        markdown,
        &HashSet::from(["references".into(), "acknowledgments".into()]),
    );
    assert_eq!(
        paragraphs
            .iter()
            .map(|p| p.source.as_str())
            .collect::<Vec<_>>(),
        vec![
            "# Title",
            "正文🦦 $inline$.",
            "## References",
            "## Acknowledgments"
        ]
    );
    for paragraph in &paragraphs {
        let units: Vec<u16> = markdown.encode_utf16().collect();
        assert_eq!(
            String::from_utf16(&units[paragraph.start_utf16..paragraph.end_utf16]).unwrap(),
            paragraph.source
        );
    }
    let merged = paragraph::extract(markdown, &HashSet::new());
    assert!(
        merged
            .iter()
            .any(|p| p.source == "One citation.\n\nAnother citation.")
    );
    assert!(merged.iter().any(|p| p.source == "Thank you."));
}

#[tokio::test]
async fn missing_protected_content_is_rejected_and_never_written_to_cache() {
    let (base, handle) = server(1, |_, _| {
        Reply::json(
            json!({"choices":[{"message":{"content":"公式被删除"},"finish_reason":"stop"}]}),
        )
    })
    .await;
    let root = tempdir().unwrap();
    let translator = Translator::new(AiClient::new(None, false).unwrap(), root.path().into());
    assert_eq!(
        translator
            .selection(
                "Keep $x$.",
                &model(base),
                "key",
                &TranslationConfig::new("zh".into()),
                false,
                &CancellationToken::new()
            )
            .await
            .unwrap_err()
            .code,
        ErrorCode::InvalidData
    );
    assert!(!root.path().join("cache/translation").exists());
    handle.await.unwrap();
}

#[tokio::test]
async fn right_to_left_targets_add_the_formula_and_table_guard() {
    let (base, handle) = server(2, |index, request| {
        let body: Value = serde_json::from_slice(&request.body).unwrap();
        let system = body["messages"][0]["content"].as_str().unwrap();
        assert_eq!(system.contains("right to left"), index == 0);
        Reply::json(json!({"choices":[{"message":{"content":"ترجمه"},"finish_reason":"stop"}]}))
    })
    .await;
    let root = tempdir().unwrap();
    let translator = Translator::new(AiClient::new(None, false).unwrap(), root.path().into());
    let model = model(base);
    let token = CancellationToken::new();
    for language in ["فارسی", "English"] {
        let config = TranslationConfig::new(language.into());
        translator
            .selection("Text", &model, "key", &config, false, &token)
            .await
            .unwrap();
    }
    assert_eq!(handle.await.unwrap().len(), 2);
}
