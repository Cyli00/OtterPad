pub mod chunks;
pub mod paddle_job;
pub mod usage;

use std::{
    collections::BTreeMap,
    io::{Cursor, Read},
    path::{Component, Path},
    time::Duration,
};

use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use crate::{
    document::{DocumentModel, structure::Structure},
    error::{ErrorCode, OtterError, Result},
    files, network,
    tasks::{self, cancellable},
};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Provider {
    Paddleocr,
    Mineru,
}
impl Provider {
    fn key(self) -> &'static str {
        match self {
            Self::Paddleocr => "paddleocr",
            Self::Mineru => "mineru",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PaddleOptions {
    pub markdown_ignore_labels: Vec<String>,
    pub use_chart_recognition: bool,
    pub use_doc_orientation_classify: bool,
    pub use_doc_unwarping: bool,
    pub use_seal_recognition: bool,
    pub use_ocr_for_image_block: bool,
    pub merge_tables: bool,
    pub restructure_pages: bool,
    pub layout_nms: bool,
    pub layout_shape_mode: String,
    pub repetition_penalty: f64,
    pub temperature: f64,
}
impl Default for PaddleOptions {
    fn default() -> Self {
        Self {
            markdown_ignore_labels: [
                "header",
                "header_image",
                "footer",
                "footer_image",
                "number",
                "footnote",
                "aside_text",
            ]
            .map(str::to_owned)
            .into(),
            use_chart_recognition: false,
            use_doc_orientation_classify: false,
            use_doc_unwarping: false,
            use_seal_recognition: false,
            use_ocr_for_image_block: false,
            merge_tables: true,
            restructure_pages: true,
            layout_nms: true,
            layout_shape_mode: "auto".into(),
            repetition_penalty: 1.0,
            temperature: 0.0,
        }
    }
}
impl PaddleOptions {
    pub fn payload(&self) -> Result<Value> {
        if !self.repetition_penalty.is_finite() || !self.temperature.is_finite() {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "nonfinite OCR options",
            ));
        }
        let mut value = serde_json::to_value(self)?;
        for (key, value_) in [
            ("promptLabel", json!("ocr")),
            ("useLayoutDetection", json!(true)),
            ("relevelTitles", json!(true)),
            ("topP", json!(1)),
            ("minPixels", json!(147384)),
            ("maxPixels", json!(2822400)),
        ] {
            value[key] = value_;
        }
        Ok(value)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MineruOptions {
    pub is_ocr: bool,
    pub enable_formula: bool,
    pub enable_table: bool,
    pub language: String,
    pub extra_formats: Vec<String>,
}
impl Default for MineruOptions {
    fn default() -> Self {
        Self {
            is_ocr: false,
            enable_formula: true,
            enable_table: true,
            language: "ch".into(),
            extra_formats: vec![],
        }
    }
}
impl MineruOptions {
    pub fn payload(&self, files: &[MineruPart]) -> Result<Value> {
        if files.is_empty()
            || files.len() > 20
            || ![
                "ch",
                "ch_server",
                "en",
                "japan",
                "korean",
                "chinese_cht",
                "ta",
                "te",
                "ka",
                "el",
                "th",
                "latin",
                "arabic",
                "cyrillic",
                "east_slavic",
                "devanagari",
            ]
            .contains(&self.language.as_str())
            || self
                .extra_formats
                .iter()
                .any(|s| !["docx", "html", "latex"].contains(&s.as_str()))
        {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "invalid MinerU options/files",
            ));
        }
        Ok(
            json!({"enable_formula":self.enable_formula,"enable_table":self.enable_table,"language":self.language,"model_version":"vlm","extra_formats":self.extra_formats,"files":files.iter().map(|part|{
                let mut file=json!({"name":part.name(),"data_id":part.data_id,"is_ocr":self.is_ocr});
                if let Some(ranges)=&part.page_ranges {file["page_ranges"]=json!(ranges);}
                file
            }).collect::<Vec<_>>()}),
        )
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Progress {
    pub stage: OcrStage,
    pub done: usize,
    pub total: usize,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OcrStage {
    RequestingUpload,
    Uploading,
    Queued,
    Running,
    Converting,
    Downloading,
    Completed,
}

pub struct OcrOutput {
    pub provider: Provider,
    pub raw: Value,
    pub raw_markdown: String,
    pub structure: Structure,
    pub model: DocumentModel,
    pub assets: BTreeMap<String, Vec<u8>>,
    pub export_zip: Option<Vec<u8>>,
}

pub struct OcrClient {
    client: Client,
    download_client: Client,
    pub poll_interval: Duration,
}
impl OcrClient {
    pub fn new(client: Client) -> Self {
        Self::with_clients(client.clone(), client)
    }
    pub fn with_clients(client: Client, download_client: Client) -> Self {
        Self {
            client,
            download_client,
            poll_interval: Duration::from_secs(5),
        }
    }

    pub async fn paddle(
        &self,
        pdf: &Path,
        url: &str,
        key: &str,
        options: &PaddleOptions,
        token: &CancellationToken,
    ) -> Result<OcrOutput> {
        let bytes = cancellable(token, async { Ok(tokio::fs::read(pdf).await?) }).await?;
        let options = options.clone();
        let payload = tasks::blocking(token, move || {
            validate_pdf(&bytes)?;
            let mut payload = options.payload()?;
            payload["file"] = json!(STANDARD.encode(&bytes));
            payload["fileType"] = json!(0);
            Ok(serde_json::to_vec(&payload)?)
        })
        .await?;
        let endpoint = if url.trim_end_matches('/').ends_with("/layout-parsing") {
            url.trim_end_matches('/').to_owned()
        } else {
            format!("{}/layout-parsing", url.trim_end_matches('/'))
        };
        let response = network::send(
            self.client
                .post(endpoint)
                .header("Authorization", format!("token {key}"))
                .header("Content-Type", "application/json")
                .body(payload),
            token,
        )
        .await?;
        let bytes = network::bytes(response, 512 * 1024 * 1024, token).await?;
        let mut output = tasks::blocking(token, move || {
            let mut response: Value = serde_json::from_slice(&bytes)?;
            if response["errorCode"].as_i64().is_some_and(|c| c != 0) {
                return Err(OtterError::new(
                    ErrorCode::Remote,
                    "PaddleOCR rejected extraction",
                ));
            }
            let raw = response["result"].take();
            paddle_output(raw)
        })
        .await?;
        self.paddle_assets(&mut output, token).await?;
        Ok(output)
    }

    async fn paddle_assets(&self, output: &mut OcrOutput, token: &CancellationToken) -> Result<()> {
        for page in &output.structure.pages {
            for (name, url) in &page.images {
                safe_relative(name)?;
                if output.assets.contains_key(name) {
                    continue;
                }
                let bytes = network::bytes(
                    network::send(self.download_client.get(url), token).await?,
                    64 * 1024 * 1024,
                    token,
                )
                .await?;
                output.assets.insert(name.clone(), bytes);
            }
        }
        Ok(())
    }

    /// 解析一篇 PDF。超过 200 页时按 `page_ranges` 拆成多段，全部完成后按页序
    /// 合并；任一页段失败即返回错误，不发布部分结果。
    #[allow(clippy::too_many_arguments)]
    pub async fn mineru_document(
        &self,
        base: &str,
        key: &str,
        document: &str,
        path: &Path,
        page_count: Option<usize>,
        options: &MineruOptions,
        token: &CancellationToken,
        mut progress: impl FnMut(Progress),
    ) -> Result<OcrOutput> {
        let plan = chunks::plan(page_count, chunks::MINERU_MAX_PAGES);
        let parts: Vec<_> = plan
            .iter()
            .map(|chunk| MineruPart {
                data_id: chunks::data_id(document, chunk, plan.len()),
                path: path.to_owned(),
                page_ranges: chunk.ranges(),
            })
            .collect();
        let mut zips = BTreeMap::new();
        // 单批最多 20 个文件；超长文档的页段分批提交。
        for group in parts.chunks(20) {
            zips.extend(
                self.mineru(base, key, group, options, token, &mut progress)
                    .await?,
            );
        }
        let ranges = plan
            .iter()
            .zip(&parts)
            .map(|(chunk, part)| {
                zips.remove(&part.data_id)
                    .map(|bytes| (*chunk, bytes))
                    .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "MinerU range missing"))
            })
            .collect::<Result<Vec<_>>>()?;
        tasks::blocking(token, move || {
            if ranges.len() == 1 {
                return mineru_package(&ranges[0].1, &[]);
            }
            mineru_package(&chunks::merge_mineru_zips(ranges)?, &[])
        })
        .await
    }

    /// 一次批量请求提交 1..20 个文件，按 `data_id` 收齐结果包；任一文件失败即报错。
    pub async fn mineru(
        &self,
        base: &str,
        key: &str,
        files: &[MineruPart],
        options: &MineruOptions,
        token: &CancellationToken,
        mut progress: impl FnMut(Progress),
    ) -> Result<BTreeMap<String, Vec<u8>>> {
        let payload = options.payload(files)?;
        for part in files {
            let size = tokio::fs::metadata(&part.path).await?.len();
            if size == 0 || size > 200 * 1024 * 1024 {
                return Err(OtterError::new(
                    ErrorCode::InvalidArgument,
                    "invalid OCR file size",
                ));
            }
        }
        progress(Progress {
            stage: OcrStage::RequestingUpload,
            done: 0,
            total: files.len(),
        });
        let response = network::json(
            self.client
                .post(format!("{}/file-urls/batch", base.trim_end_matches('/')))
                .bearer_auth(key)
                .json(&payload),
            token,
        )
        .await?;
        check_mineru(&response)?;
        let batch = response["data"]["batch_id"]
            .as_str()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "missing MinerU batch id"))?;
        files::component(batch)?;
        let urls = response["data"]["file_urls"]
            .as_array()
            .filter(|u| u.len() == files.len())
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "missing MinerU upload URLs"))?;
        for (index, part) in files.iter().enumerate() {
            let url = urls[index]
                .as_str()
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "invalid upload URL"))?;
            let bytes =
                cancellable(token, async { Ok(tokio::fs::read(&part.path).await?) }).await?;
            validate_pdf(&bytes)?;
            network::send(self.download_client.put(url).body(bytes), token).await?;
            progress(Progress {
                stage: OcrStage::Uploading,
                done: index + 1,
                total: files.len(),
            });
        }
        let mut outputs = BTreeMap::new();
        while outputs.len() < files.len() {
            cancellable(token, async {
                tokio::time::sleep(self.poll_interval).await;
                Ok(())
            })
            .await?;
            let response = network::json(
                self.client
                    .get(format!(
                        "{}/extract-results/batch/{batch}",
                        base.trim_end_matches('/')
                    ))
                    .bearer_auth(key),
                token,
            )
            .await?;
            check_mineru(&response)?;
            let results = response["data"]["extract_result"]
                .as_array()
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "missing MinerU results"))?;
            for item in results {
                let Some(id) = item["data_id"]
                    .as_str()
                    .filter(|id| files.iter().any(|part| part.data_id == *id))
                else {
                    continue;
                };
                if outputs.contains_key(id) {
                    continue;
                }
                let stage = match item["state"].as_str() {
                    Some("done") => {
                        let url = item["full_zip_url"].as_str().ok_or_else(|| {
                            OtterError::new(ErrorCode::InvalidData, "missing MinerU ZIP URL")
                        })?;
                        progress(Progress {
                            stage: OcrStage::Downloading,
                            done: outputs.len(),
                            total: files.len(),
                        });
                        let bytes = network::bytes(
                            network::send(self.download_client.get(url), token).await?,
                            1024 * 1024 * 1024,
                            token,
                        )
                        .await?;
                        tasks::check(token)?;
                        outputs.insert(id.to_owned(), bytes);
                        OcrStage::Completed
                    }
                    Some("failed") => {
                        return Err(OtterError::new(
                            ErrorCode::Remote,
                            "MinerU extraction failed",
                        ));
                    }
                    Some("running") => OcrStage::Running,
                    Some("converting") => OcrStage::Converting,
                    _ => OcrStage::Queued,
                };
                progress(Progress {
                    stage,
                    done: outputs.len(),
                    total: files.len(),
                });
            }
        }
        Ok(outputs)
    }
}

/// MinerU 批量请求里的一个文件；长 PDF 的每个页段各占一项，上传同一份文件。
#[derive(Debug, Clone)]
pub struct MineruPart {
    pub data_id: String,
    pub path: std::path::PathBuf,
    pub page_ranges: Option<String>,
}
impl MineruPart {
    fn name(&self) -> String {
        self.path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned()
    }
}

fn paddle_output(mut raw: Value) -> Result<OcrOutput> {
    if let Some(pages) = raw["layoutParsingResults"].as_array_mut() {
        chunks::assemble_paddle_pages(pages);
    }
    let structure = Structure::from_value(&raw)?;
    if structure.pages.is_empty() {
        return Err(OtterError::new(ErrorCode::InvalidData, "empty OCR result"));
    }
    let raw_markdown = structure
        .pages
        .iter()
        .map(|p| p.markdown.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");
    let model = DocumentModel::from_structure(&structure);
    Ok(OcrOutput {
        provider: Provider::Paddleocr,
        raw,
        raw_markdown,
        structure,
        model,
        assets: BTreeMap::new(),
        export_zip: None,
    })
}

fn validate_pdf(bytes: &[u8]) -> Result<()> {
    if !bytes.starts_with(b"%PDF-") || bytes.len() > 200 * 1024 * 1024 {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "invalid OCR PDF",
        ));
    }
    Ok(())
}
fn check_mineru(value: &Value) -> Result<()> {
    if value["success"] == false || value["code"].as_i64().is_some_and(|c| c != 0) {
        let code = if matches!(value["msgCode"].as_str(), Some("A0202" | "A0211")) {
            ErrorCode::Authentication
        } else if value["code"] == -60018 {
            ErrorCode::RateLimited
        } else {
            ErrorCode::Remote
        };
        return Err(OtterError::new(code, "MinerU rejected request"));
    }
    Ok(())
}
fn safe_relative(name: &str) -> Result<()> {
    if name.contains(['\\', ':'])
        || Path::new(name)
            .components()
            .any(|p| !matches!(p, Component::Normal(_)))
        || name.is_empty()
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "unsafe OCR asset path",
        ));
    }
    Ok(())
}

mod artifacts;
pub use artifacts::{mineru_package, publish};
