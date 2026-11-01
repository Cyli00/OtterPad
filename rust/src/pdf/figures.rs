//! Render confirmed OCR figure ownership using PDFium, without rendering whole pages.
use super::{DocumentInfo, PdfService, PixelRect, RenderRequest};
use crate::{
    document::{
        figures::{CaptionRef, FigureSegment, sublabel},
        revision,
        structure::{Structure, is_visual},
    },
    error::{ErrorCode, OtterError, Result},
    tasks::check,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use tokio_util::sync::CancellationToken;

const ZOOM: f32 = 3.0;
const MAX_PIXELS: u64 = 16 * 1024 * 1024;
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VisualRegion {
    #[serde(rename = "page_idx")]
    pub page_index: i64,
    pub bbox: Vec<f64>,
    #[serde(rename = "block_ids")]
    pub block_ids: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FigureAsset {
    pub id: String,
    #[serde(default)]
    pub segment_ids: Vec<String>,
    #[serde(rename = "img", alias = "imagePath")]
    pub image_path: String,
    #[serde(rename = "figure_title", alias = "captionText")]
    pub caption_text: String,
    pub kind: String,
    #[serde(rename = "caption_refs", alias = "captionRefs", default)]
    pub caption_refs: Vec<CaptionRef>,
    #[serde(default, alias = "visualRegions")]
    pub visual_regions: Vec<VisualRegion>,
    #[serde(default, alias = "widthPx")]
    pub width_px: u32,
    #[serde(default, alias = "heightPx")]
    pub height_px: u32,
}
pub struct CroppedFigures {
    pub figures: Vec<FigureAsset>,
    pub assets: BTreeMap<String, Vec<u8>>,
}
struct Raster {
    width: u32,
    height: u32,
    rgba: Vec<u8>,
}

pub(crate) fn directory(document: &std::path::Path) -> Result<std::path::PathBuf> {
    Ok(crate::document::extraction_directory(document)?.join("figures"))
}
pub(crate) fn read_assets(document: &std::path::Path) -> Result<Vec<FigureAsset>> {
    let directory = directory(document)?;
    let manifest = directory.join("figures.json");
    let manifest = if manifest.is_file() {
        manifest
    } else {
        directory.parent().unwrap().join("figures.json")
    };
    if !manifest.is_file() {
        return Ok(Vec::new());
    }
    let value: serde_json::Value = serde_json::from_slice(&std::fs::read(manifest)?)?;
    let entries = value
        .as_array()
        .or_else(|| value["figures"].as_array())
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "figure manifest entries"))?;
    let mut result = Vec::new();
    for entry in entries {
        if !entry.is_object() {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "figure manifest entry",
            ));
        }
        if entry["assignment"]
            .as_str()
            .is_some_and(|s| s != "confirmed")
            || entry["pair_method"] == "visualOnly"
            || entry["pairMethod"] == "visualOnly"
            || entry["caption_source"] == "none"
            || entry["captionSource"] == "none"
        {
            continue;
        }
        let mut entry = entry.clone();
        if entry["id"].as_str().is_none() {
            entry["id"] = revision(&entry.to_string()).into();
        }
        if entry["kind"].as_str().is_none() {
            entry["kind"] = "figure".into();
        }
        let mut asset: FigureAsset = serde_json::from_value(entry)?;
        if !crate::document::figures::usable(&asset.caption_text) {
            continue;
        }
        if asset.segment_ids.is_empty() {
            asset.segment_ids.push(asset.id.clone());
        }
        result.push(asset);
    }
    Ok(result)
}

pub fn render(
    pdf: &mut PdfService,
    info: &DocumentInfo,
    structure: &Structure,
    segments: &[FigureSegment],
    token: &CancellationToken,
    mut progress: impl FnMut(usize, usize),
) -> Result<CroppedFigures> {
    let mut groups: Vec<Vec<&FigureSegment>> = Vec::new();
    for segment in segments {
        let targets: Vec<_> = groups
            .iter()
            .enumerate()
            .filter(|(_, group)| {
                let previous = group.last().unwrap();
                let shared = segment
                    .caption_refs
                    .iter()
                    .any(|r| previous.caption_refs.contains(r));
                let continued = segment.kind == "table"
                    && previous.kind == "table"
                    && segment.page_index == previous.page_index + 1
                    && segment.caption_name == previous.caption_name
                    && continued(&segment.caption_text)
                    && similar_columns(previous, segment);
                shared || continued
            })
            .map(|(index, _)| index)
            .collect();
        if targets.len() == 1 {
            groups[targets[0]].push(segment);
        } else {
            groups.push(vec![segment]);
        }
    }
    let mut output = CroppedFigures {
        figures: Vec::new(),
        assets: BTreeMap::new(),
    };
    let mut done = 0;
    let mut bytes_total = 0usize;
    progress(0, segments.len());
    for group in groups {
        check(token)?;
        let mut rasters = Vec::new();
        let mut regions = Vec::new();
        let mut members = Vec::new();
        let mut captions = Vec::new();
        let mut refs = Vec::new();
        let mut pixels = 0u64;
        for segment in &group {
            check(token)?;
            if let Some(region) = region(segment) {
                let raster = crop(pdf, info, structure, &region, token)?;
                pixels += u64::from(raster.width) * u64::from(raster.height);
                if pixels > MAX_PIXELS {
                    return Err(overflow());
                }
                rasters.push(raster);
                regions.push(region);
                members.push(segment.id.clone());
                if !captions.contains(&segment.caption_text) {
                    captions.push(segment.caption_text.clone());
                }
                for r in &segment.caption_refs {
                    if !refs.contains(r) {
                        refs.push(r.clone());
                    }
                }
            }
            done += 1;
            progress(done, segments.len());
        }
        if rasters.is_empty() {
            continue;
        }
        let raster = combine(rasters, token)?;
        let mut png = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut png, raster.width, raster.height);
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder.write_header().map_err(png_error)?;
            writer.write_image_data(&raster.rgba).map_err(png_error)?;
            writer.finish().map_err(png_error)?;
        }
        bytes_total = bytes_total
            .checked_add(png.len())
            .filter(|n| *n <= 512 * 1024 * 1024)
            .ok_or_else(overflow)?;
        let hash = Sha256::digest(&png)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        let name = format!("{hash}.png");
        output.assets.insert(format!("figures/{name}"), png);
        output.figures.push(FigureAsset {
            id: members[0].clone(),
            segment_ids: members,
            image_path: name,
            caption_text: captions.join(" "),
            kind: group[0].kind.clone(),
            caption_refs: refs,
            visual_regions: regions,
            width_px: raster.width,
            height_px: raster.height,
        });
    }
    check(token)?;
    let source = revision(&serde_json::to_string(structure)?);
    output.assets.insert(
        "figures/figures.json".into(),
        serde_json::to_vec(
            &json!({"algorithm_version":5,"source_version":source,"figures":output.figures}),
        )?,
    );
    Ok(output)
}

fn region(segment: &FigureSegment) -> Option<VisualRegion> {
    let mut bounds = None::<[f64; 4]>;
    let mut ids = Vec::new();
    for block in &segment.blocks {
        if segment.caption_refs.iter().any(|r| {
            r.page_index == segment.page_index && r.block_id.as_deref() == Some(&block.block_id)
        }) || !(is_visual(&block.block_label)
            || sublabel(block)
            || matches!(
                block.block_label.as_str(),
                "figure_annotation" | "vision_footnote"
            ))
        {
            continue;
        }
        let bbox = block.bbox();
        if bbox.len() != 4
            || !bbox.iter().all(|v| v.is_finite())
            || bbox[2] <= bbox[0]
            || bbox[3] <= bbox[1]
        {
            continue;
        }
        bounds = Some(
            bounds
                .map(|b| {
                    [
                        b[0].min(bbox[0]),
                        b[1].min(bbox[1]),
                        b[2].max(bbox[2]),
                        b[3].max(bbox[3]),
                    ]
                })
                .unwrap_or([bbox[0], bbox[1], bbox[2], bbox[3]]),
        );
        ids.push(block.block_id.clone());
    }
    Some(VisualRegion {
        page_index: segment.page_index,
        bbox: bounds?.to_vec(),
        block_ids: ids,
    })
}
fn crop(
    pdf: &mut PdfService,
    info: &DocumentInfo,
    structure: &Structure,
    region: &VisualRegion,
    token: &CancellationToken,
) -> Result<Raster> {
    let page = info
        .pages
        .iter()
        .find(|p| i64::from(p.index) == region.page_index)
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "figure PDF page missing"))?;
    let size = structure
        .pages
        .iter()
        .find(|p| p.page_index == region.page_index)
        .and_then(|p| p.page_size.as_deref())
        .filter(|s| s.len() == 2 && s.iter().all(|n| n.is_finite() && *n > 0.0));
    let fallback = [f64::from(page.width) * 2.0, f64::from(page.height) * 2.0];
    let size = size.unwrap_or(&fallback);
    let full_width = (page.width * ZOOM).ceil() as u32;
    let full_height = (page.height * ZOOM).ceil() as u32;
    let scaled = region
        .bbox
        .iter()
        .enumerate()
        .map(|(i, n)| {
            (n / size[i % 2] * f64::from(if i % 2 == 0 { full_width } else { full_height })).clamp(
                0.0,
                f64::from(if i % 2 == 0 { full_width } else { full_height }),
            ) as u32
        })
        .collect::<Vec<_>>();
    let (left, top, right, bottom) = (scaled[0], scaled[1], scaled[2], scaled[3]);
    if right <= left || bottom <= top {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "figure outside PDF page",
        ));
    }
    let (width, height) = (right - left, bottom - top);
    let pixels = u64::from(width) * u64::from(height);
    if pixels > MAX_PIXELS {
        return Err(overflow());
    }
    let mut rgba = Vec::with_capacity((pixels * 4) as usize);
    let rows = (4 * 1024 * 1024 / width).max(1);
    let mut offset = 0;
    while offset < height {
        check(token)?;
        let band_height = rows.min(height - offset);
        let bitmap = pdf.render(
            &RenderRequest {
                document: info.handle,
                page: page.index,
                scale: ZOOM,
                tile: PixelRect {
                    x: left,
                    y: top + offset,
                    width,
                    height: band_height,
                },
                annotations: false,
            },
            token,
        )?;
        rgba.extend_from_slice(&bitmap.rgba);
        offset += band_height;
    }
    Ok(Raster {
        width,
        height,
        rgba,
    })
}
fn combine(mut images: Vec<Raster>, token: &CancellationToken) -> Result<Raster> {
    if images.len() == 1 {
        return Ok(images.remove(0));
    }
    let width = images.iter().map(|i| i.width).max().unwrap();
    let height = images.iter().map(|i| u64::from(i.height) + 24).sum::<u64>();
    if u64::from(width) * height > MAX_PIXELS {
        return Err(overflow());
    }
    let height = height as u32;
    let mut rgba = [240u8, 242, 245, 255].repeat(width as usize * height as usize);
    let mut offset = 0;
    for image in images {
        check(token)?;
        let x = (width - image.width) / 2;
        for y in 0..image.height {
            let to = ((offset + y) * width + x) as usize * 4;
            let from = (y * image.width) as usize * 4;
            rgba[to..to + image.width as usize * 4]
                .copy_from_slice(&image.rgba[from..from + image.width as usize * 4]);
        }
        offset += image.height + 24;
    }
    if height > 12000 {
        let scale = 12000.0 / f64::from(height);
        let resized_width = (f64::from(width) * scale).ceil().max(1.0) as u32;
        let mut resized = vec![0; resized_width as usize * 12000 * 4];
        for y in 0..12000u32 {
            check(token)?;
            let source_y = (f64::from(y) / scale) as u32;
            for x in 0..resized_width {
                let source_x = ((f64::from(x) / scale) as u32).min(width - 1);
                let from = (source_y as usize * width as usize + source_x as usize) * 4;
                let to = (y as usize * resized_width as usize + x as usize) * 4;
                resized[to..to + 4].copy_from_slice(&rgba[from..from + 4]);
            }
        }
        Ok(Raster {
            width: resized_width,
            height: 12000,
            rgba: resized,
        })
    } else {
        Ok(Raster {
            width,
            height,
            rgba,
        })
    }
}
fn similar_columns(a: &FigureSegment, b: &FigureSegment) -> bool {
    match (region(a), region(b)) {
        (Some(a), Some(b)) => {
            (a.bbox[0] - b.bbox[0]).abs() < 24.0 && (a.bbox[2] - b.bbox[2]).abs() < 24.0
        }
        _ => false,
    }
}
fn continued(text: &str) -> bool {
    let text = text.to_lowercase();
    ["continued", "cont.", "续表", "接上表", "續表"]
        .iter()
        .any(|p| text.contains(p))
}
fn overflow() -> OtterError {
    OtterError::new(ErrorCode::LayoutOverflow, "figure raster size limit")
}
fn png_error(_: png::EncodingError) -> OtterError {
    OtterError::new(ErrorCode::InvalidData, "PNG encoding failed")
}
