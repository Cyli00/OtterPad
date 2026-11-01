//! PaddleOCR v2 asynchronous jobs. API credentials never accompany result URLs.
use super::*;

impl OcrClient {
    pub async fn paddle_job(
        &self,
        pdf: &Path,
        job_url: &str,
        key: &str,
        options: &PaddleOptions,
        token: &CancellationToken,
        mut progress: impl FnMut(Progress),
    ) -> Result<OcrOutput> {
        let length = tokio::fs::metadata(pdf).await?.len();
        if length > 50 * 1024 * 1024 {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "Paddle upload exceeds 50 MB",
            ));
        }
        let bytes = cancellable(token, async { Ok(tokio::fs::read(pdf).await?) }).await?;
        validate_pdf(&bytes)?;
        let form = reqwest::multipart::Form::new()
            .part(
                "file",
                reqwest::multipart::Part::bytes(bytes)
                    .file_name("source.pdf")
                    .mime_str("application/pdf")?,
            )
            .text("model", "PaddleOCR-VL-1.6")
            .text(
                "optionalPayload",
                serde_json::to_string(&options.payload()?)?,
            );
        progress(Progress {
            stage: OcrStage::Uploading,
            done: 0,
            total: 1,
        });
        let submitted = job_response(
            self.client
                .post(job_url)
                .header("Authorization", format!("bearer {key}"))
                .multipart(form),
            token,
        )
        .await?;
        let job = submitted["data"]["jobId"]
            .as_str()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "Paddle job ID missing"))?;
        files::component(job)?;
        let mut failures = 0;
        loop {
            cancellable(token, async {
                tokio::time::sleep(self.poll_interval * (1 << failures.min(3))).await;
                Ok(())
            })
            .await?;
            let response = job_response(
                self.client
                    .get(format!("{}/{job}", job_url.trim_end_matches('/')))
                    .header("Authorization", format!("bearer {key}")),
                token,
            )
            .await;
            let value = match response {
                Ok(value) => {
                    failures = 0;
                    value
                }
                Err(error)
                    if matches!(
                        error.code,
                        ErrorCode::Network | ErrorCode::RateLimited | ErrorCode::Remote
                    ) && failures < 3 =>
                {
                    failures += 1;
                    continue;
                }
                Err(error) => return Err(error),
            };
            let data = &value["data"];
            match data["state"].as_str() {
                Some("pending" | "running") => {
                    let count = |name: &str| {
                        data["extractProgress"][name]
                            .as_u64()
                            .or_else(|| data["extractProgress"][name].as_str()?.parse().ok())
                            .unwrap_or(0)
                            .min(usize::MAX as u64) as usize
                    };
                    progress(Progress {
                        stage: if data["state"] == "pending" {
                            OcrStage::Queued
                        } else {
                            OcrStage::Running
                        },
                        done: count("extractedPages"),
                        total: count("totalPages"),
                    });
                }
                Some("done") => {
                    progress(Progress {
                        stage: OcrStage::Downloading,
                        done: 0,
                        total: 1,
                    });
                    let urls = &data["resultUrl"];
                    let mut output = if let Some(url) = urls["jsonUrl"].as_str() {
                        let bytes = network::bytes(
                            network::send(self.download_client.get(url), token).await?,
                            512 * 1024 * 1024,
                            token,
                        )
                        .await?;
                        tasks::blocking(token, move || jsonl(&bytes)).await?
                    } else if let Some(url) = urls["markdownUrl"].as_str() {
                        let bytes = network::bytes(
                            network::send(self.download_client.get(url), token).await?,
                            128 * 1024 * 1024,
                            token,
                        )
                        .await?;
                        tasks::blocking(token, move || {
                            let markdown = String::from_utf8(bytes).map_err(|_| {
                                OtterError::new(ErrorCode::InvalidData, "Paddle markdown UTF-8")
                            })?;
                            if markdown.trim().is_empty() {
                                return Err(OtterError::new(
                                    ErrorCode::InvalidData,
                                    "Paddle markdown empty",
                                ));
                            }
                            Ok(OcrOutput {
                                provider: Provider::Paddleocr,
                                raw: Value::Null,
                                model: DocumentModel::from_markdown(&markdown),
                                raw_markdown: markdown,
                                structure: Structure::from_value(&json!([]))?,
                                assets: BTreeMap::new(),
                                export_zip: None,
                            })
                        })
                        .await?
                    } else {
                        return Err(OtterError::new(
                            ErrorCode::InvalidData,
                            "Paddle result URL missing",
                        ));
                    };
                    self.paddle_assets(&mut output, token).await?;
                    return Ok(output);
                }
                Some("failed") => {
                    return Err(OtterError::new(ErrorCode::Remote, "Paddle job failed"));
                }
                _ => {
                    return Err(OtterError::new(
                        ErrorCode::InvalidData,
                        "unknown Paddle job state",
                    ));
                }
            }
        }
    }
}

async fn job_response(
    request: reqwest::RequestBuilder,
    token: &CancellationToken,
) -> Result<Value> {
    // A quota code may accompany a non-success HTTP status.
    let response = cancellable(token, async { Ok(request.send().await?) }).await?;
    let status = response.status();
    let bytes = network::bytes(response, 8 * 1024 * 1024, token).await?;
    let value: Value = serde_json::from_slice(&bytes)?;
    let code = value["code"]
        .as_i64()
        .or_else(|| value["code"].as_str()?.parse().ok())
        .unwrap_or(0);
    if code != 0 {
        let code = match code {
            12001 => ErrorCode::QuotaExceeded,
            10010 | 12002 => ErrorCode::RateLimited,
            10003 | 10006 | 10009 => ErrorCode::InvalidArgument,
            _ => ErrorCode::Remote,
        };
        return Err(OtterError::new(code, "Paddle rejected job"));
    }
    network::status(status)?;
    Ok(value)
}

fn jsonl(bytes: &[u8]) -> Result<OcrOutput> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "Paddle JSONL UTF-8"))?;
    let mut pages = Vec::new();
    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let value: Value = serde_json::from_str(line)?;
        let entries = value["result"]["layoutParsingResults"]
            .as_array()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "Paddle JSONL pages missing"))?;
        pages.extend(entries.iter().cloned());
    }
    // Preserve page order and reject truncated/malformed lines instead of
    // publishing an apparently successful document with silently missing pages.
    paddle_output(json!({"layoutParsingResults": pages}))
}
