//! PaddleOCR v2 asynchronous jobs. API credentials never accompany result URLs.
use super::*;

impl OcrClient {
    /// 超过 1000 页时按页段提交多个任务，全部完成后按页段顺序合并；任一页段
    /// 失败即返回错误，不发布部分结果。`page_count` 未知时整份提交。
    #[allow(clippy::too_many_arguments)]
    pub async fn paddle_job(
        &self,
        pdf: &Path,
        job_url: &str,
        key: &str,
        options: &PaddleOptions,
        page_count: Option<usize>,
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
        let plan = chunks::plan(page_count, chunks::PADDLE_MAX_PAGES);
        let batch = (plan.len() > 1).then(|| {
            let millis = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis();
            format!("nr_{millis}")
        });
        let payload = serde_json::to_string(&options.payload()?)?;
        let mut jobs = Vec::with_capacity(plan.len());
        for chunk in &plan {
            progress(Progress {
                stage: OcrStage::Uploading,
                done: chunk.index,
                total: plan.len(),
            });
            let mut form = reqwest::multipart::Form::new()
                .part(
                    "file",
                    reqwest::multipart::Part::bytes(bytes.clone())
                        .file_name("source.pdf")
                        .mime_str("application/pdf")?,
                )
                .text("model", "PaddleOCR-VL-1.6")
                .text("optionalPayload", payload.clone());
            if let Some(batch) = &batch {
                form = form.text("batchId", batch.clone());
            }
            if let Some(ranges) = chunk.ranges() {
                form = form.text("pageRanges", ranges);
            }
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
            jobs.push(job.to_owned());
        }

        // 每个页段：已提取页数、总页数、完成后的页面列表。
        let mut extracted = vec![0usize; plan.len()];
        let mut totals: Vec<usize> = plan.iter().map(|c| c.end + 1 - c.start.max(1)).collect();
        let mut results: Vec<Option<Vec<Value>>> = vec![None; plan.len()];
        let mut markdown_only = None;
        let mut failures = 0;
        while results.iter().any(Option::is_none) && markdown_only.is_none() {
            cancellable(token, async {
                tokio::time::sleep(self.poll_interval * (1 << failures.min(3))).await;
                Ok(())
            })
            .await?;
            for (i, job) in jobs.iter().enumerate() {
                if results[i].is_some() {
                    continue;
                }
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
                        break;
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
                                .map(|v| v.min(usize::MAX as u64) as usize)
                        };
                        extracted[i] = count("extractedPages").unwrap_or(0);
                        if let Some(total) = count("totalPages") {
                            totals[i] = total;
                        }
                        progress(Progress {
                            stage: if data["state"] == "pending" {
                                OcrStage::Queued
                            } else {
                                OcrStage::Running
                            },
                            done: extracted.iter().sum(),
                            total: totals.iter().sum(),
                        });
                    }
                    Some("done") => {
                        progress(Progress {
                            stage: OcrStage::Downloading,
                            done: results.iter().filter(|r| r.is_some()).count(),
                            total: plan.len(),
                        });
                        let urls = &data["resultUrl"];
                        if let Some(url) = urls["jsonUrl"].as_str() {
                            let bytes = network::bytes(
                                network::send(self.download_client.get(url), token).await?,
                                512 * 1024 * 1024,
                                token,
                            )
                            .await?;
                            results[i] = Some(tasks::blocking(token, move || jsonl(&bytes)).await?);
                            extracted[i] = totals[i];
                        } else if let (Some(url), 1) = (urls["markdownUrl"].as_str(), plan.len()) {
                            markdown_only = Some(url.to_owned());
                            break;
                        } else {
                            return Err(OtterError::new(
                                ErrorCode::InvalidData,
                                "Paddle result URL missing",
                            ));
                        }
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
        let mut output = if let Some(url) = markdown_only {
            let bytes = network::bytes(
                network::send(self.download_client.get(url), token).await?,
                128 * 1024 * 1024,
                token,
            )
            .await?;
            tasks::blocking(token, move || markdown_output(bytes)).await?
        } else {
            let pages: Vec<Value> = results.into_iter().flatten().flatten().collect();
            tasks::blocking(token, move || {
                paddle_output(json!({ "layoutParsingResults": pages }))
            })
            .await?
        };
        self.paddle_assets(&mut output, token).await?;
        Ok(output)
    }
}

fn markdown_output(bytes: Vec<u8>) -> Result<OcrOutput> {
    let markdown = String::from_utf8(bytes)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "Paddle markdown UTF-8"))?;
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

/// 一个任务的 JSONL 结果按行展开为页面列表；截断或格式错误的行直接报错，
/// 不发布静默缺页的文档。
fn jsonl(bytes: &[u8]) -> Result<Vec<Value>> {
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
    if pages.is_empty() {
        return Err(OtterError::new(ErrorCode::InvalidData, "empty OCR result"));
    }
    Ok(pages)
}
