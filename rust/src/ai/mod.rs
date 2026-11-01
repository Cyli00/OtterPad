pub mod catalog;
pub mod chat;
pub mod image;
pub mod protocol;
mod response;
pub mod search;
mod sse;
pub mod summary;
pub mod thinking;
pub mod types;

use std::time::Duration;

use futures_util::StreamExt;
use reqwest::{Client, RequestBuilder, Response};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use crate::{
    error::{ErrorCode, OtterError, Result},
    network,
    tasks::{cancellable, check},
};
use protocol::{SearchMode, wire_provider};
use response::Accumulator;
use search::SearchService;
use types::*;

#[derive(Clone)]
pub struct AiClient {
    client: Client,
    context_client: Client,
}

impl AiClient {
    pub fn new(proxy: Option<&str>, http2: bool) -> Result<Self> {
        Ok(Self {
            client: network::api_client(proxy, http2)?,
            context_client: network::client(proxy, http2)?,
        })
    }

    pub(crate) fn authorize(
        &self,
        request: RequestBuilder,
        provider: Provider,
        key: &str,
    ) -> RequestBuilder {
        match provider {
            Provider::Anthropic => request
                .header("x-api-key", key)
                .header("anthropic-version", "2023-06-01"),
            Provider::Gemini => request.header("x-goog-api-key", key),
            _ => request.bearer_auth(key),
        }
    }

    async fn post(
        &self,
        config: &ModelConfig,
        key: &str,
        body: &Value,
        stream: bool,
        token: &CancellationToken,
    ) -> Result<Response> {
        let provider = wire_provider(config);
        let url = protocol::chat_endpoint(config, stream)?;
        for attempt in 0..2 {
            check(token)?;
            let mut request = self
                .authorize(self.client.post(&url), provider, key)
                .json(body);
            if provider == Provider::Gemini && stream {
                request = request.query(&[("alt", "sse")]);
            }
            let response = cancellable(token, async { Ok(request.send().await?) }).await;
            let retry_after = response
                .as_ref()
                .ok()
                .and_then(|r| r.headers().get("retry-after"))
                .and_then(|h| h.to_str().ok())
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(2)
                .clamp(1, 30);
            let response = match response {
                Ok(response) => network::api_response(response, token).await,
                Err(error) => Err(error),
            };
            let transient = response.as_ref().is_err_and(|e| {
                matches!(e.code, ErrorCode::Network | ErrorCode::RateLimited)
                    || (e.code == ErrorCode::Remote
                        && matches!(
                            e.detail.as_str(),
                            "HTTP 500" | "HTTP 502" | "HTTP 503" | "HTTP 529"
                        ))
            });
            if transient && attempt == 0 {
                cancellable(token, async {
                    tokio::time::sleep(Duration::from_secs(retry_after)).await;
                    Ok(())
                })
                .await?;
                continue;
            }
            return response;
        }
        unreachable!()
    }

    async fn round(
        &self,
        config: &ModelConfig,
        key: &str,
        body: &Value,
        stream: bool,
        token: &CancellationToken,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<Accumulator> {
        let response = self.post(config, key, body, stream, token).await?;
        let mut accumulator = Accumulator::new(wire_provider(config));
        accumulator.result.request_id = ["x-request-id", "request-id", "x-goog-request-id"]
            .iter()
            .find_map(|name| {
                response
                    .headers()
                    .get(*name)
                    .and_then(|h| h.to_str().ok())
                    .map(str::to_owned)
            });
        let sse = response
            .headers()
            .get("content-type")
            .and_then(|h| h.to_str().ok())
            .is_some_and(|h| h.starts_with("text/event-stream"));
        if stream && sse {
            let mut decoder = sse::Decoder::default();
            let mut bytes = response.bytes_stream();
            while let Some(chunk) =
                cancellable(token, async { Ok(bytes.next().await.transpose()?) }).await?
            {
                for event in decoder.push(&chunk)? {
                    check(token)?;
                    accumulator.event(event, emit)?;
                }
            }
            decoder.finish()?;
            accumulator.validate()?;
        } else {
            let bytes = network::bytes(response, 32 * 1024 * 1024, token).await?;
            accumulator.complete_json(serde_json::from_slice(&bytes)?, emit)?;
        }
        Ok(accumulator)
    }

    pub async fn send(
        &self,
        config: &ModelConfig,
        key: &str,
        request: &ChatRequest,
        token: &CancellationToken,
    ) -> Result<ChatResponse> {
        self.run(config, key, request, false, None, token, |_| Ok(()))
            .await
    }

    /// Emits deltas for this call; cancellation drops the live HTTP body immediately.
    pub async fn stream(
        &self,
        config: &ModelConfig,
        key: &str,
        request: &ChatRequest,
        search: Option<&SearchService>,
        token: &CancellationToken,
        emit: impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<ChatResponse> {
        self.run(config, key, request, true, search, token, emit)
            .await
    }

    pub async fn send_with_search(
        &self,
        config: &ModelConfig,
        key: &str,
        request: &ChatRequest,
        search: Option<&SearchService>,
        token: &CancellationToken,
    ) -> Result<ChatResponse> {
        self.run(config, key, request, false, search, token, |_| Ok(()))
            .await
    }

    #[allow(clippy::too_many_arguments)]
    async fn run(
        &self,
        config: &ModelConfig,
        key: &str,
        request: &ChatRequest,
        stream: bool,
        search: Option<&SearchService>,
        token: &CancellationToken,
        mut emit: impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<ChatResponse> {
        check(token)?;
        if key.trim().is_empty() {
            return Err(OtterError::new(ErrorCode::Authentication, "AI key missing"));
        }
        let provider = wire_provider(config);
        let mode = protocol::search_mode(config, request.web_search, search.is_some());
        let mut request = request.clone();
        let context = if request.url_context && !protocol::native_url_context(config) {
            let text = request
                .messages
                .last()
                .map(|m| m.text.as_str())
                .unwrap_or("");
            search::fetch_context(&self.context_client, text, token).await?
        } else {
            Vec::new()
        };
        if !context.is_empty()
            && let Some(message) = request.messages.last_mut()
        {
            message.text.push_str("\n\n<url_context>\n");
            message.text.push_str(&serde_json::to_string(&context)?);
            message.text.push_str("\n</url_context>");
        }
        let mut result = ChatResponse {
            context,
            ..Default::default()
        };
        for format in protocol::formats(provider, request.schema.is_some()) {
            let mut body = protocol::build(config, &request, stream, format, mode)?;
            if format == protocol::OutputFormat::Text
                && let Some(schema) = &request.schema
            {
                let guard = format!(
                    "\nReturn JSON only, matching this schema:\n{}",
                    schema.schema
                );
                match provider {
                    Provider::Anthropic if body["system"].is_array() => {
                        let text =
                            body["system"][0]["text"].as_str().unwrap_or("").to_owned() + &guard;
                        body["system"][0]["text"] = json!(text);
                    }
                    Provider::Anthropic => body["system"] = json!(request.system.clone() + &guard),
                    Provider::OpenaiCompatible => {
                        body["messages"][0]["content"] = json!(request.system.clone() + &guard)
                    }
                    _ => {}
                }
            }
            let mut unsupported_format = false;
            for round in 0..=3 {
                let accumulator = match self
                    .round(config, key, &body, stream, token, &mut emit)
                    .await
                {
                    Err(e)
                        if round == 0
                            && request.schema.is_some()
                            && matches!(e.detail.as_str(), "HTTP 400" | "HTTP 422") =>
                    {
                        unsupported_format = true;
                        break;
                    }
                    other => other?,
                };
                let assistant = accumulator.assistant_tool_message();
                let calls = accumulator.calls;
                merge(&mut result, accumulator.result);
                if calls.is_empty() {
                    check(token)?;
                    if request.schema.is_some() {
                        let _: Value = serde_json::from_str(result.text.trim())?;
                    }
                    return Ok(result);
                }
                if round == 3 {
                    return Err(OtterError::new(ErrorCode::ToolLimit, "search round limit"));
                }
                if provider != Provider::OpenaiCompatible
                    || !matches!(mode, SearchMode::External | SearchMode::Kimi)
                {
                    return Err(OtterError::new(
                        ErrorCode::Unsupported,
                        "unsupported AI tool call",
                    ));
                }
                let messages = body["messages"]
                    .as_array_mut()
                    .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "tool history"))?;
                messages.push(assistant);
                for call in calls.values() {
                    if call.id.is_empty()
                        || !matches!(
                            (mode, call.name.as_str()),
                            (SearchMode::External, "web_search")
                                | (SearchMode::Kimi, "$web_search")
                        )
                    {
                        return Err(OtterError::new(
                            ErrorCode::Unsupported,
                            "unexpected AI tool",
                        ));
                    }
                    emit(ChatEvent::Tool {
                        name: call.name.clone(),
                    })?;
                    let content = if mode == SearchMode::Kimi {
                        call.arguments.clone()
                    } else {
                        let args: Value = serde_json::from_str(&call.arguments)?;
                        let query = args["query"].as_str().ok_or_else(|| {
                            OtterError::new(ErrorCode::InvalidData, "search query missing")
                        })?;
                        match search
                            .ok_or_else(|| {
                                OtterError::new(
                                    ErrorCode::InvalidArgument,
                                    "search service missing",
                                )
                            })?
                            .search(query, token)
                            .await
                        {
                            Ok(entries) => {
                                for entry in &entries {
                                    if !result.citations.iter().any(|s| s.url == entry.url) {
                                        let source = Citation {
                                            url: entry.url.clone(),
                                            title: entry.title.clone(),
                                        };
                                        emit(ChatEvent::Citation {
                                            source: source.clone(),
                                        })?;
                                        result.citations.push(source);
                                    }
                                }
                                serde_json::to_string(&entries)?
                            }
                            Err(e) if e.code == ErrorCode::Cancelled => return Err(e),
                            Err(e) => json!({"error_code":format!("{:?}",e.code)}).to_string(),
                        }
                    };
                    messages.push(json!({"role":"tool","tool_call_id":call.id,"name":call.name,"content":content}));
                }
            }
            if !unsupported_format {
                break;
            }
        }
        Err(OtterError::new(
            ErrorCode::Unsupported,
            "structured output formats rejected",
        ))
    }
}

fn merge(target: &mut ChatResponse, source: ChatResponse) {
    target.text.push_str(&source.text);
    target.reasoning.push_str(&source.reasoning);
    for citation in source.citations {
        if !target.citations.iter().any(|c| c.url == citation.url) {
            target.citations.push(citation);
        }
    }
    target.usage.input_tokens = add_tokens(target.usage.input_tokens, source.usage.input_tokens);
    target.usage.output_tokens = add_tokens(target.usage.output_tokens, source.usage.output_tokens);
    target.request_id = source.request_id;
}

fn add_tokens(a: Option<u64>, b: Option<u64>) -> Option<u64> {
    match (a, b) {
        (None, None) => None,
        _ => Some(a.unwrap_or(0).saturating_add(b.unwrap_or(0))),
    }
}
