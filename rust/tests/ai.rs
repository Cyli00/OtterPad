mod support;

use otter_core::{
    ai::{
        AiClient, protocol,
        search::{SearchProvider, SearchService},
        types::*,
    },
    error::ErrorCode,
};
use serde_json::{Value, json};
use support::{Reply, server};
use tokio_util::sync::CancellationToken;

fn config(provider: Provider, base_url: String) -> ModelConfig {
    ModelConfig {
        provider,
        base_url,
        model: "configured-model".into(),
        params: ModelParams {
            thinking: Some(ThinkingLevel::Off),
            ..Default::default()
        },
        thinking_spec: None,
        capabilities: None,
    }
}
fn request() -> ChatRequest {
    ChatRequest {
        system: "research system".into(),
        messages: vec![Message {
            role: Role::User,
            text: "paper question".into(),
            images: vec![ImageInput {
                mime_type: "image/png".into(),
                bytes: b"png input".into(),
                label: Some("Figure 1".into()),
            }],
        }],
        show_reasoning: true,
        cache_prefix: true,
        ..Default::default()
    }
}

#[tokio::test]
async fn all_protocols_send_multimodal_requests_and_decode_split_sse() {
    for provider in [
        Provider::Openai,
        Provider::Anthropic,
        Provider::Gemini,
        Provider::OpenaiCompatible,
    ] {
        let sse = match provider {
            Provider::Openai => {
                "\u{feff}: heartbeat\r\nevent: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\r\ndata: \"delta\":\"正文🦦\"}\r\n\r\ndata: {\"type\":\"response.reasoning_summary_text.delta\",\"delta\":\"思考\"}\r\n\r\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":10,\"output_tokens\":4}}}\r\n\r\n"
            }
            Provider::Anthropic => {
                "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":10}}}\n\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"思考\"}}\n\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"正文🦦\"}}\n\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":4}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
            }
            Provider::Gemini => {
                "data: {\"candidates\":[{\"content\":{\"parts\":[{\"thought\":true,\"text\":\"思考\"},{\"text\":\"正文🦦\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":4}}\n\n"
            }
            Provider::OpenaiCompatible => {
                "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"思考\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"正文🦦\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":4}}\n\ndata: [DONE]\n\n"
            }
        };
        let (base, handle) = server(1, move |_, _| Reply::sse(sse)).await;
        let mut config = config(provider, format!("{base}/proxy/v4"));
        if provider == Provider::Anthropic {
            config.model = "claude-opus-4-7".into();
            config.params.temperature = Some(0.3);
        }
        let mut text = String::new();
        let response = AiClient::new(None, true)
            .unwrap()
            .stream(
                &config,
                "model-only-key",
                &request(),
                None,
                &CancellationToken::new(),
                |event| {
                    if let ChatEvent::TextDelta { text: delta } = event {
                        text.push_str(&delta);
                    }
                    Ok(())
                },
            )
            .await
            .unwrap();
        assert_eq!(text, "正文🦦");
        assert_eq!(response.text, text);
        assert_eq!(response.reasoning, "思考");
        assert_eq!(response.usage.input_tokens, Some(10));
        assert_eq!(response.usage.output_tokens, Some(4));
        let requests = handle.await.unwrap();
        let request = &requests[0];
        let body: Value = serde_json::from_slice(&request.body).unwrap();
        assert!(!request.head.contains("/v4/v1"));
        match provider {
            Provider::Openai => {
                assert!(request.head.starts_with("POST /proxy/v4/responses "));
                assert!(request.head.contains("Bearer model-only-key"));
                assert_eq!(body["input"][0]["content"][1]["type"], "input_image");
                assert_eq!(body["reasoning"]["summary"], "auto");
            }
            Provider::Anthropic => {
                assert!(
                    request
                        .head
                        .to_ascii_lowercase()
                        .contains("x-api-key: model-only-key"),
                    "{}",
                    request.head
                );
                assert!(body.get("temperature").is_none());
                assert_eq!(body["thinking"]["type"], "adaptive");
                assert_eq!(body["output_config"]["effort"], "low");
                assert_eq!(
                    body["messages"][0]["content"][1]["source"]["data"],
                    "cG5nIGlucHV0"
                );
            }
            Provider::Gemini => {
                assert!(request.head.starts_with(
                    "POST /proxy/v4/models/configured-model:streamGenerateContent?alt=sse "
                ));
                assert!(
                    request
                        .head
                        .to_ascii_lowercase()
                        .contains("x-goog-api-key: model-only-key")
                );
                assert_eq!(
                    body["contents"][0]["parts"][1]["inline_data"]["data"],
                    "cG5nIGlucHV0"
                );
            }
            Provider::OpenaiCompatible => {
                assert!(request.head.starts_with("POST /proxy/v4/chat/completions "));
                assert_eq!(body["messages"][1]["content"][1]["type"], "image_url");
                assert_eq!(body["thinking"]["type"], "disabled");
            }
        }
    }
}

#[tokio::test]
async fn structured_output_falls_back_only_for_rejected_format() {
    let (base,handle)=server(3,|index,request| {
        let body:Value=serde_json::from_slice(&request.body).unwrap();
        match index {
            0=>{assert_eq!(body["response_format"]["type"],"json_schema");Reply{status:400,..Reply::json(json!({"error":{"message":"private upstream diagnostic"}}))}},
            1=>{assert_eq!(body["response_format"]["type"],"json_object");Reply{status:422,..Reply::json(json!({}))}},
            _=>{assert!(body.get("response_format").is_none());assert!(body["messages"][0]["content"].as_str().unwrap().contains("matching this schema"));Reply::json(json!({"choices":[{"message":{"content":"{\"value\":7}"},"finish_reason":"stop"}]}))},
        }
    }).await;
    let mut input = request();
    input.schema = Some(JsonSchema {
        name: "result".into(),
        schema: json!({"type":"object","properties":{"value":{"type":"integer"}},"required":["value"],"additionalProperties":false}),
    });
    let response = AiClient::new(None, false)
        .unwrap()
        .send(
            &config(Provider::OpenaiCompatible, base),
            "key",
            &input,
            &CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&response.text).unwrap()["value"],
        7
    );
    assert_eq!(handle.await.unwrap().len(), 3);
}

#[tokio::test]
async fn external_search_executes_and_returns_tool_result_without_mixing_credentials() {
    let (base,handle)=server(3,|index,request| {
        match index {
            0=>Reply::sse("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call1\",\"function\":{\"name\":\"web_search\",\"arguments\":\"{\\\"query\\\":\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"latest result\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n"),
            1=> {assert!(request.head.starts_with("POST /search "));assert!(request.head.contains("Bearer search-only-key"));assert!(!request.head.contains("model-only-key"));let body:Value=serde_json::from_slice(&request.body).unwrap();assert_eq!(body["query"],"latest result");Reply::json(json!({"results":[{"title":"Primary result","url":"https://example.org/paper","content":"Verified evidence"}]}))},
            _=> {let body:Value=serde_json::from_slice(&request.body).unwrap();let messages=body["messages"].as_array().unwrap();assert_eq!(messages[messages.len()-2]["tool_calls"][0]["id"],"call1");let tool=&messages[messages.len()-1];assert_eq!(tool["tool_call_id"],"call1");assert!(tool["content"].as_str().unwrap().contains("Verified evidence"));assert!(!request.head.contains("search-only-key"));Reply::sse("data: {\"choices\":[{\"delta\":{\"content\":\"Supported answer\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")},
        }
    }).await;
    let mut search = SearchService::new(
        None,
        false,
        SearchProvider::Tavily,
        "search-only-key".into(),
    )
    .unwrap();
    search.endpoint = format!("{base}/search");
    let mut input = request();
    input.web_search = true;
    let response = AiClient::new(None, false)
        .unwrap()
        .stream(
            &config(Provider::OpenaiCompatible, base),
            "model-only-key",
            &input,
            Some(&search),
            &CancellationToken::new(),
            |_| Ok(()),
        )
        .await
        .unwrap();
    assert_eq!(response.text, "Supported answer");
    assert_eq!(response.citations[0].url, "https://example.org/paper");
    assert_eq!(handle.await.unwrap().len(), 3);
}

#[tokio::test]
async fn truncated_or_refused_streams_never_succeed_with_partial_text() {
    for (sse, code) in [
        (
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n",
            ErrorCode::IncompleteResponse,
        ),
        (
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":\"length\"}]}\n\ndata: [DONE]\n\n",
            ErrorCode::IncompleteResponse,
        ),
        (
            "data: {\"choices\":[{\"delta\":{\"refusal\":\"blocked\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n",
            ErrorCode::Refused,
        ),
    ] {
        let (base, handle) = server(1, move |_, _| Reply::sse(sse)).await;
        let error = AiClient::new(None, false)
            .unwrap()
            .stream(
                &config(Provider::OpenaiCompatible, base),
                "key",
                &request(),
                None,
                &CancellationToken::new(),
                |_| Ok(()),
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, code);
        handle.await.unwrap();
    }
}

#[test]
fn routes_and_model_thinking_keep_legacy_protocol_contracts() {
    let config = config(Provider::OpenaiCompatible, "https://api.x.ai/v1".into());
    assert_eq!(protocol::wire_provider(&config), Provider::Openai);
    assert_eq!(
        protocol::endpoint(&config, "models").unwrap(),
        "https://api.x.ai/v1/models"
    );
    assert!(protocol::endpoint(&super_config_with_query(), "models").is_err());
    let spec = ThinkingSpec {
        levels: vec!["high".into(), "low".into()],
        ..Default::default()
    };
    assert_eq!(spec.nearest("medium"), "low");
    for (model, level, wanted) in [
        ("gpt-5-mini", ThinkingLevel::Off, "minimal"),
        ("gpt-5.1", ThinkingLevel::Xhigh, "high"),
        ("gpt-5.2", ThinkingLevel::Xhigh, "xhigh"),
    ] {
        let config = ModelConfig {
            provider: Provider::Openai,
            base_url: "https://example.org".into(),
            model: model.into(),
            params: ModelParams {
                thinking: Some(level),
                ..Default::default()
            },
            thinking_spec: None,
            capabilities: None,
        };
        assert_eq!(
            otter_core::ai::thinking::fragment(&config, Provider::Openai)["reasoning"]["effort"],
            wanted
        );
    }
}
fn super_config_with_query() -> ModelConfig {
    config(Provider::Openai, "https://example.org?key=secret".into())
}

#[tokio::test]
async fn cancellation_drops_live_stream_and_custom_key_headers_do_not_follow_redirects() {
    use std::time::Duration;
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let live = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let _ = support::read(&mut socket).await;
        socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: 99999\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n").await.unwrap();
        let mut bytes = [0; 1];
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(2), socket.read(&mut bytes))
                .await
                .unwrap()
                .unwrap(),
            0
        );
    });
    let token = CancellationToken::new();
    let error = AiClient::new(None, false)
        .unwrap()
        .stream(
            &config(Provider::OpenaiCompatible, base),
            "key",
            &request(),
            None,
            &token,
            |event| {
                if matches!(event, ChatEvent::TextDelta { .. }) {
                    token.cancel();
                }
                Ok(())
            },
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::Cancelled);
    live.await.unwrap();

    let attacker = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let target = format!("http://{}/stolen", attacker.local_addr().unwrap());
    let (base, handle) = server(1, move |_, _| Reply {
        status: 307,
        headers: vec![("Location".into(), target.clone())],
        ..Reply::json(json!({}))
    })
    .await;
    let error = AiClient::new(None, false)
        .unwrap()
        .send(
            &config(Provider::Anthropic, base),
            "private-api-key",
            &request(),
            &CancellationToken::new(),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::Remote);
    assert_eq!(error.detail, "HTTP 307");
    assert!(
        tokio::time::timeout(Duration::from_millis(100), attacker.accept())
            .await
            .is_err()
    );
    handle.await.unwrap();
}

#[tokio::test]
async fn transient_rate_limit_retries_but_exhausted_quota_returns_stable_code() {
    let (base, handle) = server(3, |index, _| match index {
        0 => Reply {
            status: 429,
            headers: vec![("Retry-After".into(), "1".into())],
            ..Reply::json(json!({"error":{"code":"rate_limit_exceeded"}}))
        },
        1 => Reply::json(
            json!({"choices":[{"message":{"content":"Recovered"},"finish_reason":"stop"}]}),
        ),
        _ => Reply {
            status: 429,
            ..Reply::json(
                json!({"error":{"type":"insufficient_quota","message":"private account data"}}),
            )
        },
    })
    .await;
    let ai = AiClient::new(None, false).unwrap();
    let config = config(Provider::OpenaiCompatible, base);
    let token = CancellationToken::new();
    assert_eq!(
        ai.send(&config, "key", &request(), &token)
            .await
            .unwrap()
            .text,
        "Recovered"
    );
    let error = ai
        .send(&config, "key", &request(), &token)
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::QuotaExceeded);
    assert_eq!(error.detail, "HTTP 429");
    assert_eq!(handle.await.unwrap().len(), 3);
}
