use super::*;

pub fn compose_user_text(question: &str, quote: Option<&str>, context: Option<&str>) -> String {
    let mut parts = Vec::new();
    if let Some(context) = context.filter(|s| !s.is_empty()) {
        parts.push(context.to_owned());
    }
    if let Some(quote) = quote.map(str::trim).filter(|s| !s.is_empty()) {
        parts.push(
            quote
                .lines()
                .map(|line| format!("> {line}"))
                .collect::<Vec<_>>()
                .join("\n"),
        );
    }
    parts.push(question.into());
    parts.join("\n\n")
}

pub(crate) fn read_markdown(directory: &Path) -> Result<String> {
    let pointer = directory.join("ocr-current.json");
    if pointer.is_file() {
        let value: Value = serde_json::from_slice(&std::fs::read(pointer)?)?;
        // OCR generations use a digest component; never accept a path from persisted JSON.
        if let Some(generation) = value["generation"].as_str() {
            let root = directory.join("ocr").join(files::component(generation)?);
            for name in ["extract.raw.md", "extract.md"] {
                let path = root.join(name);
                if path.is_file() {
                    return Ok(std::fs::read_to_string(path)?);
                }
            }
        }
    }
    for name in ["extract.raw.md", "extract.md"] {
        let path = directory.join(name);
        if path.is_file() {
            return Ok(std::fs::read_to_string(path)?);
        }
    }
    let model: crate::document::DocumentModel =
        serde_json::from_slice(&std::fs::read(directory.join("document.json"))?)?;
    Ok(model
        .blocks
        .iter()
        .filter(|b| b.owner_id.is_none())
        .map(|b| b.markdown.as_str())
        .collect::<Vec<_>>()
        .join("\n\n"))
}

pub(crate) fn load_figures(
    directory: &Path,
    only: Option<&str>,
    label: Option<&str>,
) -> Result<Vec<ImageInput>> {
    let figures = crate::pdf::figures::directory(directory)?;
    let entries: Vec<(String, Option<String>)> = if let Some(path) = only {
        vec![(path.to_owned(), label.map(str::to_owned))]
    } else {
        crate::pdf::figures::read_assets(directory)?
            .into_iter()
            .map(|entry| (entry.image_path, Some(entry.caption_text)))
            .collect()
    };
    let mut images = Vec::new();
    for (raw, label) in entries {
        let raw = raw.replace('\\', "/");
        let relative = if raw.starts_with('/') || raw.contains(':') {
            raw.rsplit_once("/figures/")
                .map(|(_, tail)| tail)
                .unwrap_or_else(|| raw.rsplit('/').next().unwrap_or(""))
        } else {
            &raw
        };
        crate::sync::archive::safe_relative(relative)?;
        let path = figures.join(relative);
        if !path.is_file() {
            continue;
        }
        let root = figures.canonicalize()?;
        if !root.starts_with(directory.canonicalize()?) || !path.canonicalize()?.starts_with(&root)
        {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "figure path outside document",
            ));
        }
        let mime = match path
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_ascii_lowercase()
            .as_str()
        {
            "jpg" | "jpeg" => "image/jpeg",
            "webp" => "image/webp",
            "png" => "image/png",
            _ => {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "figure image extension",
                ));
            }
        };
        images.push(ImageInput {
            mime_type: mime.into(),
            bytes: std::fs::read(path)?,
            label,
        });
    }
    Ok(images)
}

impl AiClient {
    pub async fn chat_title(
        &self,
        model: &ModelConfig,
        key: &str,
        question: &str,
        quote: Option<&str>,
        token: &CancellationToken,
    ) -> Result<String> {
        let mut model = model.clone();
        model.params.thinking = Some(ThinkingLevel::Off);
        let text = compose_user_text(question, quote, None)
            .chars()
            .take(1000)
            .collect();
        let request = ChatRequest {
            system: TITLE_SYSTEM.into(),
            messages: vec![Message {
                role: Role::User,
                text,
                images: Vec::new(),
            }],
            ..Default::default()
        };
        let answer = tokio::time::timeout(
            std::time::Duration::from_secs(30),
            self.send(&model, key, &request, token),
        )
        .await
        .map_err(|_| OtterError::new(ErrorCode::Network, "chat title timeout"))??;
        Ok(answer
            .text
            .lines()
            .next()
            .unwrap_or("")
            .trim()
            .chars()
            .take(30)
            .collect())
    }
}
