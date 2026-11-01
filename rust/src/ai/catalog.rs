use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio_util::sync::CancellationToken;

use super::{
    AiClient, protocol,
    types::{ModelConfig, Provider, ThinkingSpec},
};
use crate::{
    error::{ErrorCode, OtterError, Result},
    files, network,
    tasks::cancellable,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ModelCapabilities {
    pub text_input: bool,
    pub image_input: bool,
    pub text_output: bool,
    pub image_output: bool,
    pub embedding: bool,
    pub tool: bool,
    pub reasoning: bool,
    pub web_search: bool,
}

impl Default for ModelCapabilities {
    fn default() -> Self {
        Self {
            text_input: true,
            text_output: true,
            image_input: false,
            image_output: false,
            embedding: false,
            tool: false,
            reasoning: false,
            web_search: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    pub id: String,
    pub name: String,
    pub capabilities: ModelCapabilities,
}

#[derive(Default, Serialize, Deserialize)]
struct Cache {
    fetched_at: u64,
    etag: Option<String>,
    last_modified: Option<String>,
    data: Value,
}

pub struct CapabilityCatalog {
    path: PathBuf,
    cache: Cache,
}

pub const CAPABILITIES_URL: &str =
    "https://cdn.jsdelivr.net/gh/Cyli00/modelcaps@main/model_capabilities.json";

impl CapabilityCatalog {
    pub fn open(directory: &Path) -> Result<Self> {
        let path = directory.join("model_caps_cache.json");
        let cache = if path.exists() {
            let value: Value = serde_json::from_slice(&std::fs::read(&path)?)?;
            if value["models"].is_object() {
                Cache {
                    data: value,
                    ..Default::default()
                }
            } else {
                serde_json::from_value(value)?
            }
        } else {
            Cache::default()
        };
        Ok(Self { path, cache })
    }

    fn entry(&self, model: &str) -> Option<&Value> {
        candidates(model)
            .iter()
            .find_map(|id| self.cache.data["models"].get(id))
    }

    pub fn capabilities(
        &self,
        model: &str,
        manual: Option<&ModelCapabilities>,
    ) -> ModelCapabilities {
        manual
            .cloned()
            .or_else(|| {
                self.entry(model)
                    .and_then(|v| serde_json::from_value(v.clone()).ok())
            })
            .unwrap_or_default()
    }

    pub fn thinking(&self, model: &str) -> Option<ThinkingSpec> {
        self.entry(model)
            .and_then(|v| serde_json::from_value(v["thinking"].clone()).ok())
    }

    pub fn configure(&self, config: &mut ModelConfig) {
        if config.thinking_spec.is_none() {
            config.thinking_spec = self.thinking(&config.model);
        }
        if config.capabilities.is_none() {
            config.capabilities = Some(self.capabilities(&config.model, None));
        }
    }

    pub fn version(&self) -> Option<&str> {
        self.cache.data["version"].as_str()
    }

    pub async fn refresh(
        &mut self,
        client: &reqwest::Client,
        url: &str,
        force: bool,
        token: &CancellationToken,
    ) -> Result<bool> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| OtterError::new(ErrorCode::InvalidData, "system clock"))?
            .as_secs();
        if !force && self.cache.fetched_at != 0 && now / 86400 <= self.cache.fetched_at / 86400 {
            return Ok(false);
        }
        let mut request = client.get(url);
        if let Some(etag) = &self.cache.etag {
            request = request.header("If-None-Match", etag);
        }
        if let Some(modified) = &self.cache.last_modified {
            request = request.header("If-Modified-Since", modified);
        }
        let response = cancellable(token, async { Ok(request.send().await?) }).await?;
        let mut next = Cache {
            fetched_at: now,
            etag: self.cache.etag.clone(),
            last_modified: self.cache.last_modified.clone(),
            data: self.cache.data.clone(),
        };
        let changed = response.status().as_u16() != 304;
        if changed {
            network::status(response.status())?;
            next.etag = response
                .headers()
                .get("etag")
                .and_then(|v| v.to_str().ok())
                .map(str::to_owned);
            next.last_modified = response
                .headers()
                .get("last-modified")
                .and_then(|v| v.to_str().ok())
                .map(str::to_owned);
            let value: Value =
                serde_json::from_slice(&network::bytes(response, 16 * 1024 * 1024, token).await?)?;
            let models = value["models"].as_object().ok_or_else(|| {
                OtterError::new(ErrorCode::InvalidData, "model capabilities structure")
            })?;
            for entry in models.values() {
                let _: ModelCapabilities = serde_json::from_value(entry.clone())?;
            }
            next.data = value;
        } else if !next.data["models"].is_object() {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "304 without capabilities cache",
            ));
        }
        files::write_json(&self.path, &next)?;
        self.cache = next;
        Ok(changed)
    }
}

pub fn candidates(model: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut id = model.trim().rsplit('/').next().unwrap_or("").to_lowercase();
    if id.is_empty() {
        return result;
    }
    result.push(id.clone());
    id = id.split([':', '@']).next().unwrap_or("").into();
    // Strip only alphabetic vendor/region prefixes; a model's dotted version is retained.
    while let Some((prefix, rest)) = id.split_once('.') {
        if prefix.is_empty()
            || !prefix.bytes().all(|b| b.is_ascii_lowercase())
            || !rest.starts_with(|c: char| c.is_ascii_lowercase())
        {
            break;
        }
        id = rest.into();
    }
    if !result.contains(&id) {
        result.push(id.clone());
    }
    let mut parts: Vec<&str> = id.split('-').collect();
    const VARIANTS: [&str; 11] = [
        "fast", "turbo", "latest", "preview", "exp", "free", "thinking", "us", "eu", "global", "",
    ];
    while parts.len() > 1
        && parts.last().is_some_and(|s| {
            VARIANTS.contains(s)
                || ((4..=8).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_digit()))
        })
    {
        parts.pop();
        let id = parts.join("-");
        if !result.contains(&id) {
            result.push(id);
        }
    }
    result
}

impl AiClient {
    pub async fn models(
        &self,
        config: &ModelConfig,
        key: &str,
        catalog: Option<&CapabilityCatalog>,
        token: &CancellationToken,
    ) -> Result<Vec<ModelInfo>> {
        if key.is_empty() {
            return Err(OtterError::new(ErrorCode::Authentication, "AI key missing"));
        }
        let provider = protocol::wire_provider(config);
        let url = protocol::endpoint(config, "models")?;
        let mut cursor = None;
        let mut seen = std::collections::HashSet::new();
        let mut models = BTreeMap::new();
        for _ in 0..100 {
            let mut request = self.authorize(self.client.get(&url), provider, key);
            if let Some(value) = &cursor {
                request = request.query(&[(
                    if provider == Provider::Gemini {
                        "pageToken"
                    } else {
                        "after_id"
                    },
                    value,
                )]);
            }
            let data: Value = serde_json::from_slice(
                &network::bytes(network::send(request, token).await?, 8 * 1024 * 1024, token)
                    .await?,
            )?;
            let entries = data[if provider == Provider::Gemini {
                "models"
            } else {
                "data"
            }]
            .as_array()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "model list structure"))?;
            for entry in entries {
                let Some(id) = entry[if provider == Provider::Gemini {
                    "name"
                } else {
                    "id"
                }]
                .as_str() else {
                    continue;
                };
                let id = id.strip_prefix("models/").unwrap_or(id);
                let mut capabilities = catalog
                    .map(|c| c.capabilities(id, None))
                    .unwrap_or_default();
                if provider == Provider::Gemini
                    && let Some(methods) = entry["supportedGenerationMethods"].as_array()
                    && methods.iter().any(|v| v == "embedContent")
                    && !methods.iter().any(|v| v == "generateContent")
                {
                    capabilities = ModelCapabilities {
                        embedding: true,
                        ..Default::default()
                    };
                }
                models.insert(
                    id.to_owned(),
                    ModelInfo {
                        id: id.into(),
                        name: entry["displayName"]
                            .as_str()
                            .or_else(|| entry["display_name"].as_str())
                            .unwrap_or(id)
                            .into(),
                        capabilities,
                    },
                );
            }
            cursor = if provider == Provider::Gemini {
                data["nextPageToken"].as_str().map(str::to_owned)
            } else if data["has_more"] == true {
                data["last_id"].as_str().map(str::to_owned)
            } else {
                None
            };
            match &cursor {
                None => return Ok(models.into_values().collect()),
                Some(value) if !seen.insert(value.clone()) => {
                    return Err(OtterError::new(
                        ErrorCode::InvalidData,
                        "model list pagination cycle",
                    ));
                }
                _ => {}
            }
        }
        Err(OtterError::new(
            ErrorCode::InvalidData,
            "model list page limit",
        ))
    }
}
