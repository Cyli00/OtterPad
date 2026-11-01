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
pub struct ReaderDocument {
    pub version: u32,
    pub blocks: Vec<Block>,
    pub figures: Vec<ReaderFigure>,
    pub figure_assets: Vec<crate::pdf::figures::FigureAsset>,
    pub asset_directory: String,
}
pub(crate) fn directory(storage: &crate::storage::Storage, id: &str) -> Result<std::path::PathBuf> {
    if storage.document(id)?.is_none() {
        return Err(OtterError::new(ErrorCode::NotFound, "document missing"));
    }
    library::document_directory(storage, id)
}
impl Backend {
    pub async fn reader_document(&self, document: String) -> Result<ReaderDocument> {
        self.runtime
            .with_storage(&Default::default(), "reader_document", move |storage| {
                let directory = directory(storage, &document)?;
                let model = document::load(&directory)?;
                Ok(ReaderDocument {
                    version: model.version,
                    blocks: model.blocks,
                    figure_assets: crate::pdf::figures::read_assets(&directory)?,
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
