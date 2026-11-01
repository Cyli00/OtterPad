pub mod figures;
pub mod geometry;
pub mod shaping;

use std::{
    collections::BTreeMap,
    path::Path,
    sync::{Arc, Mutex},
};

use pdfium_render::prelude::*;
use serde::{Deserialize, Serialize};
use tokio_util::sync::CancellationToken;

use crate::{
    error::{ErrorCode, OtterError, Result},
    tasks,
};
pub use geometry::Rect;

// PDFium has process-global state. Keep compound operations and document drops
// serialized, in addition to pdfium-render's per-FFI-call thread-safe wrapper.
static PDF_LOCK: Mutex<()> = Mutex::new(());
self_cell::self_cell!(
    struct DocumentCell {
        owner: Arc<Pdfium>,
        #[not_covariant]
        dependent: PdfDocument,
    }
);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageInfo {
    pub index: u32,
    pub width: f32,
    pub height: f32,
    pub rotation: u16,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentInfo {
    pub handle: u64,
    pub pages: Vec<PageInfo>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct PixelRect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderRequest {
    pub document: u64,
    pub page: u32,
    pub scale: f32,
    pub tile: PixelRect,
    pub annotations: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bitmap {
    pub tile: PixelRect,
    pub scale: f32,
    pub rgba: Vec<u8>,
    pub from_cache: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfChar {
    pub page: u32,
    pub index: u32,
    pub utf16_start: usize,
    pub utf16_end: usize,
    pub text: String,
    pub bounds: Rect,
}
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct CacheKey {
    document: u64,
    page: u32,
    width: i32,
    height: i32,
    tile: PixelRect,
    annotations: bool,
}

pub struct PdfService {
    engine: Arc<Pdfium>,
    documents: BTreeMap<u64, DocumentCell>,
    next_handle: u64,
    cache: BTreeMap<CacheKey, (u64, Bitmap)>,
    cache_bytes: usize,
    cache_limit: usize,
    tick: u64,
}

fn pdf_error(error: PdfiumError) -> OtterError {
    OtterError::new(ErrorCode::Pdf, format!("{error:?}"))
}
fn lock() -> Result<std::sync::MutexGuard<'static, ()>> {
    PDF_LOCK
        .lock()
        .map_err(|_| OtterError::new(ErrorCode::Pdf, "PDF lock poisoned"))
}

impl PdfService {
    pub fn new(library: &Path, cache_limit: usize) -> Result<Self> {
        let _lock = lock()?;
        let bindings = Pdfium::bind_to_library(library).map_err(pdf_error)?;
        Ok(Self {
            engine: Arc::new(Pdfium::new(bindings)),
            documents: BTreeMap::new(),
            next_handle: 1,
            cache: BTreeMap::new(),
            cache_bytes: 0,
            cache_limit,
            tick: 0,
        })
    }

    pub fn open(
        &mut self,
        path: &Path,
        password: Option<&str>,
        token: &CancellationToken,
    ) -> Result<DocumentInfo> {
        tasks::check(token)?;
        let _lock = lock()?;
        let cell = DocumentCell::try_new(self.engine.clone(), |engine| {
            engine.load_pdf_from_file(path, password)
        })
        .map_err(pdf_error)?;
        let pages = cell.with_dependent(|_, document| -> Result<Vec<PageInfo>> {
            let mut pages = Vec::new();
            for (index, page) in document.pages().iter().enumerate() {
                tasks::check(token)?;
                let rotation = match page.rotation().map_err(pdf_error)? {
                    PdfPageRenderRotation::None => 0,
                    PdfPageRenderRotation::Degrees90 => 90,
                    PdfPageRenderRotation::Degrees180 => 180,
                    PdfPageRenderRotation::Degrees270 => 270,
                };
                pages.push(PageInfo {
                    index: index as u32,
                    width: page.width().value,
                    height: page.height().value,
                    rotation,
                });
            }
            Ok(pages)
        })?;
        let handle = self.next_handle;
        self.next_handle = self
            .next_handle
            .checked_add(1)
            .ok_or_else(|| OtterError::new(ErrorCode::Conflict, "PDF handle exhausted"))?;
        self.documents.insert(handle, cell);
        Ok(DocumentInfo { handle, pages })
    }

    pub fn close(&mut self, handle: u64) -> Result<bool> {
        let _lock = lock()?;
        let removed = self.documents.remove(&handle).is_some();
        self.cache.retain(|key, (_, bitmap)| {
            if key.document == handle {
                self.cache_bytes -= bitmap.rgba.len();
                false
            } else {
                true
            }
        });
        Ok(removed)
    }

    pub fn close_all(&mut self) -> Result<()> {
        let _lock = lock()?;
        self.documents.clear();
        self.cache.clear();
        self.cache_bytes = 0;
        Ok(())
    }

    fn with_document<T>(
        &self,
        handle: u64,
        action: impl for<'a> FnOnce(&PdfDocument<'a>) -> Result<T>,
    ) -> Result<T> {
        self.documents
            .get(&handle)
            .ok_or_else(|| OtterError::new(ErrorCode::NotFound, "PDF handle missing"))?
            .with_dependent(|_, document| action(document))
    }

    pub fn metadata(&self, handle: u64) -> Result<crate::library::metadata::PdfProperties> {
        let _lock = lock()?;
        self.with_document(handle, |document| {
            let value = |tag| {
                document
                    .metadata()
                    .get(tag)
                    .map(|value| value.value().to_owned())
            };
            Ok(crate::library::metadata::PdfProperties {
                title: value(PdfDocumentMetadataTagType::Title),
                author: value(PdfDocumentMetadataTagType::Author),
                subject: value(PdfDocumentMetadataTagType::Subject),
                keywords: value(PdfDocumentMetadataTagType::Keywords),
            })
        })
    }

    pub fn render(&mut self, request: &RenderRequest, token: &CancellationToken) -> Result<Bitmap> {
        tasks::check(token)?;
        let _lock = lock()?;
        let scale = request.scale;
        let tile = request.tile;
        if !scale.is_finite()
            || scale <= 0.0
            || tile.width == 0
            || tile.height == 0
            || u64::from(tile.width) * u64::from(tile.height) * 4 > 16 * 1024 * 1024
        {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "invalid PDF tile/scale",
            ));
        }
        let scale = (scale * 64.0).round().max(1.0) / 64.0;
        let (width, height) = self.with_document(request.document, |document| {
            let page = document
                .pages()
                .get(request.page.try_into().map_err(|_| {
                    OtterError::new(ErrorCode::InvalidArgument, "PDF page index overflow")
                })?)
                .map_err(pdf_error)?;
            let width = (page.width().value * scale).ceil();
            let height = (page.height().value * scale).ceil();
            if !width.is_finite()
                || !height.is_finite()
                || width > i32::MAX as f32
                || height > i32::MAX as f32
            {
                return Err(OtterError::new(
                    ErrorCode::InvalidArgument,
                    "PDF render dimensions overflow",
                ));
            }
            Ok((width as i32, height as i32))
        })?;
        if u64::from(tile.x) + u64::from(tile.width) > width as u64
            || u64::from(tile.y) + u64::from(tile.height) > height as u64
        {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "PDF tile outside page",
            ));
        }
        let key = CacheKey {
            document: request.document,
            page: request.page,
            width,
            height,
            tile,
            annotations: request.annotations,
        };
        self.tick = self.tick.wrapping_add(1);
        if let Some((tick, bitmap)) = self.cache.get_mut(&key) {
            *tick = self.tick;
            let mut bitmap = bitmap.clone();
            bitmap.from_cache = true;
            return Ok(bitmap);
        }
        let rgba = self.with_document(request.document, |document| {
            let page = document
                .pages()
                .get(request.page.try_into().map_err(|_| {
                    OtterError::new(ErrorCode::InvalidArgument, "PDF page index overflow")
                })?)
                .map_err(pdf_error)?;
            let mut bitmap =
                PdfBitmap::empty(tile.width as i32, tile.height as i32, PdfBitmapFormat::BGRA)
                    .map_err(pdf_error)?;
            let config = PdfRenderConfig::new()
                .set_target_size(width, height)
                .set_origin(-(tile.x as i32), -(tile.y as i32))
                .render_annotations(request.annotations);
            page.render_into_bitmap_with_config(&mut bitmap, &config)
                .map_err(pdf_error)?;
            Ok(bitmap.as_rgba_bytes())
        })?;
        tasks::check(token)?;
        if rgba.len() != tile.width as usize * tile.height as usize * 4 {
            return Err(OtterError::new(
                ErrorCode::Pdf,
                "unexpected PDF bitmap stride",
            ));
        }
        let bitmap = Bitmap {
            tile,
            scale,
            rgba,
            from_cache: false,
        };
        if bitmap.rgba.len() <= self.cache_limit {
            while self.cache_bytes + bitmap.rgba.len() > self.cache_limit {
                let key = self
                    .cache
                    .iter()
                    .min_by_key(|(_, v)| v.0)
                    .map(|(k, _)| k.clone());
                if let Some(key) = key {
                    if let Some((_, removed)) = self.cache.remove(&key) {
                        self.cache_bytes -= removed.rgba.len();
                    }
                } else {
                    break;
                }
            }
            self.cache_bytes += bitmap.rgba.len();
            self.cache.insert(key, (self.tick, bitmap.clone()));
        }
        Ok(bitmap)
    }

    pub fn cache_bytes(&self) -> usize {
        self.cache_bytes
    }
    pub fn clear_cache(&mut self) {
        self.cache.clear();
        self.cache_bytes = 0;
    }

    pub fn characters(
        &self,
        handle: u64,
        index: u32,
        token: &CancellationToken,
    ) -> Result<Vec<PdfChar>> {
        tasks::check(token)?;
        let _lock = lock()?;
        self.with_document(handle, |document| {
            let page = document
                .pages()
                .get(index.try_into().map_err(|_| {
                    OtterError::new(ErrorCode::InvalidArgument, "PDF page index overflow")
                })?)
                .map_err(pdf_error)?;
            let text = page.text().map_err(pdf_error)?;
            let chars = text.chars();
            let mut result = Vec::with_capacity(chars.len());
            let mut offset = 0;
            let config = PdfRenderConfig::new().scale_page_by_factor(1000.0);
            for character in chars.iter() {
                tasks::check(token)?;
                let value = character.unicode_string().unwrap_or_default();
                let bounds = character
                    .tight_bounds()
                    .or_else(|_| character.loose_bounds())
                    .map_err(pdf_error)?;
                let corners = [
                    (bounds.left(), bounds.bottom()),
                    (bounds.left(), bounds.top()),
                    (bounds.right(), bounds.bottom()),
                    (bounds.right(), bounds.top()),
                ];
                let mut points = Vec::new();
                for (x, y) in corners {
                    let (x, y) = page.points_to_pixels(x, y, &config).map_err(pdf_error)?;
                    points.push((x as f32 / 1000.0, y as f32 / 1000.0));
                }
                let bounds = Rect {
                    left: points.iter().map(|p| p.0).fold(f32::INFINITY, f32::min),
                    top: points.iter().map(|p| p.1).fold(f32::INFINITY, f32::min),
                    right: points.iter().map(|p| p.0).fold(f32::NEG_INFINITY, f32::max),
                    bottom: points.iter().map(|p| p.1).fold(f32::NEG_INFINITY, f32::max),
                };
                let end = offset + value.encode_utf16().count();
                result.push(PdfChar {
                    page: index,
                    index: character.index() as u32,
                    utf16_start: offset,
                    utf16_end: end,
                    text: value,
                    bounds,
                });
                offset = end;
            }
            Ok(result)
        })
    }
}

impl Drop for PdfService {
    fn drop(&mut self) {
        if let Ok(_lock) = PDF_LOCK.lock() {
            self.documents.clear();
        }
    }
}
