use super::{
    Backend,
    chat::{Conversation, ConversationMessage},
    network_settings,
    types::JsonData,
};
use crate::{
    ai::{
        AiClient,
        catalog::{CAPABILITIES_URL, CapabilityCatalog, ModelInfo},
        chat::CHAT_SYSTEM,
        search::{SearchProvider, SearchService},
        types::{ChatEvent, ChatRequest, ChatResponse, JsonSchema, Message, ModelConfig},
    },
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    tasks::cancellable,
};

pub struct ModelSelection {
    pub instance_id: String,
    pub config: ModelConfig,
}
pub struct GenerationSchema {
    pub name: String,
    pub json: JsonData,
}
pub struct GenerationRequest {
    pub system: String,
    pub messages: Vec<Message>,
    pub schema: Option<GenerationSchema>,
    pub web_search: bool,
    pub url_context: bool,
    pub show_reasoning: bool,
    pub cache_prefix: bool,
}
pub enum GenerationEvent {
    Failed { error: OtterError },
    Delta { event: ChatEvent },
    Completed { response: ChatResponse },
}
pub struct AskDocument {
    pub document_id: String,
    pub session_id: String,
    pub message: ConversationMessage,
    pub model: ModelSelection,
    pub system_prompt: Option<String>,
    pub fast: bool,
    pub web_search: bool,
    pub stream: bool,
    pub search_provider: Option<SearchProvider>,
}
pub enum ConversationEvent {
    Failed { error: OtterError },
    Delta { event: ChatEvent },
    Saved { conversation: Conversation },
}

#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct AiContext {
    pub ai: AiClient,
    pub model: ModelConfig,
    pub key: String,
    pub proxy: Option<String>,
    pub http2: bool,
}
pub(crate) async fn context(
    backend: &Backend,
    selection: ModelSelection,
    token: &tokio_util::sync::CancellationToken,
) -> Result<AiContext> {
    crate::files::component(&selection.instance_id)?;
    let key = backend
        .runtime
        .credentials
        .get(&format!("agent_api_key_{}", selection.instance_id))?;
    let (model, proxy, http2) = backend
        .runtime
        .call(token, "configure_model", move |state| {
            let mut model = selection.config;
            CapabilityCatalog::open(state.storage()?.directory())?.configure(&mut model);
            let (proxy, http2) = network_settings(state.storage()?)?;
            Ok((model, proxy, http2))
        })
        .await?;
    Ok(AiContext {
        ai: AiClient::new(proxy.as_deref(), http2)?,
        model,
        key,
        proxy,
        http2,
    })
}
fn search(
    backend: &Backend,
    context: &AiContext,
    provider: Option<SearchProvider>,
) -> Result<Option<SearchService>> {
    provider
        .map(|provider| {
            let vault_key = match provider {
                SearchProvider::Tavily => "tavily_api_key",
                SearchProvider::Exa => "exa_search_api_key",
                SearchProvider::Brave => "brave_search_api_key",
            };
            SearchService::new(
                context.proxy.as_deref(),
                context.http2,
                provider,
                backend.runtime.credentials.get(vault_key)?,
            )
        })
        .transpose()
}
impl Backend {
    pub async fn generate_text(
        &self,
        model: ModelSelection,
        request: GenerationRequest,
        provider: Option<SearchProvider>,
        task_id: String,
        sink: StreamSink<GenerationEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let context = context(self, model, &task.token).await?;
            let search = search(self, &context, provider)?;
            let request = ChatRequest {
                system: request.system,
                messages: request.messages,
                schema: request
                    .schema
                    .map(|schema| -> Result<JsonSchema> {
                        Ok(JsonSchema {
                            name: schema.name,
                            schema: schema.json.into_value()?,
                        })
                    })
                    .transpose()?,
                web_search: request.web_search,
                url_context: request.url_context,
                show_reasoning: request.show_reasoning,
                cache_prefix: request.cache_prefix,
            };
            let response = context
                .ai
                .stream(
                    &context.model,
                    &context.key,
                    &request,
                    search.as_ref(),
                    &task.token,
                    |event| sink.add(GenerationEvent::Delta { event }).map_err(closed),
                )
                .await?;
            sink.add(GenerationEvent::Completed { response })
                .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(GenerationEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn ask_document(
        &self,
        options: AskDocument,
        task_id: String,
        sink: StreamSink<ConversationEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let context = context(self, options.model, &task.token).await?;
            let search = search(self, &context, options.search_provider)?;
            let chats = self
                .runtime
                .call(&task.token, "chat_store", |state| Ok(state.chats.clone()))
                .await?;
            let conversation = chats
                .ask(
                    &options.document_id,
                    &options.session_id,
                    options.message.into_message()?,
                    options.system_prompt.as_deref().unwrap_or(CHAT_SYSTEM),
                    &context.model,
                    &context.key,
                    options.fast,
                    options.web_search,
                    options.stream,
                    &context.ai,
                    search.as_ref(),
                    &task.token,
                    |event| sink.add(ConversationEvent::Delta { event }).map_err(closed),
                )
                .await?;
            sink.add(ConversationEvent::Saved {
                conversation: Conversation::from_session(conversation),
            })
            .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(ConversationEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn models(
        &self,
        selection: ModelSelection,
        task_id: String,
    ) -> Result<Vec<ModelInfo>> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let context = context(self, selection, &task.token).await?;
        let catalog = CapabilityCatalog::open(&self.runtime.directory)?;
        context
            .ai
            .models(&context.model, &context.key, Some(&catalog), &task.token)
            .await
    }
    pub async fn refresh_model_capabilities(&self, force: bool, task_id: String) -> Result<bool> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let (proxy, http2) = self
            .runtime
            .call(&task.token, "network_settings", |state| {
                network_settings(state.storage()?)
            })
            .await?;
        let mut catalog = CapabilityCatalog::open(&self.runtime.directory)?;
        catalog
            .refresh(
                &crate::network::client(proxy.as_deref(), http2)?,
                CAPABILITIES_URL,
                force,
                &task.token,
            )
            .await
    }
}
fn closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "AI stream closed")
}
