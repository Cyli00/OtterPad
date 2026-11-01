use super::{
    Backend,
    types::{JsonData, JsonEntry},
};
use crate::{
    ai::{
        chat::{ChatMessage, ChatSession},
        types::Role,
    },
    error::Result,
};
use std::collections::BTreeMap;

pub struct Conversation {
    pub id: String,
    pub title: String,
    pub created_at: String,
    pub updated_at: String,
    pub messages: Vec<ConversationMessage>,
    pub revision: String,
    pub extra: Vec<JsonEntry>,
}
pub struct ConversationMessage {
    pub id: String,
    pub role: Role,
    pub content: String,
    pub quoted_text: Option<String>,
    pub quote_anchor: Option<JsonData>,
    pub figure_image_path: Option<String>,
    pub activities: Vec<JsonData>,
    pub url_context: Option<String>,
    pub model_id: Option<String>,
    pub created_at: String,
    pub extra: Vec<JsonEntry>,
}
pub struct Conversations {
    pub sessions: Vec<Conversation>,
    pub unreadable: Vec<String>,
}
impl Conversation {
    pub(crate) fn from_session(session: ChatSession) -> Self {
        Self {
            id: session.id,
            title: session.title,
            created_at: session.created_at,
            updated_at: session.updated_at,
            messages: session
                .messages
                .into_iter()
                .map(ConversationMessage::from_message)
                .collect(),
            revision: session.revision,
            extra: entries(session.extra),
        }
    }
    fn into_session(self) -> Result<ChatSession> {
        Ok(ChatSession {
            id: self.id,
            title: self.title,
            created_at: self.created_at,
            updated_at: self.updated_at,
            messages: self
                .messages
                .into_iter()
                .map(ConversationMessage::into_message)
                .collect::<Result<_>>()?,
            revision: self.revision,
            extra: values(self.extra)?,
        })
    }
}
impl ConversationMessage {
    pub(crate) fn from_message(message: ChatMessage) -> Self {
        Self {
            id: message.id,
            role: message.role,
            content: message.content,
            quoted_text: message.quoted_text,
            quote_anchor: message.quote_anchor.map(JsonData::from_value),
            figure_image_path: message.figure_image_path,
            activities: message
                .activities
                .into_iter()
                .map(JsonData::from_value)
                .collect(),
            url_context: message.url_context,
            model_id: message.model_id,
            created_at: message.created_at,
            extra: entries(message.extra),
        }
    }
    pub(crate) fn into_message(self) -> Result<ChatMessage> {
        Ok(ChatMessage {
            id: self.id,
            role: self.role,
            content: self.content,
            quoted_text: self.quoted_text,
            quote_anchor: self.quote_anchor.map(JsonData::into_value).transpose()?,
            figure_image_path: self.figure_image_path,
            activities: self
                .activities
                .into_iter()
                .map(JsonData::into_value)
                .collect::<Result<_>>()?,
            url_context: self.url_context,
            model_id: self.model_id,
            created_at: self.created_at,
            extra: values(self.extra)?,
        })
    }
}
fn entries(values: BTreeMap<String, serde_json::Value>) -> Vec<JsonEntry> {
    values
        .into_iter()
        .map(|(key, value)| JsonEntry {
            key,
            value: JsonData::from_value(value),
        })
        .collect()
}
fn values(entries: Vec<JsonEntry>) -> Result<BTreeMap<String, serde_json::Value>> {
    entries
        .into_iter()
        .map(|entry| Ok((entry.key, entry.value.into_value()?)))
        .collect()
}

impl Backend {
    pub async fn conversations(&self, document: String) -> Result<Conversations> {
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "conversations", move |state| {
                let list = state.chats.list(&document)?;
                Ok(Conversations {
                    sessions: list
                        .sessions
                        .into_iter()
                        .map(Conversation::from_session)
                        .collect(),
                    unreadable: list.unreadable,
                })
            })
            .await
    }
    pub async fn create_conversation(
        &self,
        document: String,
        title: String,
    ) -> Result<Conversation> {
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "create_conversation", move |state| {
                Ok(Conversation::from_session(state.chats.save(
                    &document,
                    &ChatSession::create(title)?,
                    None,
                )?))
            })
            .await
    }
    pub async fn conversation(&self, document: String, id: String) -> Result<Conversation> {
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "conversation", move |state| {
                Ok(Conversation::from_session(
                    state.chats.load(&document, &id)?,
                ))
            })
            .await
    }
    pub async fn save_conversation(
        &self,
        document: String,
        session: Conversation,
    ) -> Result<Conversation> {
        let session = session.into_session()?;
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "save_conversation", move |state| {
                Ok(Conversation::from_session(state.chats.save(
                    &document,
                    &session,
                    Some(&session.revision),
                )?))
            })
            .await
    }
    pub async fn delete_conversation(&self, document: String, id: String) -> Result<()> {
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "delete_conversation", move |state| {
                state.chats.delete(&document, &id)
            })
            .await
    }
}
