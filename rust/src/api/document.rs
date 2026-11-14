use super::Backend;
use crate::{
    document::{self, AnchorRange, Block, figures::CaptionRef},
    error::{ErrorCode, OtterError, Result},
    library,
};

pub struct ReaderFigureBlock {
    pub id: String,
    pub label: String,
    pub bbox: Vec<f64>,
    pub image: Option<String>,
}
pub struct ReaderFigure {
    pub id: String,
    pub page_index: i64,
    pub caption_text: String,
    pub caption_name: String,
    pub caption_refs: Vec<CaptionRef>,
    pub blocks: Vec<ReaderFigureBlock>,
    pub cross_page: bool,
    pub kind: String,
}
/// 图块（含图片型表格）在阅读器中显示的位图。
pub struct ReaderFigureImage {
    pub block_id: String,
    pub path: String,
    pub width_px: u32,
    pub height_px: u32,
}
pub struct ReaderDocument {
    pub version: u32,
    pub blocks: Vec<Block>,
    /// 与 `blocks` 一一对应的译文键；空串表示该块不翻译。
    pub translation_keys: Vec<String>,
    pub figures: Vec<ReaderFigure>,
    pub figure_assets: Vec<crate::pdf::figures::FigureAsset>,
    pub figure_images: Vec<ReaderFigureImage>,
    pub asset_directory: String,
    /// 参考文献条目（大纲的参考文献页）。
    pub references: Vec<crate::document::references::Reference>,
}
/// 新清单按 `segment_ids` 对应图块；0.1.x 清单没有图块 id，按视觉区域的页码与 OCR 块 id 对应。
fn figure_images(
    directory: &std::path::Path,
    blocks: &[Block],
    assets: &[crate::pdf::figures::FigureAsset],
) -> Result<Vec<ReaderFigureImage>> {
    let mut images = Vec::new();
    for block in blocks.iter().filter(|b| {
        b.owner_id.is_none()
            && matches!(
                b.kind,
                document::BlockKind::Figure | document::BlockKind::Table
            )
    }) {
        let asset = assets
            .iter()
            .find(|a| a.segment_ids.contains(&block.id))
            .or_else(|| {
                let source = block.source_block_id.as_deref()?;
                assets.iter().find(|a| {
                    a.visual_regions.iter().any(|r| {
                        Some(r.page_index) == block.page_index
                            && r.block_ids.iter().any(|id| id == source)
                    })
                })
            });
        let Some(asset) = asset else { continue };
        if let Some(path) = crate::pdf::figures::asset_file(directory, &asset.image_path)? {
            images.push(ReaderFigureImage {
                block_id: block.id.clone(),
                path: path.to_string_lossy().into_owned(),
                width_px: asset.width_px,
                height_px: asset.height_px,
            });
        }
    }
    Ok(images)
}
pub(crate) fn directory(storage: &crate::storage::Storage, id: &str) -> Result<std::path::PathBuf> {
    if storage.document(id)?.is_none() {
        return Err(OtterError::new(ErrorCode::NotFound, "document missing"));
    }
    library::document_directory(storage, id)
}
/// 译文展示块，见 [`document::translated_block`]。
#[flutter_rust_bridge::frb(sync)]
pub fn translated_block(source: Block, markdown: String) -> Block {
    document::translated_block(&source, &markdown)
}

impl Backend {
    pub async fn reader_document(&self, document: String) -> Result<ReaderDocument> {
        self.runtime
            .with_storage(&Default::default(), "reader_document", move |storage| {
                let directory = directory(storage, &document)?;
                let model = document::load(&directory)?;
                let figure_assets = crate::pdf::figures::read_assets(&directory)?;
                Ok(ReaderDocument {
                    version: model.version,
                    translation_keys: model
                        .blocks
                        .iter()
                        .map(|b| crate::translate::paragraph::block_key(b).unwrap_or_default())
                        .collect(),
                    figure_images: figure_images(&directory, &model.blocks, &figure_assets)?,
                    references: document::references::references(&model.blocks),
                    blocks: model.blocks,
                    figure_assets,
                    asset_directory: document::extraction_directory(&directory)?
                        .to_string_lossy()
                        .into_owned(),
                    figures: model
                        .figures
                        .into_iter()
                        .map(|f| ReaderFigure {
                            id: f.id,
                            page_index: f.page_index,
                            caption_text: f.caption_text,
                            caption_name: f.caption_name,
                            caption_refs: f.caption_refs,
                            blocks: f
                                .blocks
                                .into_iter()
                                .map(|b| ReaderFigureBlock {
                                    bbox: b.bbox(),
                                    id: b.block_id,
                                    label: b.block_label,
                                    image: b.source_image,
                                })
                                .collect(),
                            cross_page: f.cross_page,
                            kind: f.kind,
                        })
                        .collect(),
                })
            })
            .await
    }
    pub async fn create_anchor(
        &self,
        document: String,
        block: String,
        start: u64,
        end: u64,
    ) -> Result<AnchorRange> {
        self.runtime
            .with_storage(&Default::default(), "create_anchor", move |storage| {
                let model = document::load(&directory(storage, &document)?)?;
                model.anchor(
                    &block,
                    usize::try_from(start).map_err(|_| {
                        OtterError::new(ErrorCode::InvalidArgument, "anchor start range")
                    })?,
                    usize::try_from(end).map_err(|_| {
                        OtterError::new(ErrorCode::InvalidArgument, "anchor end range")
                    })?,
                )
            })
            .await
    }
    pub async fn resolve_anchor(
        &self,
        document: String,
        anchor: AnchorRange,
    ) -> Result<Option<AnchorRange>> {
        self.runtime
            .with_storage(&Default::default(), "resolve_anchor", move |storage| {
                Ok(document::load(&directory(storage, &document)?)?.resolve(&anchor))
            })
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pdf::figures::{FigureAsset, VisualRegion};

    fn figure(id: &str, source: &str) -> Block {
        let mut block = document::DocumentModel::from_markdown("Figure 1. Caption")
            .blocks
            .remove(0);
        block.id = id.into();
        block.kind = document::BlockKind::Figure;
        block.page_index = Some(1);
        block.source_block_id = Some(source.into());
        block
    }

    fn asset(segment: &str, image: &str, region_blocks: &[&str]) -> FigureAsset {
        FigureAsset {
            id: segment.into(),
            segment_ids: vec![segment.into()],
            image_path: image.into(),
            caption_text: "Figure 1. Caption".into(),
            kind: "figure".into(),
            caption_refs: vec![],
            visual_regions: vec![VisualRegion {
                page_index: 1,
                bbox: vec![0.0, 0.0, 1.0, 1.0],
                block_ids: region_blocks.iter().map(|s| (*s).into()).collect(),
            }],
            width_px: 30,
            height_px: 20,
        }
    }

    #[test]
    fn figure_images_match_segment_ids_then_legacy_visual_regions() {
        let root = tempfile::tempdir().unwrap();
        let figures = root.path().join("figures");
        std::fs::create_dir_all(figures.join("generation_a")).unwrap();
        std::fs::write(figures.join("new.png"), b"png").unwrap();
        std::fs::write(figures.join("generation_a/old.png"), b"png").unwrap();
        let blocks = [
            figure("fig-new", "3"),
            figure("fig-old", "7"),
            figure("fig-none", "9"),
        ];
        let assets = [
            asset("fig-new", "new.png", &[]),
            // 0.1.x 清单没有图块 id，读取时以条目哈希补齐，只能按视觉区域对应。
            asset(
                "legacy-hash",
                "/old/root/figures/generation_a/old.png",
                &["5", "7"],
            ),
            asset("fig-none", "missing.png", &[]),
        ];
        let images = figure_images(root.path(), &blocks, &assets).unwrap();
        let found = images
            .iter()
            .map(|i| {
                (
                    i.block_id.as_str(),
                    i.path.rsplit("figures/").next().unwrap(),
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            found,
            [("fig-new", "new.png"), ("fig-old", "generation_a/old.png")]
        );
        assert_eq!((images[0].width_px, images[0].height_px), (30, 20));
    }
}
