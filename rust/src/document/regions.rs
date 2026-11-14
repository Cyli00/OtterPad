//! 块在 PDF 页面上的区域：OCR 坐标按该页 `page_size` 换算成 0–1 的页面比例，
//! Flutter 乘以 PDF 页面尺寸即得显示位置，无需知道 OCR 图像分辨率。

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use super::{Block, BlockKind, structure::Structure};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PageRegion {
    pub page: u32,
    pub left: f64,
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
    /// 该区域承载的原文 UTF-16 长度；同一块跨栏/跨页时按它分配译文。
    pub source_length: u64,
}

/// 与 `blocks` 一一对应；没有结构或坐标无效的块得到空列表。
/// 图表根块的区域是图片的视觉框而不是题注文字框，不能用来放译文，也给空列表。
pub fn page_regions(structure: Option<&Structure>, blocks: &[Block]) -> Vec<Vec<PageRegion>> {
    let sizes: BTreeMap<i64, (f64, f64)> = structure
        .map(|s| {
            s.pages
                .iter()
                .filter_map(|p| match p.page_size.as_deref() {
                    Some([w, h]) if w.is_finite() && h.is_finite() && *w > 0.0 && *h > 0.0 => {
                        Some((p.page_index, (*w, *h)))
                    }
                    _ => None,
                })
                .collect()
        })
        .unwrap_or_default();
    blocks
        .iter()
        .map(|block| {
            if matches!(block.kind, BlockKind::Figure | BlockKind::Table) {
                return vec![];
            }
            block
                .source_regions
                .iter()
                .filter_map(|region| {
                    let (width, height) = *sizes.get(&region.page_index)?;
                    let [left, top, right, bottom] = region.bbox.as_slice() else {
                        return None;
                    };
                    let rect = PageRegion {
                        page: u32::try_from(region.page_index).ok()?,
                        left: (left / width).clamp(0.0, 1.0),
                        top: (top / height).clamp(0.0, 1.0),
                        right: (right / width).clamp(0.0, 1.0),
                        bottom: (bottom / height).clamp(0.0, 1.0),
                        source_length: region.source_length as u64,
                    };
                    (rect.right > rect.left && rect.bottom > rect.top).then_some(rect)
                })
                .collect()
        })
        .collect()
}

/// 当前 generation 的 `structure.json`；旧数据没有该文件时返回 None。
pub(crate) fn load_structure(
    directory: &std::path::Path,
) -> crate::error::Result<Option<Structure>> {
    let path = super::extraction_directory(directory)?.join("structure.json");
    if !path.is_file() {
        return Ok(None);
    }
    Ok(Some(serde_json::from_slice(&std::fs::read(path)?)?))
}
