use crate::{
    error::{ErrorCode, OtterError, Result},
    storage::Storage,
};

#[derive(Clone, Copy)]
pub enum PromptKind {
    TranslationSystem,
    TranslationUser,
    ChatSystem,
    SummaryImage,
}
pub struct PromptDefinition {
    pub kind: PromptKind,
    pub storage_key: String,
    pub default_text: String,
    pub text: String,
    pub required_placeholders: Vec<String>,
    pub optional_placeholders: Vec<String>,
    pub is_default: bool,
}
fn definition(
    kind: PromptKind,
) -> (
    &'static str,
    &'static str,
    &'static [&'static str],
    &'static [&'static str],
) {
    match kind {
        PromptKind::TranslationSystem => (
            "translation_config_system_prompt",
            crate::translate::SYSTEM_PROMPT,
            &[],
            &["targetLanguage"],
        ),
        PromptKind::TranslationUser => (
            "translation_config_user_prompt",
            crate::translate::USER_PROMPT,
            &["targetLanguage", "input"],
            &[],
        ),
        PromptKind::ChatSystem => (
            "prompt_chat_system",
            crate::ai::chat::CHAT_SYSTEM,
            &["document"],
            &[],
        ),
        PromptKind::SummaryImage => (
            "image_generation_prompt",
            crate::ai::summary::DEFAULT_PROMPT,
            &[],
            &[],
        ),
    }
}
pub fn get(storage: &Storage, kind: PromptKind) -> Result<PromptDefinition> {
    let (key, default, required, optional) = definition(kind);
    let text = storage
        .setting(key)?
        .and_then(|value| {
            value
                .as_str()
                .filter(|s| !s.trim().is_empty())
                .map(str::to_owned)
        })
        .unwrap_or_else(|| default.to_owned());
    Ok(PromptDefinition {
        kind,
        storage_key: key.into(),
        default_text: default.into(),
        is_default: text.trim() == default.trim(),
        text,
        required_placeholders: required.iter().map(|s| (*s).to_owned()).collect(),
        optional_placeholders: optional.iter().map(|s| (*s).to_owned()).collect(),
    })
}
pub fn set(storage: &Storage, kind: PromptKind, text: &str) -> Result<PromptDefinition> {
    let (key, _, required, _) = definition(kind);
    if text.trim().is_empty() {
        storage.delete_setting(key)?;
    } else {
        if required
            .iter()
            .any(|name| !text.contains(&format!("{{{{{name}}}}}")))
        {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "prompt placeholder missing",
            ));
        }
        storage.put_setting(key, &serde_json::Value::String(text.into()))?;
    }
    get(storage, kind)
}
