use std::path::{Path, PathBuf};

use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::{
    AiClient,
    catalog::ModelCapabilities,
    chat::{load_figures, now, read_markdown},
    image::ImageRequest,
    types::{ModelConfig, Provider},
};
use crate::{
    document::{figures, revision},
    error::{ErrorCode, OtterError, Result},
    files,
    storage::Document,
    tasks::check,
    translate::paragraph,
};

pub const DEFAULT_PROMPT: &str = "A detailed scientific infographic summarizing a paper, in the style of a Cell journal highlight summary.\n- Layout: a title, short explanatory text blocks, and simple diagram panels connected by arrows, presenting key findings in a structured, readable flow.\n- Style: clean vector-like line art, thin dark grey outlines, sans-serif labels, editorial and precise.\n- Color: white or very light grey background; soft muted blue and warm pale grey as the base; very pale desaturated orange for functional coding only.\n- Text density: medium — a title plus 3-6 short text blocks.\n\nDo not use: purple, large filled color blocks, gradients, shadows, 3D, or photorealistic rendering.\n";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SummaryConfig {
    pub prompt: String,
    pub aspect_ratio: String,
    pub fidelity: String,
    pub max_reference_images: usize,
    pub language: Option<String>,
}
impl Default for SummaryConfig {
    fn default() -> Self {
        Self {
            prompt: DEFAULT_PROMPT.into(),
            aspect_ratio: "9:16".into(),
            fidelity: "auto".into(),
            max_reference_images: 10,
            language: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SummaryRecord {
    pub image_path: PathBuf,
    pub metadata_path: PathBuf,
    pub mime_type: String,
    pub reference_image_count: usize,
}

pub struct SummaryService {
    directory: PathBuf,
}
impl SummaryService {
    pub fn new(directory: PathBuf) -> Self {
        Self { directory }
    }

    fn directory(&self, document: &Document) -> Result<PathBuf> {
        if document.content_hash.is_none() {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "summary PDF missing",
            ));
        }
        let directory = self
            .directory
            .join("library")
            .join(files::component(&document.id)?);
        if !directory.is_dir() {
            return Err(OtterError::new(
                ErrorCode::NotFound,
                "summary document missing",
            ));
        }
        Ok(directory)
    }

    /// Clipboard/export prompt: the user supplies the paper Markdown as a separate attachment.
    pub fn compose(
        &self,
        document: &Document,
        config: &SummaryConfig,
        provider: Provider,
    ) -> Result<String> {
        let directory = self.directory(document)?;
        read_markdown(&directory)?;
        validate(config)?;
        Ok(prompt(document, None, config, provider))
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn generate(
        &self,
        document: &Document,
        config: &SummaryConfig,
        model: &ModelConfig,
        key: &str,
        capabilities: &ModelCapabilities,
        ai: &AiClient,
        token: &CancellationToken,
    ) -> Result<SummaryRecord> {
        check(token)?;
        validate(config)?;
        let directory = self.directory(document)?;
        let markdown = read_markdown(&directory)?;
        let (markdown, offset) = compact(&markdown);
        let references = references(&directory, config.max_reference_images.clamp(1, 10))?;
        let count = references.len();
        let image = ai
            .generate_image(
                model,
                key,
                &ImageRequest {
                    prompt: prompt(document, Some(&markdown), config, model.provider),
                    references,
                    aspect_ratio: config.aspect_ratio.clone(),
                    fidelity: config.fidelity.clone(),
                    capabilities: capabilities.clone(),
                },
                token,
            )
            .await?;
        check(token)?;
        let metadata = json!({"documentId":document.id,"title":document.title,"provider":model.provider,"modelId":model.model,"aspectRatio":config.aspect_ratio,"fidelity":config.fidelity,"referenceImageCount":count,"requestId":image.request_id,"providerText":image.text,"createdAt":now()?,"backMatterOffset":offset,"mimeType":image.mime_type});
        let content_hash = Sha256::digest(&image.bytes)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        let identity = revision(&format!("{content_hash}{metadata}"));
        let extension = match image.mime_type.as_str() {
            "image/png" => "png",
            "image/jpeg" => "jpg",
            "image/webp" => "webp",
            _ => {
                return Err(OtterError::new(
                    ErrorCode::Unsupported,
                    "summary image MIME",
                ));
            }
        };
        let generation = directory.join("summary/generations").join(&identity);
        files::atomic_write(&generation.join(format!("image.{extension}")), &image.bytes)?;
        files::write_json(&generation.join("summary.meta.json"), &metadata)?;
        check(token)?;
        files::write_json(
            &directory.join("summary/current.json"),
            &json!({"generation":identity,"image":format!("image.{extension}")}),
        )?;
        Ok(SummaryRecord {
            image_path: generation.join(format!("image.{extension}")),
            metadata_path: generation.join("summary.meta.json"),
            mime_type: image.mime_type,
            reference_image_count: count,
        })
    }

    pub fn current(&self, document: &Document) -> Result<Option<SummaryRecord>> {
        let summary = self.directory(document)?.join("summary");
        let pointer = summary.join("current.json");
        if pointer.is_file() {
            let value: Value = serde_json::from_slice(&std::fs::read(pointer)?)?;
            let generation = value["generation"]
                .as_str()
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "summary generation"))?;
            let image = value["image"]
                .as_str()
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "summary image path"))?;
            let directory = summary
                .join("generations")
                .join(files::component(generation)?);
            let metadata_path = directory.join("summary.meta.json");
            let metadata: Value = serde_json::from_slice(&std::fs::read(&metadata_path)?)?;
            let image_path = directory.join(files::component(image)?);
            if !image_path.is_file() {
                return Err(OtterError::new(
                    ErrorCode::NotFound,
                    "summary image missing",
                ));
            }
            Ok(Some(SummaryRecord {
                image_path,
                metadata_path,
                mime_type: metadata["mimeType"].as_str().unwrap_or("image/png").into(),
                reference_image_count: metadata["referenceImageCount"].as_u64().unwrap_or(0)
                    as usize,
            }))
        } else {
            let image_path = summary.join("summary.png");
            if !image_path.is_file() {
                return Ok(None);
            }
            let metadata_path = summary.join("summary.meta.json");
            let metadata: Value = if metadata_path.is_file() {
                serde_json::from_slice(&std::fs::read(&metadata_path)?)?
            } else {
                Value::Null
            };
            let bytes = std::fs::read(&image_path)?;
            let mime = if bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP") {
                "image/webp"
            } else if bytes.starts_with(b"\xff\xd8") {
                "image/jpeg"
            } else {
                "image/png"
            };
            Ok(Some(SummaryRecord {
                image_path,
                metadata_path,
                mime_type: mime.into(),
                reference_image_count: metadata["referenceImageCount"].as_u64().unwrap_or(0)
                    as usize,
            }))
        }
    }
}

fn validate(config: &SummaryConfig) -> Result<()> {
    if !["1:1", "4:3", "3:2", "16:9", "21:9", "9:16"].contains(&config.aspect_ratio.as_str())
        || !["auto", "standard", "high"].contains(&config.fidelity.as_str())
        || config.prompt.trim().is_empty()
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "summary configuration",
        ));
    }
    Ok(())
}

pub fn compact(markdown: &str) -> (String, Option<usize>) {
    let length = markdown.encode_utf16().count();
    let offset = paragraph::sections(markdown)
        .first()
        .map(|s| s.heading.start)
        .or_else(|| {
            if length <= 8000 {
                return None;
            }
            Regex::new(r"(?m)^#{1,2}\s+.+$")
                .unwrap()
                .find_iter(markdown)
                .find(|m| markdown[..m.start()].encode_utf16().count() >= length * 8 / 10)
                .map(|m| m.start())
        });
    let body = &markdown[..offset.unwrap_or(markdown.len())];
    let no_images = Regex::new(r"!\[[^\]]*\]\([^)]+\)")
        .unwrap()
        .replace_all(body, "");
    let normalized = Regex::new(r"\n{3,}")
        .unwrap()
        .replace_all(&no_images, "\n\n")
        .trim()
        .to_owned();
    let mut units = 0;
    let mut end = normalized.len();
    for (byte, c) in normalized.char_indices() {
        units += c.len_utf16();
        if units > 24000 {
            end = byte;
            break;
        }
    }
    let text = if end < normalized.len() {
        format!(
            "{}\n\n[Content truncated for image generation.]",
            &normalized[..end]
        )
    } else {
        normalized
    };
    (
        text,
        offset.map(|byte| markdown[..byte].encode_utf16().count()),
    )
}

fn prompt(
    document: &Document,
    markdown: Option<&str>,
    config: &SummaryConfig,
    provider: Provider,
) -> String {
    let mut constraints = format!("Required output aspect ratio: {}.", config.aspect_ratio);
    if let Some(language) = config.language.as_ref().filter(|v| !v.is_empty()) {
        constraints.push_str(&format!("\nAll visible text labels, titles, and annotations in the infographic must be in {language}."));
    }
    if !matches!(provider, Provider::Openai | Provider::Gemini) && config.fidelity != "auto" {
        constraints.push_str(&format!("\nImage quality: {}. Render at the highest resolution available for this quality tier.",config.fidelity));
    }
    let body=markdown.map(|m|format!("Processed Markdown:\n{m}")).unwrap_or_else(||"Paper full text:\nThe full paper Markdown is attached separately by the user. Read it to ground the infographic in the paper's actual content.".into());
    let authors = if document.authors.is_empty() {
        "Unknown".into()
    } else {
        document.authors.join(", ")
    };
    format!(
        "{}\n\n{constraints}\n\nUse the following paper material to create the infographic.\n\nTitle:\n{}\n\nMetadata:\nAuthors: {authors}\nJournal: {}\nYear: {}\nDOI: {}\nKeywords: {}\n\n{body}\n\nReference figures:\nThe attached images are extracted figures from the paper. Use them as scientific visual references, but redraw the final result as a clean editorial infographic. Do not copy dense text from the source figures verbatim.\n",
        config.prompt.trim(),
        document.title,
        document.journal.as_deref().unwrap_or("Unknown"),
        document.year.as_deref().unwrap_or("Unknown"),
        document.doi.as_deref().unwrap_or("Unknown"),
        document.keywords.join(", ")
    )
}

fn references(directory: &Path, limit: usize) -> Result<Vec<super::types::ImageInput>> {
    let figure_directory = crate::pdf::figures::directory(directory)?;
    if figure_directory.join("figures.json").is_file()
        || figure_directory
            .parent()
            .unwrap()
            .join("figures.json")
            .is_file()
    {
        let entries = crate::pdf::figures::read_assets(directory)?;
        let mut primary = Vec::new();
        let mut supplementary = Vec::new();
        for entry in entries {
            let images = load_figures(
                directory,
                Some(&entry.image_path),
                Some(&entry.caption_text),
            )?;
            if figures::supplementary_caption(&entry.caption_text) {
                supplementary.extend(images);
            } else {
                primary.extend(images);
            }
        }
        primary.extend(supplementary);
        primary.truncate(limit);
        Ok(primary)
    } else {
        let figures = figure_directory;
        if !figures.is_dir() {
            return Ok(Vec::new());
        }
        let mut files: Vec<_> = std::fs::read_dir(figures)?.collect::<std::io::Result<Vec<_>>>()?;
        files.sort_by_key(|e| e.file_name());
        let mut images = Vec::new();
        for entry in files {
            let name = entry.file_name().to_string_lossy().into_owned();
            if ["png", "jpg", "jpeg", "webp"].contains(
                &entry
                    .path()
                    .extension()
                    .and_then(|v| v.to_str())
                    .unwrap_or("")
                    .to_ascii_lowercase()
                    .as_str(),
            ) {
                images.extend(load_figures(directory, Some(&name), None)?);
            }
            if images.len() >= limit {
                break;
            }
        }
        Ok(images)
    }
}
