use base64::{Engine, engine::general_purpose::STANDARD};
use regex::Regex;
use serde_json::{Value, json};

use crate::error::{ErrorCode, OtterError, Result};

use super::{thinking, types::*};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum OutputFormat {
    Schema,
    Json,
    Text,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SearchMode {
    None,
    Native,
    External,
    Kimi,
}

pub fn wire_provider(config: &ModelConfig) -> Provider {
    let host = reqwest::Url::parse(&config.base_url)
        .ok()
        .and_then(|u| u.host_str().map(str::to_lowercase))
        .unwrap_or_default();
    if config.provider == Provider::OpenaiCompatible && (host == "x.ai" || host.ends_with(".x.ai"))
    {
        Provider::Openai
    } else {
        config.provider
    }
}

pub fn endpoint(config: &ModelConfig, resource: &str) -> Result<String> {
    let base = config.base_url.trim().trim_end_matches('/');
    let url = reqwest::Url::parse(base)
        .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "AI base URL"))?;
    if !matches!(url.scheme(), "https" | "http")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(OtterError::new(ErrorCode::InvalidArgument, "AI base URL"));
    }
    let version = if wire_provider(config) == Provider::Gemini {
        "v1beta"
    } else {
        "v1"
    };
    let versioned = Regex::new(r"/v[\da-z.]+$").unwrap().is_match(base);
    Ok(if versioned {
        format!("{base}/{resource}")
    } else {
        format!("{base}/{version}/{resource}")
    })
}

pub(crate) fn chat_endpoint(config: &ModelConfig, stream: bool) -> Result<String> {
    let resource = match wire_provider(config) {
        Provider::Openai => "responses".into(),
        Provider::Anthropic => "messages".into(),
        Provider::OpenaiCompatible => "chat/completions".into(),
        Provider::Gemini => {
            let model = config
                .model
                .strip_prefix("models/")
                .unwrap_or(&config.model);
            if model.contains(['?', '#', ':', '\\'])
                || model
                    .split('/')
                    .any(|s| s.is_empty() || s == "." || s == "..")
            {
                return Err(OtterError::new(
                    ErrorCode::InvalidArgument,
                    "Gemini model id",
                ));
            }
            format!(
                "models/{model}:{}",
                if stream {
                    "streamGenerateContent"
                } else {
                    "generateContent"
                }
            )
        }
    };
    endpoint(config, &resource)
}

pub(crate) fn formats(provider: Provider, schema: bool) -> Vec<OutputFormat> {
    if !schema {
        return vec![OutputFormat::Text];
    }
    match provider {
        Provider::Openai => vec![OutputFormat::Schema, OutputFormat::Json],
        Provider::Anthropic => vec![OutputFormat::Schema, OutputFormat::Text],
        Provider::Gemini => vec![OutputFormat::Schema, OutputFormat::Json],
        Provider::OpenaiCompatible => {
            vec![OutputFormat::Schema, OutputFormat::Json, OutputFormat::Text]
        }
    }
}

pub(crate) fn search_mode(config: &ModelConfig, enabled: bool, external: bool) -> SearchMode {
    if !enabled {
        return SearchMode::None;
    }
    let id = config.model.to_lowercase();
    if config.capabilities.as_ref().is_some_and(|c| c.web_search)
        && matches!(
            wire_provider(config),
            Provider::Openai | Provider::Anthropic
        )
    {
        return SearchMode::Native;
    }
    match wire_provider(config) {
        Provider::Openai
            if ["gpt-4o", "gpt-4.1", "gpt-5", "o3", "o4-mini", "grok-4"]
                .iter()
                .any(|s| id.starts_with(s)) =>
        {
            SearchMode::Native
        }
        Provider::Anthropic if thinking::modern_claude(&id) => SearchMode::Native,
        Provider::Gemini if !id.starts_with("gemini-1") => SearchMode::Native,
        Provider::OpenaiCompatible => {
            let host = reqwest::Url::parse(&config.base_url)
                .ok()
                .and_then(|u| u.host_str().map(str::to_lowercase))
                .unwrap_or_default();
            if host.contains("moonshot") || host.contains("kimi") {
                SearchMode::Kimi
            } else if host.contains("dashscope")
                || host.ends_with("bigmodel.cn")
                || host.contains("xiaomimimo")
            {
                SearchMode::Native
            } else if external {
                SearchMode::External
            } else {
                SearchMode::None
            }
        }
        _ => SearchMode::None,
    }
}

pub(crate) fn native_url_context(config: &ModelConfig) -> bool {
    match wire_provider(config) {
        Provider::Anthropic => thinking::modern_claude(&config.model),
        Provider::Gemini => {
            !config.model.starts_with("gemini-1") && !config.model.starts_with("gemini-2.0")
        }
        _ => false,
    }
}

fn role(role: Role) -> &'static str {
    if role == Role::User {
        "user"
    } else {
        "assistant"
    }
}

fn image_uri(image: &ImageInput) -> String {
    format!(
        "data:{};base64,{}",
        image.mime_type,
        STANDARD.encode(&image.bytes)
    )
}

fn content(message: &Message, provider: Provider, cache: bool) -> Value {
    if message.images.is_empty()
        && matches!(provider, Provider::Openai | Provider::OpenaiCompatible)
    {
        return json!(message.text);
    }
    let mut parts = Vec::new();
    for (index, image) in message.images.iter().enumerate() {
        if let Some(label) = &image.label {
            parts.push(match provider {
                Provider::Gemini => json!({"text":label}),
                Provider::Openai => json!({"type":"input_text","text":label}),
                _ => json!({"type":"text","text":label}),
            });
        }
        let mut part = match provider {
            Provider::Openai => {
                json!({"type":"input_image","image_url":image_uri(image),"detail":"high"})
            }
            Provider::Anthropic => {
                json!({"type":"image","source":{"type":"base64","media_type":image.mime_type,"data":STANDARD.encode(&image.bytes)}})
            }
            Provider::Gemini => {
                json!({"inline_data":{"mime_type":image.mime_type,"data":STANDARD.encode(&image.bytes)}})
            }
            Provider::OpenaiCompatible => {
                json!({"type":"image_url","image_url":{"url":image_uri(image),"detail":"high"}})
            }
        };
        if cache && provider == Provider::Anthropic && index + 1 == message.images.len() {
            part["cache_control"] = json!({"type":"ephemeral"});
        }
        parts.push(part);
    }
    let mut text = match provider {
        Provider::Gemini => json!({"text":message.text}),
        Provider::Openai => {
            json!({"type":if message.role == Role::Assistant {"output_text"} else {"input_text"},"text":message.text})
        }
        _ => json!({"type":"text","text":message.text}),
    };
    if cache && provider == Provider::Anthropic {
        text["cache_control"] = json!({"type":"ephemeral"});
    }
    parts.push(text);
    json!(parts)
}

pub(crate) fn build(
    config: &ModelConfig,
    request: &ChatRequest,
    stream: bool,
    format: OutputFormat,
    search: SearchMode,
) -> Result<Value> {
    if config.model.trim().is_empty()
        || request.messages.is_empty()
        || request
            .messages
            .last()
            .is_some_and(|m| m.role != Role::User)
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "AI model/messages",
        ));
    }
    for message in &request.messages {
        if message.images.iter().any(|i| {
            !matches!(
                i.mime_type.as_str(),
                "image/png" | "image/jpeg" | "image/webp" | "image/gif"
            ) || i.bytes.is_empty()
        }) {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "AI image input",
            ));
        }
    }
    let provider = wire_provider(config);
    let params = &config.params;
    let fragment = thinking::fragment(config, provider);
    let mut body = json!({});
    if provider != Provider::Gemini {
        body["model"] = json!(config.model);
        body["stream"] = json!(stream);
    }
    let messages: Vec<Value> = request.messages.iter().enumerate().map(|(i,m)| {
        let cache = request.cache_prefix && i + 1 == request.messages.len();
        if provider == Provider::Gemini {
            json!({"role":if m.role == Role::Assistant {"model"} else {"user"},"parts":content(m,provider,false)})
        } else { json!({"role":role(m.role),"content":content(m,provider,cache)}) }
    }).collect();
    let mut generation = json!({});
    if thinking::sampling(config) {
        let names = if provider == Provider::Gemini {
            ["temperature", "topP", "topK"]
        } else {
            ["temperature", "top_p", "top_k"]
        };
        for (name, value) in names.into_iter().zip([
            params.temperature.map(|v| json!(v)),
            params.top_p.map(|v| json!(v)),
            params.top_k.map(|v| json!(v)),
        ]) {
            if let Some(value) = value {
                if value.is_null() {
                    return Err(OtterError::new(
                        ErrorCode::InvalidArgument,
                        "non-finite AI parameter",
                    ));
                }
                if name != "top_k" || provider == Provider::Anthropic {
                    generation[name] = value;
                }
            }
        }
    }
    match provider {
        Provider::Openai => {
            body["instructions"] = json!(request.system);
            body["input"] = if messages.len() == 1 && request.messages[0].images.is_empty() {
                json!(request.messages[0].text)
            } else {
                json!(messages)
            };
            if let Some(max) = params.max_tokens {
                body["max_output_tokens"] = json!(max);
            }
            if let Some(value) = params.parallel_tool_calls {
                body["parallel_tool_calls"] = json!(value);
            }
            if let Some(value) = &params.truncation {
                body["truncation"] = json!(value);
            }
            if let Some(value) = &params.verbosity {
                body["text"] = json!({"verbosity":value});
            }
            if let Some(schema) = &request.schema {
                if !body["text"].is_object() {
                    body["text"] = json!({});
                }
                body["text"]["format"] = match format {
                    OutputFormat::Schema => {
                        json!({"type":"json_schema","name":schema.name,"strict":true,"schema":schema.schema})
                    }
                    _ => json!({"type":"json_object"}),
                };
            }
            if search == SearchMode::Native {
                body["tools"] = json!([{"type":"web_search"}]);
            }
        }
        Provider::Anthropic => {
            body["system"] = if request.cache_prefix {
                json!([{"type":"text","text":request.system,"cache_control":{"type":"ephemeral"}}])
            } else {
                json!(request.system)
            };
            body["messages"] = json!(messages);
            let budget = fragment["thinking"]["budget_tokens"].as_u64().unwrap_or(0) as u32;
            let max = params.max_tokens.unwrap_or(4096);
            body["max_tokens"] = json!(if budget >= max { budget + 8192 } else { max });
            let mut tools = Vec::new();
            if search == SearchMode::Native {
                tools.push(json!({"type":"web_search_20250305","name":"web_search"}));
            }
            if request.url_context && native_url_context(config) {
                tools.push(json!({"type":"web_fetch_20250910","name":"web_fetch"}));
            }
            if !tools.is_empty() {
                body["tools"] = json!(tools);
            }
        }
        Provider::Gemini => {
            body["systemInstruction"] = json!({"parts":[{"text":request.system}]});
            body["contents"] = json!(messages);
            if let Some(max) = params.max_tokens {
                generation["maxOutputTokens"] = json!(max);
            }
            if fragment.as_object().is_some_and(|m| !m.is_empty()) {
                generation["thinkingConfig"] = fragment.clone();
            }
            if request.show_reasoning {
                if !generation["thinkingConfig"].is_object() {
                    generation["thinkingConfig"] = json!({});
                }
                generation["thinkingConfig"]["includeThoughts"] = json!(true);
            }
            if let Some(schema) = &request.schema {
                generation["responseMimeType"] = json!("application/json");
                if format == OutputFormat::Schema {
                    generation["responseJsonSchema"] = schema.schema.clone();
                }
            }
            let mut tools = Vec::new();
            if search == SearchMode::Native {
                tools.push(json!({"google_search":{}}));
            }
            if request.url_context && native_url_context(config) {
                tools.push(json!({"url_context":{}}));
            }
            if !tools.is_empty() {
                body["tools"] = json!(tools);
            }
            body["generationConfig"] = generation;
            return Ok(body);
        }
        Provider::OpenaiCompatible => {
            let mut all = vec![json!({"role":"system","content":request.system})];
            all.extend(messages);
            body["messages"] = json!(all);
            for (name, value) in [
                ("max_tokens", params.max_tokens.map(|v| json!(v))),
                (
                    "presence_penalty",
                    params.presence_penalty.map(|v| json!(v)),
                ),
                (
                    "frequency_penalty",
                    params.frequency_penalty.map(|v| json!(v)),
                ),
            ] {
                if let Some(value) = value {
                    body[name] = value;
                }
            }
            if let Some(schema) = &request.schema {
                match format {
                    OutputFormat::Schema => {
                        body["response_format"] = json!({"type":"json_schema","json_schema":{"name":schema.name,"strict":true,"schema":schema.schema}})
                    }
                    OutputFormat::Json => body["response_format"] = json!({"type":"json_object"}),
                    OutputFormat::Text => {}
                }
            }
            let host = reqwest::Url::parse(&config.base_url)
                .ok()
                .and_then(|u| u.host_str().map(str::to_lowercase))
                .unwrap_or_default();
            if host.contains("dashscope")
                && Regex::new(r"qwen[\w.-]*-vl")
                    .unwrap()
                    .is_match(&config.model.to_lowercase())
            {
                body["vl_high_resolution_images"] = json!(true);
            }
            match search {
                SearchMode::Native if host.contains("dashscope") => {
                    body["enable_search"] = json!(true)
                }
                SearchMode::Native if host.ends_with("bigmodel.cn") => {
                    body["tools"] = json!([{"type":"web_search","web_search":{"enable":true,"search_result":true}}])
                }
                SearchMode::Native => body["tools"] = json!([{"type":"web_search"}]),
                SearchMode::Kimi => {
                    body["tools"] =
                        json!([{"type":"builtin_function","function":{"name":"$web_search"}}])
                }
                SearchMode::External => {
                    body["tools"] = json!([{"type":"function","function":{"name":"web_search","description":"Search the web for current information","parameters":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}}}])
                }
                SearchMode::None => {}
            }
        }
    }
    for (key, value) in generation.as_object().unwrap() {
        body[key] = value.clone();
    }
    for (key, value) in fragment.as_object().unwrap() {
        body[key] = value.clone();
    }
    if provider == Provider::Openai
        && request.show_reasoning
        && !config.model.to_lowercase().starts_with("grok")
    {
        if !body["reasoning"].is_object() {
            body["reasoning"] = json!({});
        }
        body["reasoning"]["summary"] = json!("auto");
    }
    if provider == Provider::Anthropic
        && format == OutputFormat::Schema
        && let Some(schema) = &request.schema
    {
        if !body["output_config"].is_object() {
            body["output_config"] = json!({});
        }
        body["output_config"]["format"] = json!({"type":"json_schema","schema":schema.schema});
    }
    if search == SearchMode::Kimi {
        body["thinking"] = json!({"type":"disabled"});
        body.as_object_mut().unwrap().remove("reasoning_effort");
    }
    Ok(body)
}
