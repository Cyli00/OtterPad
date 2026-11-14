use super::*;

impl Translator {
    /// 各段独立请求，并发由按端点共享的 [`limiter`] 自适应控制；持续限流时停止整批并保存已完成段落。
    #[allow(clippy::too_many_arguments)]
    pub async fn document(
        &self,
        document: &str,
        paragraphs: &[Paragraph],
        model: &ModelConfig,
        key: &str,
        config: &TranslationConfig,
        use_cache: bool,
        token: &CancellationToken,
        mut emit: impl FnMut(TranslationEvent) -> Result<()>,
    ) -> Result<TranslationReport> {
        check(token)?;
        let cached = if use_cache {
            self.load(document, &config.language).await?
        } else {
            BTreeMap::new()
        };
        let mut pending = BTreeMap::<String, (String, usize)>::new();
        for paragraph in paragraphs {
            if paragraph.hash != revision(paragraph.source.trim()) {
                return Err(OtterError::new(
                    ErrorCode::InvalidArgument,
                    "paragraph source hash mismatch",
                ));
            }
            let value = pending
                .entry(paragraph.hash.clone())
                .or_insert((paragraph.source.clone(), 0));
            value.1 += 1;
        }
        let mut report = TranslationReport {
            total: paragraphs.len(),
            completed: 0,
            cached: 0,
            failures: Vec::new(),
        };
        emit(TranslationEvent::Progress {
            completed: 0,
            total: report.total,
        })?;
        for (hash, (_, count)) in &pending {
            if let Some(text) = cached.get(hash) {
                emit(TranslationEvent::Result {
                    hash: hash.clone(),
                    text: text.clone(),
                })?;
                report.completed += count;
                report.cached += count;
            }
        }
        pending.retain(|hash, _| !cached.contains_key(hash));
        emit(TranslationEvent::Progress {
            completed: report.completed,
            total: report.total,
        })?;
        let child = token.child_token();
        let limiter = limiter::Limiter::for_endpoint(model);
        let mut futures = FuturesUnordered::new();
        for (hash, (source, count)) in pending {
            let child = &child;
            let limiter = &limiter;
            futures.push(async move {
                let result = async {
                    let (mut failures, mut limited) = (0, 0);
                    loop {
                        let permit =
                            cancellable(child, async { Ok(limiter.acquire().await) }).await?;
                        let result = self
                            .selection(&source, model, key, config, false, child)
                            .await;
                        match &result {
                            Ok(_) => permit.succeeded(),
                            // 限流的等待由 limiter 统一暂停，这里只限制单段重试次数。
                            Err(error) if error.code == ErrorCode::RateLimited => {
                                if !permit.rate_limited() && limited < 10 {
                                    limited += 1;
                                    continue;
                                }
                            }
                            Err(error) if retryable(error) && failures < 2 => {
                                drop(permit);
                                cancellable(child, async {
                                    tokio::time::sleep(Duration::from_secs(1 << failures)).await;
                                    Ok(())
                                })
                                .await?;
                                failures += 1;
                                continue;
                            }
                            Err(_) => {}
                        }
                        return result;
                    }
                }
                .await;
                (hash, count, result)
            });
        }
        let mut completed = BTreeMap::new();
        let work: Result<()> = async {
            while let Some((hash, count, result)) = futures.next().await {
                match result {
                    Ok(text) => {
                        completed.insert(hash.clone(), text.clone());
                        report.completed += count;
                        emit(TranslationEvent::Result { hash, text })?;
                        emit(TranslationEvent::Progress {
                            completed: report.completed,
                            total: report.total,
                        })?;
                        if completed.len() >= 8 {
                            self.save(document, &config.language, &completed).await?;
                            completed.clear();
                        }
                    }
                    Err(error)
                        if matches!(
                            error.code,
                            ErrorCode::Authentication
                                | ErrorCode::QuotaExceeded
                                | ErrorCode::RateLimited
                                | ErrorCode::Cancelled
                        ) =>
                    {
                        return Err(error);
                    }
                    Err(error) => {
                        report.failures.push(TranslationFailure {
                            hash: hash.clone(),
                            code: error.code,
                        });
                        emit(TranslationEvent::Failure {
                            hash,
                            code: error.code,
                        })?;
                    }
                }
            }
            Ok(())
        }
        .await;
        child.cancel();
        drop(futures);
        // A cancelled request still keeps every completed paragraph, including the final short batch.
        if !completed.is_empty() {
            self.save(document, &config.language, &completed).await?;
        }
        work?;
        check(token)?;
        Ok(report)
    }
}
