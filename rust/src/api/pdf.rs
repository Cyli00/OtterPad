use super::Backend;
use crate::{
    error::{ErrorCode, OtterError, Result},
    library,
    pdf::{Bitmap, DocumentInfo, PdfChar, RenderRequest},
    tasks::cancellable,
};

pub fn align_pdf_text(
    source: String,
    characters: Vec<PdfChar>,
    regions: Vec<crate::pdf::geometry::LayoutRegion>,
) -> Result<crate::pdf::geometry::Alignment> {
    crate::pdf::geometry::align_regions(&source, &characters, &regions)
}
pub fn pdf_selection_rectangles(
    characters: Vec<PdfChar>,
    start: u64,
    end: u64,
) -> Result<Vec<crate::pdf::geometry::Rect>> {
    let start = usize::try_from(start)
        .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "selection start range"))?;
    let end = usize::try_from(end)
        .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "selection end range"))?;
    Ok(crate::pdf::geometry::selection_rects(
        &characters,
        start,
        end,
    ))
}
pub fn search_pdf_text(
    characters: Vec<PdfChar>,
    query: String,
    case_sensitive: bool,
) -> Vec<crate::pdf::geometry::SearchHit> {
    crate::pdf::geometry::search(&characters, &query, case_sensitive)
}
pub fn hit_test_pdf(characters: Vec<PdfChar>, x: f32, y: f32, tolerance: f32) -> Option<u32> {
    crate::pdf::geometry::hit_test(&characters, x, y, tolerance)
}
pub fn layout_pdf_translation(
    input: crate::pdf::geometry::TranslationLayout,
) -> Result<Vec<crate::pdf::geometry::PositionedLine>> {
    crate::pdf::geometry::layout_translation(&input)
}

pub fn layout_shaped_pdf_translation(
    input: crate::pdf::shaping::ShapedTranslationInput,
) -> Result<Vec<crate::pdf::shaping::ShapedLine>> {
    crate::pdf::shaping::layout(&input)
}

impl Backend {
    pub async fn open_pdf(
        &self,
        document: String,
        password: Option<String>,
        task_id: String,
    ) -> Result<DocumentInfo> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let token = task.token.clone();
        self.runtime
            .call(&task.token, "open_pdf", move |state| {
                let storage = state.storage()?;
                if storage.document(&document)?.is_none() {
                    return Err(OtterError::new(ErrorCode::NotFound, "PDF document missing"));
                }
                let path = library::document_directory(storage, &document)?.join("source.pdf");
                let info = state.pdf()?.open(&path, password.as_deref(), &token)?;
                state.pdf_documents.insert(info.handle, document);
                Ok(info)
            })
            .await
    }
    pub async fn close_pdf(&self, handle: u64) -> Result<bool> {
        let _lease = self.runtime.operations.read().await;
        self.runtime
            .call(&Default::default(), "close_pdf", move |state| {
                state.pdf_documents.remove(&handle);
                state.pdf()?.close(handle)
            })
            .await
    }
    pub async fn render_pdf_tile(&self, request: RenderRequest, task_id: String) -> Result<Bitmap> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let token = task.token.clone();
        self.runtime
            .call(&task.token, "render_pdf_tile", move |state| {
                state.pdf()?.render(&request, &token)
            })
            .await
    }
    pub async fn pdf_characters(
        &self,
        handle: u64,
        page: u32,
        task_id: String,
    ) -> Result<Vec<PdfChar>> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let token = task.token.clone();
        self.runtime
            .call(&task.token, "pdf_characters", move |state| {
                state.pdf()?.characters(handle, page, &token)
            })
            .await
    }
    /// 单页搜索（不区分大小写）。Dart 逐页调用，字符不跨 FFI，渲染请求可插在页与页之间。
    pub async fn search_pdf_page(
        &self,
        handle: u64,
        page: u32,
        query: String,
        task_id: String,
    ) -> Result<Vec<crate::pdf::geometry::SearchHit>> {
        let task = self.runtime.tasks.begin(task_id)?;
        let _lease = cancellable(&task.token, async {
            Ok(self.runtime.operations.read().await)
        })
        .await?;
        let token = task.token.clone();
        self.runtime
            .call(&task.token, "search_pdf_page", move |state| {
                let chars = state.pdf()?.characters(handle, page, &token)?;
                Ok(crate::pdf::geometry::search(&chars, &query, false))
            })
            .await
    }
}
