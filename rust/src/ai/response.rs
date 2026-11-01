use std::collections::BTreeMap;

use serde_json::{Value, json};

use crate::error::{ErrorCode, OtterError, Result};

use super::{sse::SseEvent, types::*};

#[derive(Debug, Default)]
pub(crate) struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

pub(crate) struct Accumulator {
    pub result: ChatResponse,
    pub calls: BTreeMap<usize, ToolCall>,
    pub terminal: bool,
    pub finish_reason: Option<String>,
    provider: Provider,
}

impl Accumulator {
    pub fn new(provider: Provider) -> Self {
        Self {
            result: ChatResponse::default(),
            calls: BTreeMap::new(),
            terminal: false,
            finish_reason: None,
            provider,
        }
    }

    fn text(
        &mut self,
        text: &str,
        thought: bool,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        if text.is_empty() {
            return Ok(());
        }
        if self.result.text.len() + self.result.reasoning.len() + text.len() > 32 * 1024 * 1024 {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "AI response exceeds limit",
            ));
        }
        if thought {
            self.result.reasoning.push_str(text);
            emit(ChatEvent::ReasoningDelta { text: text.into() })
        } else {
            self.result.text.push_str(text);
            emit(ChatEvent::TextDelta { text: text.into() })
        }
    }

    fn citation(
        &mut self,
        value: &Value,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        let source = value.get("url_citation").unwrap_or(value);
        let url = source["url"].as_str().or_else(|| source["uri"].as_str());
        if let Some(url) = url
            && reqwest::Url::parse(url).is_ok_and(|u| matches!(u.scheme(), "http" | "https"))
            && !self.result.citations.iter().any(|c| c.url == url)
        {
            let source = Citation {
                url: url.into(),
                title: source["title"].as_str().unwrap_or("").into(),
            };
            self.result.citations.push(source.clone());
            emit(ChatEvent::Citation { source })?;
        }
        Ok(())
    }

    fn usage(
        &mut self,
        value: &Value,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        if !value.is_object() {
            return Ok(());
        }
        let input = value["input_tokens"]
            .as_u64()
            .or_else(|| value["prompt_tokens"].as_u64())
            .or_else(|| value["promptTokenCount"].as_u64());
        let output = value["output_tokens"]
            .as_u64()
            .or_else(|| value["completion_tokens"].as_u64())
            .or_else(|| value["candidatesTokenCount"].as_u64());
        if input.is_some() {
            self.result.usage.input_tokens = input;
        }
        if output.is_some() {
            self.result.usage.output_tokens = output;
        }
        emit(ChatEvent::Usage {
            usage: self.result.usage.clone(),
        })
    }

    fn finish(&mut self, reason: &str) -> Result<()> {
        match reason {
            "length" | "max_tokens" | "MAX_TOKENS" => {
                return Err(OtterError::new(
                    ErrorCode::IncompleteResponse,
                    "AI token limit",
                ));
            }
            "refusal" | "content_filter" | "SAFETY" | "RECITATION" | "BLOCKLIST"
            | "PROHIBITED_CONTENT" | "IMAGE_SAFETY" => {
                return Err(OtterError::new(ErrorCode::Refused, "AI response blocked"));
            }
            "insufficient_system_resource" | "ERROR" | "OTHER" => {
                return Err(OtterError::new(ErrorCode::Remote, "AI generation failed"));
            }
            _ => {}
        }
        self.finish_reason = Some(reason.into());
        Ok(())
    }

    fn compat(
        &mut self,
        value: &Value,
        stream: bool,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        if let Some(choice) = value["choices"].as_array().and_then(|a| a.first()) {
            let message = &choice[if stream { "delta" } else { "message" }];
            if message["refusal"].as_str().is_some_and(|s| !s.is_empty()) {
                return Err(OtterError::new(ErrorCode::Refused, "AI refusal"));
            }
            if let Some(text) = message["content"].as_str() {
                self.text(text, false, emit)?;
            }
            if let Some(text) = message["reasoning_content"].as_str() {
                self.text(text, true, emit)?;
            }
            if let Some(calls) = message["tool_calls"].as_array() {
                for (i, call) in calls.iter().enumerate() {
                    let index = call["index"].as_u64().unwrap_or(i as u64) as usize;
                    if index > 31 {
                        return Err(OtterError::new(ErrorCode::ToolLimit, "tool call count"));
                    }
                    let slot = self.calls.entry(index).or_default();
                    if let Some(id) = call["id"].as_str() {
                        slot.id.push_str(id);
                    }
                    if let Some(name) = call["function"]["name"].as_str() {
                        slot.name.push_str(name);
                    }
                    if let Some(args) = call["function"]["arguments"].as_str() {
                        if slot.arguments.len() + args.len() > 64 * 1024 {
                            return Err(OtterError::new(
                                ErrorCode::ToolLimit,
                                "tool arguments size",
                            ));
                        }
                        slot.arguments.push_str(args);
                    }
                }
            }
            if let Some(reason) = choice["finish_reason"].as_str() {
                self.finish(reason)?;
            }
        }
        self.usage(&value["usage"], emit)
    }

    fn gemini(
        &mut self,
        value: &Value,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        if value["promptFeedback"]["blockReason"].is_string() {
            return Err(OtterError::new(ErrorCode::Refused, "Gemini prompt blocked"));
        }
        if let Some(candidate) = value["candidates"].as_array().and_then(|a| a.first()) {
            if let Some(parts) = candidate["content"]["parts"].as_array() {
                for part in parts {
                    if let Some(text) = part["text"].as_str() {
                        self.text(text, part["thought"] == true, emit)?;
                    }
                }
            }
            if let Some(chunks) = candidate["groundingMetadata"]["groundingChunks"].as_array() {
                for chunk in chunks {
                    self.citation(&chunk["web"], emit)?;
                }
            }
            if let Some(reason) = candidate["finishReason"].as_str() {
                self.finish(reason)?;
                self.terminal = true;
            }
        }
        self.usage(&value["usageMetadata"], emit)
    }

    fn openai_output(
        &mut self,
        value: &Value,
        text: bool,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        if value["status"] == "incomplete" {
            return Err(OtterError::new(
                ErrorCode::IncompleteResponse,
                "Responses incomplete",
            ));
        }
        if value["status"] == "failed" || value["error"].is_object() {
            return Err(OtterError::new(ErrorCode::Remote, "Responses failed"));
        }
        if let Some(output) = value["output"].as_array() {
            for item in output {
                if item["type"] == "message"
                    && let Some(content) = item["content"].as_array()
                {
                    for part in content {
                        if part["type"] == "refusal" {
                            return Err(OtterError::new(ErrorCode::Refused, "Responses refusal"));
                        }
                        if text
                            && part["type"] == "output_text"
                            && let Some(t) = part["text"].as_str()
                        {
                            self.text(t, false, emit)?;
                        }
                        if let Some(annotations) = part["annotations"].as_array() {
                            for a in annotations {
                                self.citation(a, emit)?;
                            }
                        }
                    }
                }
            }
        }
        self.usage(&value["usage"], emit)
    }

    pub fn event(
        &mut self,
        event: SseEvent,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        if event.data == "[DONE]" {
            if self.provider == Provider::OpenaiCompatible
                || (self.provider == Provider::Openai && self.finish_reason.is_some())
            {
                self.terminal = true;
            }
            return Ok(());
        }
        let value: Value = serde_json::from_str(&event.data)?;
        if value["error"].is_object() || value["type"] == "error" || event.event == "error" {
            return Err(OtterError::new(ErrorCode::Remote, "AI stream error"));
        }
        match self.provider {
            Provider::Openai => {
                let kind = value["type"].as_str().unwrap_or(&event.event);
                match kind {
                    "response.output_text.delta" => {
                        self.text(value["delta"].as_str().unwrap_or(""), false, emit)?
                    }
                    "response.reasoning_summary_text.delta" | "response.reasoning_text.delta" => {
                        self.text(value["delta"].as_str().unwrap_or(""), true, emit)?
                    }
                    "response.output_text.annotation.added" => {
                        self.citation(&value["annotation"], emit)?
                    }
                    "response.completed" => {
                        self.openai_output(&value["response"], self.result.text.is_empty(), emit)?;
                        self.terminal = true;
                    }
                    "response.failed" => {
                        return Err(OtterError::new(ErrorCode::Remote, "Responses failed"));
                    }
                    "response.incomplete" => {
                        return Err(OtterError::new(
                            ErrorCode::IncompleteResponse,
                            "Responses incomplete",
                        ));
                    }
                    "response.refusal.delta" => {
                        return Err(OtterError::new(ErrorCode::Refused, "Responses refusal"));
                    }
                    _ if kind.contains("web_search_call") || kind.contains("web_fetch_call") => {
                        emit(ChatEvent::Tool { name: kind.into() })?
                    }
                    _ if value["choices"].is_array() => self.compat(&value, true, emit)?,
                    _ => {}
                }
            }
            Provider::Anthropic => {
                let kind = value["type"].as_str().unwrap_or(&event.event);
                match kind {
                    "content_block_delta" => {
                        let delta = &value["delta"];
                        match delta["type"].as_str() {
                            Some("text_delta") => {
                                self.text(delta["text"].as_str().unwrap_or(""), false, emit)?
                            }
                            Some("thinking_delta") => {
                                self.text(delta["thinking"].as_str().unwrap_or(""), true, emit)?
                            }
                            Some("citations_delta") => self.citation(&delta["citation"], emit)?,
                            _ => {}
                        }
                    }
                    "content_block_start"
                        if value["content_block"]["type"] == "server_tool_use" =>
                    {
                        emit(ChatEvent::Tool {
                            name: value["content_block"]["name"].as_str().unwrap_or("").into(),
                        })?
                    }
                    "message_start" => self.usage(&value["message"]["usage"], emit)?,
                    "message_delta" => {
                        if let Some(reason) = value["delta"]["stop_reason"].as_str() {
                            self.finish(reason)?;
                        }
                        self.usage(&value["usage"], emit)?;
                    }
                    "message_stop" => self.terminal = true,
                    _ => {}
                }
            }
            Provider::Gemini => self.gemini(&value, emit)?,
            Provider::OpenaiCompatible => self.compat(&value, true, emit)?,
        }
        Ok(())
    }

    pub fn complete_json(
        &mut self,
        value: Value,
        emit: &mut impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<()> {
        if value["error"].is_object() {
            return Err(OtterError::new(ErrorCode::Remote, "AI error response"));
        }
        match self.provider {
            Provider::Openai => {
                if value["output"].is_array() {
                    self.openai_output(&value, true, emit)?;
                } else {
                    self.compat(&value, false, emit)?;
                }
            }
            Provider::Anthropic => {
                if let Some(reason) = value["stop_reason"].as_str() {
                    self.finish(reason)?;
                }
                if let Some(content) = value["content"].as_array() {
                    for part in content {
                        match part["type"].as_str() {
                            Some("text") => {
                                self.text(part["text"].as_str().unwrap_or(""), false, emit)?;
                                if let Some(citations) = part["citations"].as_array() {
                                    for a in citations {
                                        self.citation(a, emit)?;
                                    }
                                }
                            }
                            Some("thinking") => {
                                self.text(part["thinking"].as_str().unwrap_or(""), true, emit)?
                            }
                            _ => {}
                        }
                    }
                }
                self.usage(&value["usage"], emit)?;
            }
            Provider::Gemini => self.gemini(&value, emit)?,
            Provider::OpenaiCompatible => self.compat(&value, false, emit)?,
        }
        self.terminal = true;
        self.validate()
    }

    pub fn validate(&self) -> Result<()> {
        if !self.terminal {
            return Err(OtterError::new(
                ErrorCode::IncompleteResponse,
                "AI stream missing completion",
            ));
        }
        if !self.calls.is_empty() && self.finish_reason.as_deref() != Some("tool_calls") {
            return Err(OtterError::new(
                ErrorCode::IncompleteResponse,
                "AI tool call missing completion",
            ));
        }
        if self.result.text.trim().is_empty() && self.calls.is_empty() {
            return Err(OtterError::new(
                ErrorCode::IncompleteResponse,
                "AI empty output",
            ));
        }
        Ok(())
    }

    pub fn assistant_tool_message(&self) -> Value {
        json!({"role":"assistant","content":if self.result.text.is_empty() {Value::Null} else {json!(self.result.text)},"tool_calls":self.calls.values().map(|c|json!({"id":c.id,"type":"function","function":{"name":c.name,"arguments":c.arguments}})).collect::<Vec<_>>()})
    }
}
