use otter_core::pdf::{PdfService, PixelRect, RenderRequest};
use tokio_util::sync::CancellationToken;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if !(2..=3).contains(&args.len()) {
        return Err("expected PDFium library path, PDF path, and optional OCR JSON path".into());
    }
    let token = CancellationToken::new();
    let mut service = PdfService::new(std::path::Path::new(&args[0]), 8 * 1024 * 1024)?;
    let info = service.open(std::path::Path::new(&args[1]), None, &token)?;
    let mut character_count = 0;
    let mut all_chars = Vec::new();
    for page in &info.pages {
        let chars = service.characters(info.handle, page.index, &token)?;
        character_count += chars.len();
        all_chars.extend(chars);
        let request = RenderRequest {
            document: info.handle,
            page: page.index,
            scale: 1.0,
            tile: PixelRect {
                x: 0,
                y: 0,
                width: (page.width as u32).min(256),
                height: (page.height as u32).min(256),
            },
            annotations: false,
        };
        let first = service.render(&request, &token)?;
        let second = service.render(&request, &token)?;
        if first.rgba != second.rgba || !second.from_cache {
            return Err("PDF cache did not preserve rendered bytes".into());
        }
    }
    println!(
        "{} pages, {} characters; real tiles and cache verified, {} cached bytes",
        info.pages.len(),
        character_count,
        service.cache_bytes()
    );
    if let Some(path) = args.get(2) {
        use otter_core::{
            document::{
                plain_text,
                structure::{Structure, is_body},
            },
            pdf::{
                Rect,
                geometry::{LayoutRegion, align_regions},
            },
        };
        let structure = Structure::parse(&std::fs::read_to_string(path)?)?;
        let mut attempted = 0;
        let mut aligned = 0;
        for page in &structure.pages {
            for block in page
                .blocks
                .iter()
                .filter(|b| is_body(&b.block_label) && !b.block_content.trim().is_empty())
            {
                let mut regions = Vec::new();
                let source_regions = if block.text_regions.is_empty() {
                    vec![otter_core::document::structure::TextRegion {
                        page_index: page.page_index,
                        bbox: block.bbox(),
                        source_length: 0,
                    }]
                } else {
                    block.text_regions.clone()
                };
                for region in source_regions {
                    let Some(size) = structure
                        .pages
                        .iter()
                        .find(|p| p.page_index == region.page_index)
                        .and_then(|p| p.page_size.as_ref())
                    else {
                        continue;
                    };
                    let Some(info) = info.pages.get(region.page_index as usize) else {
                        continue;
                    };
                    if region.bbox.len() != 4 {
                        continue;
                    }
                    regions.push(LayoutRegion {
                        page: region.page_index as u32,
                        bounds: Rect {
                            left: region.bbox[0] as f32 / size[0] as f32 * info.width,
                            top: region.bbox[1] as f32 / size[1] as f32 * info.height,
                            right: region.bbox[2] as f32 / size[0] as f32 * info.width,
                            bottom: region.bbox[3] as f32 / size[1] as f32 * info.height,
                        },
                    });
                }
                if regions.is_empty() {
                    continue;
                }
                attempted += 1;
                let result =
                    align_regions(&plain_text(&block.block_content), &all_chars, &regions)?;
                if result.located {
                    aligned += 1;
                }
            }
        }
        if attempted > 0 && aligned == 0 {
            return Err("no real OCR paragraph aligned to PDF glyphs".into());
        }
        println!("{aligned}/{attempted} OCR paragraphs aligned to actual PDF glyphs");
    }
    Ok(())
}
