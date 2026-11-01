pub mod paragraph;
pub mod protected;

use std::{
    collections::{BTreeMap, HashMap},
    path::{Path, PathBuf},
    sync::{Arc, LazyLock, Mutex, Weak},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use futures_util::{StreamExt, stream::FuturesUnordered};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex as AsyncMutex, Semaphore};
use tokio_util::sync::CancellationToken;

use crate::{
    ai::{
        AiClient,
        types::{ChatEvent, ChatRequest, Message, ModelConfig, Role, ThinkingLevel},
    },
    document::revision,
    error::{ErrorCode, OtterError, Result},
    files,
    tasks::{cancellable, check},
};
use paragraph::Paragraph;
use protected::Protected;

pub const SYSTEM_PROMPT: &str = "You are a professional {{targetLanguage}} native translator who needs to fluently translate text into {{targetLanguage}}.\n\n## Translation Rules\n1. Output only the translated content, without explanations or additional content.\n2. Preserve the original structure exactly: the same number of paragraphs, and the same Markdown formatting (headings, lists, emphasis, LaTeX).\n3. Keep content that should not be translated as-is: code, formulas, URLs, technical identifiers.\n4. Translate names and terminology into their established {{targetLanguage}} rendering when one exists; otherwise keep the original.";
pub const USER_PROMPT: &str = "Translate to {{targetLanguage}}:\n\n{{input}}";
const PLACEHOLDER_GUARD: &str = "The input contains placeholders like [[m0]], [[m1]] that stand for protected content (formulas or code). Keep every placeholder exactly as-is at its corresponding position in the translation. Never translate, alter, merge, or drop a placeholder.";
const SEGMENT_GUARD: &str = "The input is divided into independent segments by lines containing only \"%%%%\". Translate every segment in place and reproduce the separator lines in the same order and count. Never merge or split segments, never add or remove separators. Use neighbouring segments only for terminology and tone consistency.";
const TTL: u64 = 7 * 86400;
static PERMITS: LazyLock<Arc<Semaphore>> = LazyLock::new(|| Arc::new(Semaphore::new(8)));
type FileLocks = Mutex<HashMap<PathBuf, Weak<AsyncMutex<()>>>>;
static FILE_LOCKS: LazyLock<FileLocks> = LazyLock::new(|| Mutex::new(HashMap::new()));

fn file_lock(path: &Path) -> Result<Arc<AsyncMutex<()>>> {
    let mut locks = FILE_LOCKS
        .lock()
        .map_err(|_| OtterError::new(ErrorCode::Conflict, "translation file lock"))?;
    locks.retain(|_, v| v.strong_count() > 0);
    if let Some(lock) = locks.get(path).and_then(Weak::upgrade) {
        return Ok(lock);
    }
    let lock = Arc::new(AsyncMutex::new(()));
    locks.insert(path.into(), Arc::downgrade(&lock));
    Ok(lock)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranslationConfig {
    pub language: String,
    pub system_prompt: String,
    pub user_prompt: String,
    pub temperature: Option<f64>,
    pub thinking: Option<ThinkingLevel>,
}

impl TranslationConfig {
    pub fn new(language: String) -> Self {
        Self {
            language,
            system_prompt: SYSTEM_PROMPT.into(),
            user_prompt: USER_PROMPT.into(),
            temperature: None,
            thinking: Some(ThinkingLevel::Off),
        }
    }
}

#[derive(Clone)]
pub struct Translator {
    ai: AiClient,
    directory: PathBuf,
}

#[derive(Serialize, Deserialize)]
struct SelectionCache {
    created_at: u64,
    text: String,
}

type Layers = BTreeMap<String, BTreeMap<String, String>>;

impl Translator {
    pub fn new(ai: AiClient, directory: PathBuf) -> Self {
        Self { ai, directory }
    }

    fn request(&self, text: &str, config: &TranslationConfig) -> Result<(Protected, ChatRequest)> {
        if config.language.trim().is_empty()
            || !config.user_prompt.contains("{{targetLanguage}}")
            || !config.user_prompt.contains("{{input}}")
        {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "translation prompt placeholders/language",
            ));
        }
        let protected = Protected::mask(text);
        let mut system = config
            .system_prompt
            .replace("{{targetLanguage}}", &config.language);
        if !protected.is_empty() {
            system.push('\n');
            system.push_str(PLACEHOLDER_GUARD);
        }
        if text.contains("%%%%") {
            system.push('\n');
            system.push_str(SEGMENT_GUARD);
        }
        let prompt = config
            .user_prompt
            .replace("{{targetLanguage}}", &config.language)
            .replace("{{input}}", &protected.masked);
        Ok((
            protected,
            ChatRequest {
                system,
                messages: vec![Message {
                    role: Role::User,
                    text: prompt,
                    images: Vec::new(),
                }],
                ..Default::default()
            },
        ))
    }

    fn model(&self, model: &ModelConfig, config: &TranslationConfig) -> ModelConfig {
        let mut model = model.clone();
        if config.thinking.is_some() {
            model.params.thinking = config.thinking;
        }
        if config.temperature.is_some() {
            model.params.temperature = config.temperature;
        }
        model
    }

    fn cache_path(
        &self,
        text: &str,
        model: &ModelConfig,
        config: &TranslationConfig,
    ) -> Result<PathBuf> {
        let key = serde_json::to_string(&(text, model, config))?;
        Ok(self
            .directory
            .join("cache/translation")
            .join(format!("{}.json", revision(&key))))
    }

    fn cached(&self, path: &Path) -> Result<Option<String>> {
        if !path.is_file() {
            return Ok(None);
        }
        let value: SelectionCache = serde_json::from_slice(&std::fs::read(path)?)?;
        let now = epoch()?;
        if value.created_at <= now && now - value.created_at < TTL {
            Ok(Some(value.text))
        } else {
            std::fs::remove_file(path)?;
            Ok(None)
        }
    }

    pub async fn selection(
        &self,
        text: &str,
        model: &ModelConfig,
        key: &str,
        config: &TranslationConfig,
        use_cache: bool,
        token: &CancellationToken,
    ) -> Result<String> {
        check(token)?;
        if text.trim().is_empty() {
            return Ok(String::new());
        }
        let model = self.model(model, config);
        let path = self.cache_path(text, &model, config)?;
        if use_cache && let Some(text) = self.cached(&path)? {
            return Ok(text);
        }
        let (protected, request) = self.request(text, config)?;
        let response = self.ai.send(&model, key, &request, token).await?;
        let result = restore(&protected, text, &response.text)?;
        check(token)?;
        files::write_json(
            &path,
            &SelectionCache {
                created_at: epoch()?,
                text: result.clone(),
            },
        )?;
        Ok(result)
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn selection_stream(
        &self,
        text: &str,
        model: &ModelConfig,
        key: &str,
        config: &TranslationConfig,
        use_cache: bool,
        token: &CancellationToken,
        mut snapshot: impl FnMut(String) -> Result<()>,
    ) -> Result<String> {
        check(token)?;
        if text.trim().is_empty() {
            snapshot(String::new())?;
            return Ok(String::new());
        }
        let model = self.model(model, config);
        let path = self.cache_path(text, &model, config)?;
        if use_cache && let Some(text) = self.cached(&path)? {
            snapshot(text.clone())?;
            return Ok(text);
        }
        let (protected, request) = self.request(text, config)?;
        let mut partial = String::new();
        let mut callback_error = None;
        let response = self
            .ai
            .stream(&model, key, &request, None, token, |event| {
                if let ChatEvent::TextDelta { text } = event {
                    partial.push_str(&text);
                    let result = protected.restore(&partial, false).and_then(&mut snapshot);
                    if let Err(error) = result {
                        callback_error = Some(error.clone());
                        return Err(error);
                    }
                }
                Ok(())
            })
            .await;
        if let Some(error) = callback_error {
            return Err(error);
        }
        let result = match response {
            Ok(response) => restore(&protected, text, &response.text),
            Err(error) => Err(error),
        };
        match result {
            Ok(text) => {
                check(token)?;
                files::write_json(
                    &path,
                    &SelectionCache {
                        created_at: epoch()?,
                        text: text.clone(),
                    },
                )?;
                snapshot(text.clone())?;
                Ok(text)
            }
            Err(error)
                if matches!(
                    error.code,
                    ErrorCode::Cancelled
                        | ErrorCode::Authentication
                        | ErrorCode::QuotaExceeded
                        | ErrorCode::Refused
                ) =>
            {
                Err(error)
            }
            Err(_) => {
                let text = self
                    .selection(text, &model, key, config, false, token)
                    .await?;
                snapshot(text.clone())?;
                Ok(text)
            }
        }
    }

    fn translations_path(&self, document: &str) -> Result<PathBuf> {
        Ok(self
            .directory
            .join("library")
            .join(files::component(document)?)
            .join("translations.json"))
    }

    pub async fn load(&self, document: &str, language: &str) -> Result<BTreeMap<String, String>> {
        let path = self.translations_path(document)?;
        let lock = file_lock(&path)?;
        let _guard = lock.lock().await;
        Ok(read_layers(&path)?.remove(language).unwrap_or_default())
    }

    pub async fn save(
        &self,
        document: &str,
        language: &str,
        values: &BTreeMap<String, String>,
    ) -> Result<()> {
        let path = self.translations_path(document)?;
        let lock = file_lock(&path)?;
        let _guard = lock.lock().await;
        let mut root = read_layers(&path)?;
        root.entry(language.into())
            .or_default()
            .extend(values.clone());
        files::write_json(&path, &root)
    }

    pub async fn clear(&self, document: &str, language: &str) -> Result<()> {
        let path = self.translations_path(document)?;
        let lock = file_lock(&path)?;
        let _guard = lock.lock().await;
        if !path.exists() {
            return Ok(());
        }
        let mut root = read_layers(&path)?;
        root.remove(language);
        if root.is_empty() {
            std::fs::remove_file(path)?;
            Ok(())
        } else {
            files::write_json(&path, &root)
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum TranslationEvent {
    Result { hash: String, text: String },
    Progress { completed: usize, total: usize },
    Failure { hash: String, code: ErrorCode },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranslationFailure {
    pub hash: String,
    pub code: ErrorCode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranslationReport {
    pub completed: usize,
    pub total: usize,
    pub cached: usize,
    pub failures: Vec<TranslationFailure>,
}

fn read_layers(path: &Path) -> Result<Layers> {
    if path.exists() {
        Ok(serde_json::from_slice(&std::fs::read(path)?)?)
    } else {
        Ok(BTreeMap::new())
    }
}

fn epoch() -> Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|v| v.as_secs())
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "system clock"))
}

fn restore(protected: &Protected, source: &str, text: &str) -> Result<String> {
    let result = protected.restore(text, true)?;
    let separators = |s: &str| s.lines().filter(|line| line.trim() == "%%%%").count();
    if separators(source) != separators(&result)
        || ['⟪', '⟫']
            .iter()
            .any(|marker| source.matches(*marker).count() != result.matches(*marker).count())
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "translation segment/selection markers changed",
        ));
    }
    Ok(result)
}

fn retryable(error: &OtterError) -> bool {
    matches!(
        error.code,
        ErrorCode::Network | ErrorCode::RateLimited | ErrorCode::IncompleteResponse
    ) || (error.code == ErrorCode::Remote
        && matches!(
            error.detail.as_str(),
            "HTTP 500" | "HTTP 502" | "HTTP 503" | "HTTP 529"
        ))
}

mod document;
