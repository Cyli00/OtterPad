use regex::Regex;
use serde_json::{Value, json};

use super::types::{ModelConfig, Provider, ThinkingLevel};

pub fn claude_adaptive(model: &str) -> bool {
    Regex::new(r"claude-(?:opus-4-[789]|(?:opus|sonnet|haiku)-[5-9]|fable|mythos)(?:\b|-)")
        .unwrap()
        .is_match(&model.to_lowercase())
}

pub fn modern_claude(model: &str) -> bool {
    let id = model.to_lowercase();
    [
        "claude-opus-4",
        "claude-sonnet-4",
        "claude-haiku-4",
        "claude-opus-5",
        "claude-sonnet-5",
        "claude-fable",
        "claude-mythos",
        "claude-3-7",
        "claude-3-5-haiku",
    ]
    .iter()
    .any(|prefix| id.starts_with(prefix))
}

pub fn sampling(config: &ModelConfig) -> bool {
    config
        .thinking_spec
        .as_ref()
        .and_then(|s| s.sampling)
        .unwrap_or_else(|| {
            !(config.provider == Provider::Anthropic && claude_adaptive(&config.model))
        })
}

pub fn fragment(config: &ModelConfig, provider: Provider) -> Value {
    let Some(level) = config.params.thinking else {
        return json!({});
    };
    let id = config.model.to_lowercase();
    let spec = config.thinking_spec.as_ref();
    let nearest = |want: &str| spec.map(|s| s.nearest(want)).unwrap_or_else(|| want.into());
    match provider {
        Provider::Openai => {
            if id.starts_with("grok") {
                return json!({});
            }
            let mut effort = level.effort().to_string();
            if spec.is_some_and(|s| !s.levels.is_empty()) {
                effort = nearest(&effort);
            } else if let Some(m) = Regex::new(r"(?:^|[/-])gpt-5(?:\.(\d+))?(?:[.-]|$)")
                .unwrap()
                .captures(&id)
            {
                let minor = m
                    .get(1)
                    .and_then(|m| m.as_str().parse::<u32>().ok())
                    .unwrap_or(0);
                if minor == 0 && level == ThinkingLevel::Off {
                    effort = "minimal".into();
                }
                if minor <= 1 && level == ThinkingLevel::Xhigh {
                    effort = "high".into();
                }
            }
            json!({"reasoning": {"effort": effort}})
        }
        Provider::Anthropic => {
            if spec
                .and_then(|s| s.adaptive)
                .unwrap_or_else(|| claude_adaptive(&id))
            {
                let effort = if level == ThinkingLevel::Off {
                    "low"
                } else {
                    level.effort()
                };
                json!({"thinking":{"type":"adaptive"},"output_config":{"effort":nearest(effort)}})
            } else if level == ThinkingLevel::Off {
                json!({"thinking":{"type":"disabled"}})
            } else {
                json!({"thinking":{"type":"enabled","budget_tokens":level.budget()}})
            }
        }
        Provider::Gemini => {
            if Regex::new(r"(?:^|[/-])gemini-3(?:[.-]|$)")
                .unwrap()
                .is_match(&id)
            {
                let value = match level {
                    ThinkingLevel::Off => {
                        if id.contains("pro") {
                            "low"
                        } else {
                            "minimal"
                        }
                    }
                    ThinkingLevel::Low => "low",
                    ThinkingLevel::Medium => {
                        if id.contains("gemini-3-pro") {
                            "high"
                        } else {
                            "medium"
                        }
                    }
                    ThinkingLevel::High | ThinkingLevel::Xhigh => "high",
                };
                json!({"thinkingLevel":value})
            } else if Regex::new(r"(?:^|[/-])gemini-2\.5(?:[.-]|$)")
                .unwrap()
                .is_match(&id)
            {
                let pro = id.contains("gemini-2.5-pro");
                let budget = match level {
                    ThinkingLevel::Off => {
                        if pro {
                            128
                        } else {
                            0
                        }
                    }
                    ThinkingLevel::Low => 512,
                    ThinkingLevel::Medium => 4096,
                    ThinkingLevel::High => 16384,
                    ThinkingLevel::Xhigh => {
                        if pro {
                            32768
                        } else {
                            24576
                        }
                    }
                };
                json!({"thinkingBudget":budget})
            } else {
                json!({})
            }
        }
        Provider::OpenaiCompatible => {
            if level == ThinkingLevel::Off {
                json!({"thinking":{"type":"disabled"}})
            } else {
                json!({"thinking":{"type":"enabled"},"reasoning_effort":level.effort()})
            }
        }
    }
}
