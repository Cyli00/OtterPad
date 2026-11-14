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

#[test]
fn block_units_follow_the_reader_blocks_and_skip_ignored_back_matter() {
    let markdown = "# Title\n\nBody $x$.\n\n$$E=mc^2$$\n\n## References\n\nOne citation.\n\n## Acknowledgments\n\nThank you.";
    let model = otter_core::document::DocumentModel::from_markdown(markdown);
    let sources = |ignored: &[&str]| {
        paragraph::blocks(
            &model,
            &ignored
                .iter()
                .map(|s| s.to_string())
                .collect::<HashSet<_>>(),
        )
        .into_iter()
        .map(|p| {
            assert_eq!(p.hash, revision(p.source.trim()));
            p.source
        })
        .collect::<Vec<_>>()
    };
    let all = sources(&[]);
    assert!(all.contains(&"Body $x$.".to_string()));
    assert!(all.contains(&"One citation.".to_string()));
    assert!(!all.iter().any(|s| s.contains("$$")));
    let skipped = sources(&["references"]);
    assert!(!skipped.contains(&"One citation.".to_string()));
    assert!(skipped.contains(&"Thank you.".to_string()));
    for block in &model.blocks {
        if let Some(key) = paragraph::block_key(block) {
            assert_eq!(key, revision(block.markdown.trim()));
        }
    }
}

#[tokio::test]
async fn document_translation_backs_off_when_provider_limits_concurrency() {
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };
    use tokio::{io::AsyncWriteExt, net::TcpListener};
    // 服务端同时最多处理 4 个请求，超出返回 429。
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let active = Arc::new(AtomicUsize::new(0));
    let peak = Arc::new(AtomicUsize::new(0));
    let limited = Arc::new(AtomicUsize::new(0));
    let server = {
        let (active, peak, limited) = (active.clone(), peak.clone(), limited.clone());
        tokio::spawn(async move {
            loop {
                let (mut socket, _) = listener.accept().await.unwrap();
                let (active, peak, limited) = (active.clone(), peak.clone(), limited.clone());
                tokio::spawn(async move {
                    let _ = support::read(&mut socket).await;
                    let now = active.fetch_add(1, Ordering::SeqCst) + 1;
                    peak.fetch_max(now, Ordering::SeqCst);
                    let (status, body) = if now > 4 {
                        limited.fetch_add(1, Ordering::SeqCst);
                        (
                            "429 Too Many Requests",
                            r#"{"error":{"type":"rate_limit_error"}}"#.to_owned(),
                        )
                    } else {
                        tokio::time::sleep(std::time::Duration::from_millis(80)).await;
                        ("200 OK", json!({"choices":[{"message":{"content":"译文"},"finish_reason":"stop"}]}).to_string())
                    };
                    active.fetch_sub(1, Ordering::SeqCst);
                    let reply = format!(
                        "HTTP/1.1 {status}\r\ncontent-type: application/json\r\nretry-after: 1\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{body}",
                        body.len()
                    );
                    let _ = socket.write_all(reply.as_bytes()).await;
                });
            }
        })
    };
    let root = tempdir().unwrap();
    std::fs::create_dir_all(root.path().join("library/paper")).unwrap();
    let translator = Translator::new(AiClient::new(None, false).unwrap(), root.path().into());
    let markdown = (0..40)
        .map(|i| format!("Paragraph number {i}."))
        .collect::<Vec<_>>()
        .join("\n\n");
    let paragraphs = paragraph::extract(&markdown, &HashSet::new());
    assert_eq!(paragraphs.len(), 40);
    let report = translator
        .document(
            "paper",
            &paragraphs,
            &model(base),
            "key",
            &TranslationConfig::new("zh".into()),
            false,
            &CancellationToken::new(),
            |_| Ok(()),
        )
        .await
        .unwrap();
    server.abort();
    assert!(report.failures.is_empty(), "{:?}", report.failures.len());
    assert_eq!(report.completed, 40);
    assert!(peak.load(Ordering::SeqCst) > 4);
    assert!(limited.load(Ordering::SeqCst) > 0);
}
