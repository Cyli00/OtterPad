use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Provider {
    Openai,
    Anthropic,
    Gemini,
    OpenaiCompatible,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThinkingLevel {
    Off,
    Low,
    Medium,
    High,
    Xhigh,
}

impl ThinkingLevel {
    pub fn effort(self) -> &'static str {
        match self {
            Self::Off => "none",
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
            Self::Xhigh => "xhigh",
        }
    }

    pub fn budget(self) -> u32 {
        match self {
            Self::Off => 0,
            Self::Low => 1024,
            Self::Medium => 4096,
            Self::High => 16384,
            Self::Xhigh => 32000,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThinkingSpec {
    pub adaptive: Option<bool>,
    pub always_on: Option<bool>,
    pub sampling: Option<bool>,
    #[serde(default)]
    pub levels: Vec<String>,
    #[serde(rename = "default")]
    pub default_level: Option<String>,
}

impl ThinkingSpec {
    pub fn nearest(&self, want: &str) -> String {
        const ORDER: [&str; 7] = ["none", "minimal", "low", "medium", "high", "xhigh", "max"];
        let target = ORDER.iter().position(|s| *s == want).unwrap_or(0);
        self.levels
            .iter()
            .filter_map(|s| ORDER.iter().position(|v| v == s).map(|i| (i, s)))
            .min_by_key(|(i, _)| (i.abs_diff(target), *i))
            .map(|(_, s)| s.clone())
            .unwrap_or_else(|| want.into())
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ModelParams {
    pub temperature: Option<f64>,
    pub top_p: Option<f64>,
    pub max_tokens: Option<u32>,
    pub top_k: Option<u32>,
    pub thinking: Option<ThinkingLevel>,
    pub verbosity: Option<String>,
    pub parallel_tool_calls: Option<bool>,
    pub truncation: Option<String>,
    pub presence_penalty: Option<f64>,
    pub frequency_penalty: Option<f64>,
}

/// Credentials are injected separately and never serialized with configuration or history.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelConfig {
    pub provider: Provider,
    pub base_url: String,
    pub model: String,
    #[serde(default)]
    pub params: ModelParams,
    pub thinking_spec: Option<ThinkingSpec>,
    #[serde(default)]
    pub capabilities: Option<super::catalog::ModelCapabilities>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    User,
    Assistant,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageInput {
    pub mime_type: String,
    pub bytes: Vec<u8>,
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: Role,
    pub text: String,
    #[serde(default)]
    pub images: Vec<ImageInput>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonSchema {
    pub name: String,
    pub schema: Value,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChatRequest {
    pub system: String,
    pub messages: Vec<Message>,
    pub schema: Option<JsonSchema>,
    pub web_search: bool,
    pub url_context: bool,
    pub show_reasoning: bool,
    pub cache_prefix: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Citation {
    pub url: String,
    pub title: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Usage {
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ChatEvent {
    TextDelta { text: String },
    ReasoningDelta { text: String },
    Tool { name: String },
    Citation { source: Citation },
    Usage { usage: Usage },
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChatResponse {
    pub text: String,
    pub reasoning: String,
    pub citations: Vec<Citation>,
    pub usage: Usage,
    pub request_id: Option<String>,
    pub context: Vec<super::search::UrlContext>,
}
