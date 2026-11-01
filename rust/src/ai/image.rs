use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::multipart::{Form, Part};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use super::{
    AiClient,
    catalog::ModelCapabilities,
    protocol,
    types::{ImageInput, ModelConfig, Provider},
};
use crate::{
    error::{ErrorCode, OtterError, Result},
    network,
    tasks::check,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageRequest {
    pub prompt: String,
    pub references: Vec<ImageInput>,
    pub aspect_ratio: String,
    pub fidelity: String,
    pub capabilities: ModelCapabilities,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageResponse {
    pub bytes: Vec<u8>,
    pub mime_type: String,
    pub text: String,
    pub request_id: Option<String>,
}

impl AiClient {
    pub async fn generate_image(
        &self,
        config: &ModelConfig,
        key: &str,
        input: &ImageRequest,
        token: &CancellationToken,
    ) -> Result<ImageResponse> {
        check(token)?;
        if key.trim().is_empty() {
            return Err(OtterError::new(ErrorCode::Authentication, "AI key missing"));
        }
        if !input.capabilities.image_output
            || input.capabilities.embedding
            || input.prompt.trim().is_empty()
        {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "image generation capability/prompt",
            ));
        }
        if input.references.iter().any(|i| {
            i.bytes.is_empty()
                || !matches!(
                    i.mime_type.as_str(),
                    "image/png" | "image/jpeg" | "image/webp"
                )
        }) {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "reference image format",
            ));
        }
        let provider = protocol::wire_provider(config);
        let request = match provider {
            Provider::Anthropic => {
                return Err(OtterError::new(
                    ErrorCode::Unsupported,
                    "Anthropic image generation",
                ));
            }
            Provider::Gemini => {
                let mut parts = vec![json!({"text":input.prompt})];
                for image in &input.references {
                    parts.push(json!({"inline_data":{"mime_type":image.mime_type,"data":STANDARD.encode(&image.bytes)}}));
                }
                let mut image_config = json!({"aspectRatio":input.aspect_ratio});
                match input.fidelity.as_str() {
                    "standard" => image_config["imageSize"] = json!("1K"),
                    "high" => image_config["imageSize"] = json!("2K"),
                    _ => {}
                }
                self.client.post(protocol::chat_endpoint(config,false)?).json(&json!({"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["TEXT","IMAGE"],"imageConfig":image_config}}))
            }
            _ => {
                let size = match input.aspect_ratio.as_str() {
                    "1:1" => "1024x1024",
                    "4:3" => "1536x1152",
                    "16:9" => "1536x864",
                    "21:9" => "1536x660",
                    "9:16" => "864x1536",
                    _ => "1536x1024",
                };
                let quality = match input.fidelity.as_str() {
                    "auto" => Some("auto"),
                    "standard" => Some("medium"),
                    "high" => Some("high"),
                    _ => None,
                };
                if input.references.is_empty() {
                    let mut body = json!({"model":config.model,"prompt":input.prompt,"output_format":"webp","output_compression":80,"size":size});
                    if let Some(q) = quality {
                        body["quality"] = json!(q);
                    }
                    self.client
                        .post(protocol::endpoint(config, "images/generations")?)
                        .json(&body)
                } else {
                    let mut form = Form::new()
                        .text("model", config.model.clone())
                        .text("prompt", input.prompt.clone())
                        .text("output_format", "webp")
                        .text("output_compression", "80")
                        .text("size", size);
                    if let Some(q) = quality {
                        form = form.text("quality", q);
                    }
                    for (i, image) in input.references.iter().enumerate() {
                        let part = Part::bytes(image.bytes.clone())
                            .file_name(format!("reference-{i}"))
                            .mime_str(&image.mime_type)?;
                        form = form.part("image[]", part);
                    }
                    self.client
                        .post(protocol::endpoint(config, "images/edits")?)
                        .multipart(form)
                }
            }
        };
        let response = network::send_api(self.authorize(request, provider, key), token).await?;
        let request_id = response
            .headers()
            .get("x-request-id")
            .and_then(|v| v.to_str().ok())
            .map(str::to_owned);
        let value: Value =
            serde_json::from_slice(&network::bytes(response, 64 * 1024 * 1024, token).await?)?;
        if provider == Provider::Gemini {
            let candidate = &value["candidates"][0];
            if candidate["finishReason"]
                .as_str()
                .is_some_and(|r| r != "STOP")
                || value["promptFeedback"]["blockReason"].is_string()
            {
                return Err(OtterError::new(
                    ErrorCode::Refused,
                    "image generation blocked/incomplete",
                ));
            }
            let mut text = Vec::new();
            let mut image = None;
            if let Some(parts) = candidate["content"]["parts"].as_array() {
                for part in parts {
                    if part["thought"] == true {
                        continue;
                    }
                    if let Some(value) = part["text"].as_str() {
                        text.push(value);
                    }
                    let inline = part.get("inlineData").or_else(|| part.get("inline_data"));
                    if image.is_none()
                        && let Some(inline) = inline
                        && let Some(data) = inline["data"].as_str()
                    {
                        image = Some((
                            decode(data)?,
                            inline["mimeType"]
                                .as_str()
                                .or_else(|| inline["mime_type"].as_str())
                                .unwrap_or("image/png")
                                .to_owned(),
                        ));
                    }
                }
            }
            let (bytes, mime_type) = image
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "Gemini image missing"))?;
            Ok(ImageResponse {
                bytes,
                mime_type,
                text: text.join("\n"),
                request_id,
            })
        } else {
            let data = value["data"][0]["b64_json"]
                .as_str()
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "image payload missing"))?;
            let bytes = decode(data)?;
            let mime_type = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
                "image/png"
            } else if bytes.starts_with(b"\xff\xd8\xff") {
                "image/jpeg"
            } else if bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP") {
                "image/webp"
            } else {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "unsupported generated image signature",
                ));
            };
            Ok(ImageResponse {
                bytes,
                mime_type: mime_type.into(),
                text: String::new(),
                request_id,
            })
        }
    }
}

fn decode(text: &str) -> Result<Vec<u8>> {
    let bytes = STANDARD
        .decode(text)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "image base64"))?;
    if bytes.is_empty() {
        return Err(OtterError::new(ErrorCode::InvalidData, "empty image"));
    }
    Ok(bytes)
}
