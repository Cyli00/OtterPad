use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::error::{ErrorCode, OtterError, Result};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextRegion {
    pub page_index: i64,
    pub bbox: Vec<f64>,
    pub source_length: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LayoutBlock {
    pub block_id: String,
    pub block_label: String,
    #[serde(rename = "block_bbox")]
    pub raw_bbox: Vec<Value>,
    pub block_content: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group_id: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub global_group_id: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub block_order: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_image: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub caption_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub text_regions: Vec<TextRegion>,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub source_data: Value,
}

impl LayoutBlock {
    pub fn bbox(&self) -> Vec<f64> {
        self.raw_bbox.iter().filter_map(Value::as_f64).collect()
    }

    fn parse(raw: &Value) -> Result<Self> {
        if !raw.is_object() {
            return invalid("layout block is not an object");
        }
        Ok(Self {
            block_id: raw
                .get("block_id")
                .map(|v| {
                    v.as_str()
                        .map(str::to_owned)
                        .unwrap_or_else(|| v.to_string())
                })
                .unwrap_or_default(),
            block_label: string(raw, "block_label"),
            raw_bbox: if bbox(raw.get("block_bbox"), 4).is_some() {
                raw["block_bbox"].as_array().cloned().unwrap_or_default()
            } else {
                vec![]
            },
            block_content: string(raw, "block_content"),
            group_id: raw["group_id"].as_i64(),
            global_group_id: raw["global_group_id"].as_i64(),
            block_order: raw["block_order"].as_i64(),
            parent_id: optional_string(raw, "parent_id"),
            source_image: optional_string(raw, "source_image"),
            caption_kind: optional_string(raw, "caption_kind"),
            text_regions: raw
                .get("text_regions")
                .map(|v| serde_json::from_value(v.clone()))
                .transpose()?
                .unwrap_or_default(),
            source_data: raw
                .get("source_data")
                .filter(|v| v.is_object())
                .unwrap_or(raw)
                .clone(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StructurePage {
    pub page_index: i64,
    pub blocks: Vec<LayoutBlock>,
    pub markdown: String,
    pub page_size: Option<Vec<f64>>,
    pub images: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Structure {
    pub pages: Vec<StructurePage>,
}

fn invalid<T>(detail: &str) -> Result<T> {
    Err(OtterError::new(ErrorCode::InvalidData, detail))
}
fn string(value: &Value, key: &str) -> String {
    value[key].as_str().unwrap_or_default().to_owned()
}
fn optional_string(value: &Value, key: &str) -> Option<String> {
    value[key].as_str().map(str::to_owned)
}
pub(crate) fn bbox(raw: Option<&Value>, length: usize) -> Option<Vec<f64>> {
    let values = raw?.as_array()?;
    if values.len() != length {
        return None;
    }
    let values: Vec<f64> = values.iter().map(Value::as_f64).collect::<Option<_>>()?;
    if values.iter().any(|v| !v.is_finite())
        || (length == 2 && values.iter().any(|v| *v <= 0.0))
        || (length == 4 && (values[2] <= values[0] || values[3] <= values[1]))
    {
        return None;
    }
    Some(values)
}

pub fn is_body(label: &str) -> bool {
    matches!(label, "text" | "paragraph" | "abstract" | "list")
}
pub fn is_visual(label: &str) -> bool {
    matches!(
        label,
        "image" | "chart" | "table" | "image_body" | "chart_body" | "table_body"
    )
}
pub fn is_caption(label: &str) -> bool {
    matches!(
        label,
        "figure_title" | "table_title" | "chart_title" | "image_title" | "caption"
    ) || label.ends_with("_caption")
}

impl Structure {
    pub fn parse(text: &str) -> Result<Self> {
        Self::from_value(&serde_json::from_str(text)?)
    }

    pub fn from_value(root: &Value) -> Result<Self> {
        if root["pdf_info"].is_array() {
            return Self::from_mineru_layout(root);
        }
        let pages = root
            .as_array()
            .or_else(|| root["layoutParsingResults"].as_array())
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "unsupported OCR root"))?;
        if pages.first().is_some_and(Value::is_array) {
            return Self::from_mineru_v2(pages, &[]);
        }
        let mut structure = Self {
            pages: pages
                .iter()
                .enumerate()
                .map(|(i, raw)| {
                    if !raw["prunedResult"]["parsing_res_list"].is_array()
                        && !raw["markdown"]["text"].is_string()
                    {
                        return invalid("unsupported PaddleOCR page");
                    }
                    let pre = &raw["prunedResult"]["doc_preprocessor_res"];
                    let transformed = pre["angle"].as_f64().unwrap_or(0.0) != 0.0
                        || pre["model_settings"]["use_doc_unwarping"] == true;
                    Ok(StructurePage {
                        page_index: raw["page_index"].as_i64().unwrap_or(i as i64),
                        page_size: if transformed {
                            None
                        } else {
                            bbox(raw.get("page_size"), 2).or_else(|| {
                                bbox(
                                    Some(&json!([
                                        raw["prunedResult"]["width"],
                                        raw["prunedResult"]["height"]
                                    ])),
                                    2,
                                )
                            })
                        },
                        markdown: string(&raw["markdown"], "text"),
                        images: raw["markdown"]["images"]
                            .as_object()
                            .map(|m| {
                                m.iter()
                                    .map(|(k, v)| {
                                        (
                                            k.clone(),
                                            v.as_str()
                                                .map(str::to_owned)
                                                .unwrap_or_else(|| v.to_string()),
                                        )
                                    })
                                    .collect()
                            })
                            .unwrap_or_default(),
                        blocks: raw["prunedResult"]["parsing_res_list"]
                            .as_array()
                            .map(|b| b.iter().map(LayoutBlock::parse).collect())
                            .transpose()?
                            .unwrap_or_default(),
                    })
                })
                .collect::<Result<_>>()?,
        };
        if root["_source"] == "mineru" {
            structure.mineru_regions();
        } else {
            structure.paddle_regions();
        }
        Ok(structure)
    }

    pub fn legacy_json(&self, source: Option<&str>) -> Value {
        let mut value = json!({"structure_version":2,"layoutParsingResults":self.pages.iter().map(|p|{
            let mut page=json!({"page_index":p.page_index,"prunedResult":{"parsing_res_list":p.blocks},"markdown":{"text":p.markdown,"images":p.images}});
            if let Some(size)=&p.page_size {page["page_size"]=json!(size);}
            page
        }).collect::<Vec<_>>()});
        if let Some(source) = source {
            value["_source"] = json!(source);
        }
        value
    }
}

mod mineru;
mod regions;
