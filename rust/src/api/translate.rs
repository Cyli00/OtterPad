use super::{
    Backend,
    ai::{ModelSelection, context},
    document::directory,
};
use crate::{
    ai::{
        AiClient,
        image::{ImageRequest, ImageResponse},
        summary::{SummaryConfig, SummaryService},
        types::Provider,
    },
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    tasks::cancellable,
    translate::{TranslationConfig, TranslationEvent, TranslationReport, Translator, paragraph},
};

pub struct TranslateSelection {
    pub text: String,
    pub model: ModelSelection,
    pub config: TranslationConfig,
    pub use_cache: bool,
}
pub struct TranslateDocument {
    pub document_id: String,
    pub model: ModelSelection,
    pub config: TranslationConfig,
    pub ignored_sections: Vec<String>,
    pub use_cache: bool,
}
pub struct TranslationValue {
    pub hash: String,
    pub text: String,
}
pub enum TranslateEvent {
    Failed { error: OtterError },
    Snapshot { text: String },
    Paragraph { event: TranslationEvent },
    Completed { report: TranslationReport },
}
pub struct SummaryImage {
    pub image_path: String,
    pub metadata_path: String,
    pub mime_type: String,
    pub reference_image_count: u64,
}

impl Backend {
    pub async fn translate_selection(
        &self,
        options: TranslateSelection,
        task_id: String,
        sink: StreamSink<TranslateEvent>,
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
            let translator = Translator::new(context.ai, self.runtime.directory.clone());
            translator
                .selection_stream(
                    &options.text,
                    &context.model,
                    &context.key,
                    &options.config,
                    options.use_cache,
                    &task.token,
                    |text| sink.add(TranslateEvent::Snapshot { text }).map_err(closed),
                )
                .await?;
            Ok(())
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(TranslateEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn translate_document(
        &self,
        options: TranslateDocument,
        task_id: String,
        sink: StreamSink<TranslateEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let _lease = cancellable(&task.token, async {
                Ok(self.runtime.operations.read().await)
            })
            .await?;
            let document_id = options.document_id.clone();
            let paragraphs = self
                .runtime
                .call(&task.token, "translation_paragraphs", move |state| {
                    let directory = directory(state.storage()?, &document_id)?;
                    let markdown = crate::ai::chat::read_markdown(&directory)?;
                    Ok(paragraph::extract(
                        &markdown,
                        &options.ignored_sections.into_iter().collect(),
                    ))
                })
                .await?;
            let context = context(self, options.model, &task.token).await?;
            let translator = Translator::new(context.ai, self.runtime.directory.clone());
            let report = translator
                .document(
                    &options.document_id,
                    &paragraphs,
                    &context.model,
                    &context.key,
                    &options.config,
                    options.use_cache,
                    &task.token,
                    |event| {
                        sink.add(TranslateEvent::Paragraph { event })
                            .map_err(closed)
                    },
                )
                .await?;
            sink.add(TranslateEvent::Completed { report })
                .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(TranslateEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn translations(
        &self,
        document: String,
        language: String,
    ) -> Result<Vec<TranslationValue>> {
        let _lease = self.runtime.operations.read().await;
        let check_document = document.clone();
        self.runtime
            .call(&Default::default(), "translations", move |state| {
                directory(state.storage()?, &check_document)
            })
            .await?;
        let translator =
            Translator::new(AiClient::new(None, true)?, self.runtime.directory.clone());
        Ok(translator
            .load(&document, &language)
            .await?
            .into_iter()
            .map(|(hash, text)| TranslationValue { hash, text })
            .collect())
    }
    pub async fn clear_translations(&self, document: String, language: String) -> Result<()> {
        let _lease = self.runtime.operations.read().await;
        Translator::new(AiClient::new(None, true)?, self.runtime.directory.clone())
            .clear(&document, &language)
            .await
    }
    pub async fn generate_image(
        &self,
        model: ModelSelection,
        request: ImageRequest,
        task_id: String,
    ) -> Result<ImageResponse> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let context = context(self, model, &task.token).await?;
        context
            .ai
            .generate_image(&context.model, &context.key, &request, &task.token)
            .await
    }
    pub async fn summary_prompt(
        &self,
        document: String,
        config: SummaryConfig,
        provider: Provider,
    ) -> Result<String> {
        self.runtime
            .with_storage(&Default::default(), "summary_prompt", move |storage| {
                let document = storage.document(&document)?.ok_or_else(|| {
                    OtterError::new(ErrorCode::NotFound, "summary document missing")
                })?;
                SummaryService::new(storage.directory().to_owned())
                    .compose(&document, &config, provider)
            })
            .await
    }
    pub async fn generate_summary(
        &self,
        document: String,
        model: ModelSelection,
        config: SummaryConfig,
        task_id: String,
    ) -> Result<SummaryImage> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let document =
            self.runtime
                .call(&task.token, "summary_document", move |state| {
                    state.storage()?.document(&document)?.ok_or_else(|| {
                        OtterError::new(ErrorCode::NotFound, "summary document missing")
                    })
                })
                .await?;
        let context = context(self, model, &task.token).await?;
        let capabilities = context.model.capabilities.as_ref().ok_or_else(|| {
            OtterError::new(
                ErrorCode::InvalidArgument,
                "summary model capabilities missing",
            )
        })?;
        let result = SummaryService::new(self.runtime.directory.clone())
            .generate(
                &document,
                &config,
                &context.model,
                &context.key,
                capabilities,
                &context.ai,
                &task.token,
            )
            .await?;
        Ok(SummaryImage {
            image_path: result.image_path.to_string_lossy().into_owned(),
            metadata_path: result.metadata_path.to_string_lossy().into_owned(),
            mime_type: result.mime_type,
            reference_image_count: result.reference_image_count as u64,
        })
    }
}
fn closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "translation stream closed")
}
