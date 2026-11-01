use std::{
    collections::{BTreeMap, HashSet},
    path::{Path, PathBuf},
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use tokio_util::sync::CancellationToken;

use super::{AiClient, protocol, search::SearchService, types::*};
use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
    tasks::check,
};

pub const CHAT_SYSTEM: &str = "You are a research assistant embedded in a document reader. The user is reading the academic document below and will ask questions about it.\n\n## Rules\n1. Prefer document content and cite the section or figure you used. For questions about this document's own findings, methods, or numbers, if the document does not provide an answer, say so explicitly — never present general knowledge as the document's conclusion.\n2. Definitions, background, and general concepts may be answered from general knowledge — mark those parts as general knowledge rather than document content.\n3. Answer in the same language the user asks in.\n4. Use Markdown formatting; write math as LaTeX in $...$ / $$...$$.\n\n## Document\n{{document}}";
const GUIDANCE: &str = "优先帮助用户理解文献并保持专注。先直接回答当前问题，再用连贯段落解释依据、机制与意义；每段围绕一个主题，承接上文，避免孤立短句、碎片化结论和无关扩展。每个主题只加粗少量真正关键的概念或结论，避免整段强调、重复小标题或堆砌术语分散注意力。只有步骤或并列信息适合时才使用列表，最多两层，禁止第三层及更深的嵌套；其余用完整段落。新概念先作简短解释，再联系本文证据，必要时给一个贴切例子。明确区分文献事实、推断和不确定性；不得为便于学习而编造证据。按用户问题决定详略，不强塞练习或延伸话题。用户明确指定的输出格式优先。\n";
const TITLE_SYSTEM: &str = "Summarize the user message into a very short conversation title in the same language as the message: at most 12 characters for CJK or 6 words for English. Output the title only — no quotes, no trailing punctuation, no explanation.";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessage {
    pub id: String,
    pub role: Role,
    #[serde(default)]
    pub content: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quoted_text: Option<String>,
    /// Kept verbatim so an unresolvable 0.1.x reader anchor is never discarded.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quote_anchor: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub figure_image_path: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub activities: Vec<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url_context: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model_id: Option<String>,
    pub created_at: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl ChatMessage {
    pub fn user(content: String) -> Result<Self> {
        Ok(Self {
            id: new_id(),
            role: Role::User,
            content,
            quoted_text: None,
            quote_anchor: None,
            figure_image_path: None,
            activities: Vec::new(),
            url_context: None,
            model_id: None,
            created_at: now()?,
            extra: BTreeMap::new(),
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSession {
    pub id: String,
    #[serde(default)]
    pub title: String,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub messages: Vec<ChatMessage>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
    #[serde(skip)]
    pub revision: String,
}

impl ChatSession {
    pub fn create(title: String) -> Result<Self> {
        let now = now()?;
        Ok(Self {
            id: new_id(),
            title,
            created_at: now.clone(),
            updated_at: now,
            messages: Vec::new(),
            extra: BTreeMap::new(),
            revision: String::new(),
        })
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionList {
    pub sessions: Vec<ChatSession>,
    pub unreadable: Vec<String>,
}

/// A single store owns session mutations; saves are atomic and compare the caller's revision.
pub struct ChatStore {
    directory: PathBuf,
    writes: Mutex<()>,
    active: Mutex<HashSet<(String, String)>>,
}

struct Active<'a> {
    store: &'a ChatStore,
    key: (String, String),
}
impl Drop for Active<'_> {
    fn drop(&mut self) {
        if let Ok(mut active) = self.store.active.lock() {
            active.remove(&self.key);
        }
    }
}

impl ChatStore {
    pub fn new(directory: PathBuf) -> Self {
        Self {
            directory,
            writes: Mutex::new(()),
            active: Mutex::new(HashSet::new()),
        }
    }

    fn document(&self, document: &str) -> Result<PathBuf> {
        let path = self
            .directory
            .join("library")
            .join(files::component(document)?);
        if !path.is_dir() {
            return Err(OtterError::new(
                ErrorCode::NotFound,
                "chat document missing",
            ));
        }
        Ok(path)
    }

    fn path(&self, document: &str, id: &str) -> Result<PathBuf> {
        Ok(self
            .document(document)?
            .join("chats")
            .join(format!("{}.json", files::component(id)?)))
    }

    pub fn load(&self, document: &str, id: &str) -> Result<ChatSession> {
        let bytes = std::fs::read(self.path(document, id)?)?;
        let mut session: ChatSession = serde_json::from_slice(&bytes)?;
        session.revision = crate::document::revision(&String::from_utf8_lossy(&bytes));
        validate(&session)?;
        if session.id != id {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "session identity mismatch",
            ));
        }
        Ok(session)
    }

    pub fn list(&self, document: &str) -> Result<SessionList> {
        let path = self.document(document)?.join("chats");
        let mut list = SessionList {
            sessions: Vec::new(),
            unreadable: Vec::new(),
        };
        if !path.exists() {
            return Ok(list);
        }
        for entry in std::fs::read_dir(path)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() || entry.path().extension().is_none_or(|e| e != "json")
            {
                continue;
            }
            let id = entry
                .path()
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .into_owned();
            match self.load(document, &id) {
                Ok(session) => list.sessions.push(session),
                Err(_) => list.unreadable.push(id),
            }
        }
        list.sessions.sort_by(|a, b| {
            timestamp(&b.updated_at)
                .cmp(&timestamp(&a.updated_at))
                .then_with(|| a.id.cmp(&b.id))
        });
        list.unreadable.sort();
        Ok(list)
    }

    pub fn save(
        &self,
        document: &str,
        session: &ChatSession,
        expected_revision: Option<&str>,
    ) -> Result<ChatSession> {
        validate(session)?;
        let _lock = self
            .writes
            .lock()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "session write lock"))?;
        let path = self.path(document, &session.id)?;
        if path.exists() {
            let existing = self.load(document, &session.id)?;
            if expected_revision != Some(existing.revision.as_str()) {
                return Err(OtterError::new(
                    ErrorCode::Conflict,
                    "session revision changed",
                ));
            }
        } else if expected_revision.is_some() {
            return Err(OtterError::new(ErrorCode::Conflict, "session removed"));
        }
        let mut next = session.clone();
        next.updated_at = now()?;
        let bytes = serde_json::to_vec(&next)?;
        files::atomic_write(&path, &bytes)?;
        next.revision = crate::document::revision(&String::from_utf8_lossy(&bytes));
        Ok(next)
    }

    pub fn delete(&self, document: &str, id: &str) -> Result<()> {
        let _lock = self
            .writes
            .lock()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "session write lock"))?;
        let path = self.path(document, id)?;
        if path.exists() {
            std::fs::remove_file(path)?;
        }
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub fn build_request(
        &self,
        document: &str,
        history: &[ChatMessage],
        current: &ChatMessage,
        system_template: &str,
        config: &ModelConfig,
        fast: bool,
        web_search: bool,
    ) -> Result<ChatRequest> {
        if current.role != Role::User || !system_template.contains("{{document}}") {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "chat user/system prompt",
            ));
        }
        let directory = self.document(document)?;
        let markdown = read_markdown(&directory)?;
        let send_images = !fast && config.capabilities.as_ref().is_some_and(|c| c.image_input);
        let explicit = current.figure_image_path.is_some()
            || history.iter().any(|m| m.figure_image_path.is_some());
        let figures = if send_images && !explicit {
            load_figures(&directory, None, None)?
        } else {
            Vec::new()
        };
        let first = history
            .iter()
            .position(|m| m.role == Role::User)
            .unwrap_or(history.len());
        let mut messages = Vec::new();
        for (index, message) in history.iter().chain(std::iter::once(current)).enumerate() {
            let images = if send_images && message.role == Role::User {
                if let Some(path) = &message.figure_image_path {
                    load_figures(&directory, Some(path), message.quoted_text.as_deref())?
                } else if index == first {
                    figures.clone()
                } else {
                    Vec::new()
                }
            } else {
                Vec::new()
            };
            messages.push(Message {
                role: message.role,
                text: if message.role == Role::User {
                    compose_user_text(
                        &message.content,
                        message.quoted_text.as_deref(),
                        message.url_context.as_deref(),
                    )
                } else {
                    message.content.clone()
                },
                images,
            });
        }
        let urls = history.iter().chain(std::iter::once(current)).any(|m| {
            m.role == Role::User
                && (m.content.contains("https://") || m.content.contains("http://"))
        });
        Ok(ChatRequest {
            system: format!(
                "{GUIDANCE}{}",
                system_template.replace("{{document}}", &markdown)
            ),
            messages,
            web_search,
            url_context: urls,
            show_reasoning: config.capabilities.as_ref().is_some_and(|c| c.reasoning),
            cache_prefix: true,
            ..Default::default()
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn ask(
        &self,
        document: &str,
        session_id: &str,
        mut current: ChatMessage,
        system_template: &str,
        config: &ModelConfig,
        key: &str,
        fast: bool,
        web_search: bool,
        stream: bool,
        ai: &AiClient,
        search: Option<&SearchService>,
        token: &CancellationToken,
        emit: impl FnMut(ChatEvent) -> Result<()>,
    ) -> Result<ChatSession> {
        check(token)?;
        let key_pair = (document.to_owned(), session_id.to_owned());
        {
            let mut active = self
                .active
                .lock()
                .map_err(|_| OtterError::new(ErrorCode::Conflict, "chat task lock"))?;
            if !active.insert(key_pair.clone()) {
                return Err(OtterError::new(
                    ErrorCode::Conflict,
                    "session already generating",
                ));
            }
        }
        let _active = Active {
            store: self,
            key: key_pair,
        };
        let mut session = self.load(document, session_id)?;
        let retry = session
            .messages
            .last()
            .is_some_and(|m| m.id == current.id && m.role == Role::User);
        if !retry && session.messages.iter().any(|m| m.id == current.id) {
            return Err(OtterError::new(ErrorCode::Conflict, "duplicate message id"));
        }
        let history = if retry {
            &session.messages[..session.messages.len() - 1]
        } else {
            session.messages.as_slice()
        };
        let request = self.build_request(
            document,
            history,
            &current,
            system_template,
            config,
            fast,
            web_search,
        )?;
        if !retry {
            let revision = session.revision.clone();
            session.messages.push(current.clone());
            session = self.save(document, &session, Some(&revision))?;
        }
        let mut config = config.clone();
        if protocol::wire_provider(&config) == Provider::Anthropic
            && config.params.max_tokens.is_none()
        {
            config.params.max_tokens = Some(if stream { 32000 } else { 8192 });
        }
        let answer = if stream {
            ai.stream(&config, key, &request, search, token, emit)
                .await?
        } else {
            ai.send_with_search(&config, key, &request, search, token)
                .await?
        };
        check(token)?;
        if !answer.context.is_empty() {
            current.url_context = Some(format!(
                "<url_context>\n{}\n</url_context>",
                serde_json::to_string(&answer.context)?
            ));
        }
        let mut assistant = ChatMessage::user(answer.text)?;
        assistant.role = Role::Assistant;
        assistant.model_id = Some(config.model);
        if !answer.reasoning.is_empty() {
            assistant
                .extra
                .insert("reasoning".into(), Value::String(answer.reasoning));
        }
        if !answer.citations.is_empty() {
            assistant
                .extra
                .insert("citations".into(), serde_json::to_value(answer.citations)?);
        }
        let previous = session.revision.clone();
        *session.messages.last_mut().unwrap() = current;
        session.messages.push(assistant);
        self.save(document, &session, Some(&previous))
    }
}

pub fn now() -> Result<String> {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "timestamp formatting"))
}
fn timestamp(value: &str) -> i128 {
    OffsetDateTime::parse(value, &Rfc3339)
        .or_else(|_| OffsetDateTime::parse(&format!("{value}Z"), &Rfc3339))
        .map(|v| v.unix_timestamp_nanos())
        .unwrap_or(i128::MIN)
}
fn validate(session: &ChatSession) -> Result<()> {
    files::component(&session.id)?;
    if timestamp(&session.created_at) == i128::MIN
        || timestamp(&session.updated_at) == i128::MIN
        || session
            .messages
            .iter()
            .any(|m| m.id.is_empty() || timestamp(&m.created_at) == i128::MIN)
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "session timestamps/message ids",
        ));
    }
    Ok(())
}
static IDS: AtomicU64 = AtomicU64::new(0);
pub(crate) fn new_id() -> String {
    format!(
        "{:x}-{:x}",
        OffsetDateTime::now_utc().unix_timestamp_nanos(),
        IDS.fetch_add(1, Ordering::Relaxed)
    )
}

mod context;
pub use context::compose_user_text;
pub(crate) use context::{load_figures, read_markdown};
