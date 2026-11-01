use super::*;

impl Translator {
    /// Each paragraph is independent; all documents share eight live request permits.
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
        let mut futures = FuturesUnordered::new();
        for (hash, (source, count)) in pending {
            let child = &child;
            futures.push(async move {
                let result = async {
                    let permit = cancellable(child, async {
                        PERMITS.acquire().await.map_err(|_| {
                            OtterError::new(ErrorCode::Cancelled, "translation queue closed")
                        })
                    })
                    .await?;
                    let result = async {
                        for attempt in 0..=2 {
                            let result = self
                                .selection(&source, model, key, config, false, child)
                                .await;
                            if result.as_ref().is_err_and(retryable) && attempt < 2 {
                                cancellable(child, async {
                                    tokio::time::sleep(Duration::from_secs(1 << attempt)).await;
                                    Ok(())
                                })
                                .await?;
                            } else {
                                return result;
                            }
                        }
                        unreachable!()
                    }
                    .await;
                    drop(permit);
                    result
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
