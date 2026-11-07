use super::{Backend, document::directory, network_settings};
use crate::ocr::usage::ExtractionUsage;
use crate::{
    error::{ErrorCode, OtterError, Result},
    frb_generated::StreamSink,
    ocr::{self, MineruOptions, OcrClient, OcrStage, PaddleOptions, Progress},
    sync::archive,
    tasks::cancellable,
};

#[derive(Clone)]
pub enum ExtractionProvider {
    PaddleJob {
        job_url: String,
        options: PaddleOptions,
    },
    Paddle {
        url: String,
        options: PaddleOptions,
    },
    Mineru {
        base_url: String,
        options: MineruOptions,
    },
}
pub enum ExtractionEvent {
    Failed {
        error: OtterError,
    },
    Progress {
        progress: Progress,
    },
    Published {
        document_id: String,
        generation: String,
    },
}
pub enum ExtractionBatchEvent {
    Failed {
        error: OtterError,
    },
    Document {
        document_id: String,
        event: ExtractionEvent,
    },
    Completed {
        succeeded: u32,
        failed: u32,
        cancelled: u32,
    },
}
impl Backend {
    pub async fn extract_documents(
        &self,
        documents: Vec<String>,
        provider: ExtractionProvider,
        task_id: String,
        sink: StreamSink<ExtractionBatchEvent>,
    ) -> Result<()> {
        use futures_util::{StreamExt, stream};
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            if documents.len() > 100
                || documents
                    .iter()
                    .collect::<std::collections::HashSet<_>>()
                    .len()
                    != documents.len()
            {
                return Err(OtterError::new(
                    ErrorCode::InvalidArgument,
                    "OCR batch count or duplicate ID",
                ));
            }
            let task = self.runtime.tasks.begin(task_id)?;
            let total = documents.len() as u32;
            let jobs = stream::iter(documents)
                .map(|document| {
                    let provider = provider.clone();
                    let token = task.token.clone();
                    let event_id = document.clone();
                    let event_sink = sink.clone();
                    let emit: Emitter = std::sync::Arc::new(move |event| {
                        event_sink
                            .add(ExtractionBatchEvent::Document {
                                document_id: event_id.clone(),
                                event,
                            })
                            .map_err(closed)
                    });
                    async move {
                        let result =
                            extract_one(self, document.clone(), provider, token, emit).await;
                        (document, result)
                    }
                })
                .buffer_unordered(4);
            tokio::pin!(jobs);
            let (mut succeeded, mut failed) = (0, 0);
            while let Some((document_id, result)) = jobs.next().await {
                match result {
                    Ok(()) => succeeded += 1,
                    Err(error) if error.code == ErrorCode::Cancelled => {}
                    Err(error) => {
                        failed += 1;
                        sink.add(ExtractionBatchEvent::Document {
                            document_id,
                            event: ExtractionEvent::Failed { error },
                        })
                        .map_err(closed)?;
                    }
                }
            }
            sink.add(ExtractionBatchEvent::Completed {
                succeeded,
                failed,
                cancelled: total - succeeded - failed,
            })
            .map_err(closed)
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(ExtractionBatchEvent::Failed { error });
        }
        Ok(())
    }
    pub async fn extraction_usage(&self) -> Result<ExtractionUsage> {
        self.runtime
            .with_storage(&Default::default(), "extraction_usage", ocr::usage::today)
            .await
    }
    pub async fn extract_document(
        &self,
        document: String,
        provider: ExtractionProvider,
        task_id: String,
        sink: StreamSink<ExtractionEvent>,
    ) -> Result<()> {
        let sink = std::sync::Arc::new(sink);
        let failure_sink = sink.clone();
        let result: Result<()> = async move {
            let task = self.runtime.tasks.begin(task_id)?;
            let emit: Emitter = std::sync::Arc::new(move |event| sink.add(event).map_err(closed));
            extract_one(self, document, provider, task.token.clone(), emit).await
        }
        .await;
        if let Err(error) = result {
            let _ = failure_sink.add(ExtractionEvent::Failed { error });
        }
        Ok(())
    }
}
type Emitter = std::sync::Arc<dyn Fn(ExtractionEvent) -> Result<()> + Send + Sync>;
async fn extract_one(
    backend: &Backend,
    document: String,
    provider: ExtractionProvider,
    task_token: tokio_util::sync::CancellationToken,
    emit: Emitter,
) -> Result<()> {
    let _lease = cancellable(&task_token, async {
        Ok(backend.runtime.operations.read().await)
    })
    .await?;
    let input_id = document.clone();
    let token = task_token.clone();
    let (pdf, expected, proxy, http2, pages) = backend
        .runtime
        .call(&task_token, "prepare_ocr", move |state| {
            let pdf = directory(state.storage()?, &input_id)?.join("source.pdf");
            let hash = archive::hash_file(&pdf, &token)?;
            let (proxy, http2) = network_settings(state.storage()?)?;
            // 页数决定长 PDF 是否按页段提交；读不出时整份提交，由服务商判定。
            let pages = state.pdf().ok().and_then(|pdf_state| {
                let info = pdf_state.open(&pdf, None, &token).ok()?;
                let count = info.pages.len();
                let _ = pdf_state.close(info.handle);
                Some(count)
            });
            Ok((pdf, hash, proxy, http2, pages))
        })
        .await?;
    let client = OcrClient::with_clients(
        crate::network::api_client(proxy.as_deref(), http2)?,
        crate::network::client(proxy.as_deref(), http2)?,
    );
    let mut output = match provider {
        ExtractionProvider::PaddleJob { job_url, options } => {
            client
                .paddle_job(
                    &pdf,
                    &job_url,
                    &backend.runtime.credentials.get("doc_extract_api_key")?,
                    &options,
                    pages,
                    &task_token,
                    |progress| {
                        if emit(ExtractionEvent::Progress { progress }).is_err() {
                            task_token.cancel();
                        }
                    },
                )
                .await?
        }
        ExtractionProvider::Paddle { url, options } => {
            emit(ExtractionEvent::Progress {
                progress: Progress {
                    stage: OcrStage::Running,
                    done: 0,
                    total: 1,
                },
            })
            .map_err(closed)?;
            client
                .paddle(
                    &pdf,
                    &url,
                    &backend.runtime.credentials.get("doc_extract_api_key")?,
                    &options,
                    &task_token,
                )
                .await?
        }
        ExtractionProvider::Mineru { base_url, options } => {
            client
                .mineru_document(
                    &base_url,
                    &backend
                        .runtime
                        .credentials
                        .get("doc_extract_api_key_mineru")?,
                    &document,
                    &pdf,
                    pages,
                    &options,
                    &task_token,
                    |progress| {
                        if emit(ExtractionEvent::Progress { progress }).is_err() {
                            task_token.cancel();
                        }
                    },
                )
                .await?
        }
    };
    let token = task_token.clone();
    backend
        .runtime
        .call(&task_token, "publish_ocr", move |state| {
            if archive::hash_file(&pdf, &token)? != expected {
                return Err(OtterError::new(
                    ErrorCode::Conflict,
                    "PDF changed during OCR",
                ));
            }
            let directory = directory(state.storage()?, &document)?;
            let info = state.pdf()?.open(&pdf, None, &token)?;
            let result = (|| -> Result<String> {
                if matches!(output.provider, ocr::Provider::Mineru) && output.raw.is_array() {
                    let sizes = info
                        .pages
                        .iter()
                        .map(|p| vec![f64::from(p.width), f64::from(p.height)])
                        .collect::<Vec<_>>();
                    output.structure = crate::document::structure::Structure::from_mineru_v2(
                        output.raw.as_array().unwrap(),
                        &sizes,
                    )?;
                    output.model =
                        crate::document::DocumentModel::from_structure(&output.structure);
                }
                let crops = crate::pdf::figures::render(
                    state.pdf()?,
                    &info,
                    &output.structure,
                    &output.model.figures,
                    &token,
                    |done, total| {
                        if emit(ExtractionEvent::Progress {
                            progress: Progress {
                                stage: OcrStage::Converting,
                                done,
                                total,
                            },
                        })
                        .is_err()
                        {
                            token.cancel();
                        }
                    },
                )?;
                output.assets.extend(crops.assets);
                ocr::publish(&directory, &output, &token)
            })();
            state.pdf()?.close(info.handle)?;
            let generation = result?;
            ocr::usage::record(state.storage()?, output.provider, info.pages.len() as u64)?;
            emit(ExtractionEvent::Published {
                document_id: document,
                generation,
            })
            .map_err(closed)
        })
        .await
}

fn closed(_: impl std::fmt::Debug) -> OtterError {
    OtterError::new(ErrorCode::Cancelled, "OCR stream closed")
}
