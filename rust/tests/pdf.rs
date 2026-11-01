use otter_core::{
    error::ErrorCode,
    pdf::{PdfService, PixelRect, RenderRequest},
};
use tokio_util::sync::CancellationToken;

#[test]
fn real_pdfium_renders_tiles_extracts_rotated_geometry_and_enforces_cache_bounds() {
    let library = std::env::var_os("PDFIUM_LIBRARY_PATH")
        .expect("PDFIUM_LIBRARY_PATH is required; run scripts/fetch_pdfium.py --target host first");
    let token = CancellationToken::new();
    let mut service = PdfService::new(std::path::Path::new(&library), 64_000).unwrap();
    let info = service
        .open(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests/fixtures/two_pages.pdf")
                .as_path(),
            None,
            &token,
        )
        .unwrap();
    assert_eq!(info.pages.len(), 2);
    assert_eq!((info.pages[0].width, info.pages[0].height), (300.0, 200.0));
    assert_eq!(
        (
            info.pages[1].width,
            info.pages[1].height,
            info.pages[1].rotation
        ),
        (200.0, 300.0, 90)
    );
    for page in 0..2 {
        let chars = service.characters(info.handle, page, &token).unwrap();
        let text = chars.iter().map(|c| c.text.as_str()).collect::<String>();
        assert!(text.contains("OtterPad PDF test"));
        let hits = otter_core::pdf::geometry::search(&chars, "PDF", false);
        assert_eq!(hits.len(), 1);
        assert!(!hits[0].rectangles.is_empty());
        let dimensions = &info.pages[page as usize];
        let full = service
            .render(
                &RenderRequest {
                    document: info.handle,
                    page,
                    scale: 1.0,
                    tile: PixelRect {
                        x: 0,
                        y: 0,
                        width: dimensions.width as u32,
                        height: dimensions.height as u32,
                    },
                    annotations: false,
                },
                &token,
            )
            .unwrap();
        assert!(
            full.rgba
                .as_chunks::<4>()
                .0
                .iter()
                .any(|p| p[0] != 255 || p[1] != 255 || p[2] != 255)
        );
        let first = chars.iter().find(|c| c.text == "O").unwrap();
        let alignment = otter_core::pdf::geometry::align_region(
            "OtterPad PDF test",
            &chars,
            otter_core::pdf::Rect {
                left: 0.0,
                top: 0.0,
                right: dimensions.width,
                bottom: dimensions.height,
            },
        )
        .unwrap();
        assert!(alignment.located);
        assert_eq!(alignment.confidence, 1.0);
        assert_eq!(
            otter_core::pdf::geometry::hit_test(
                &chars,
                (first.bounds.left + first.bounds.right) / 2.0,
                (first.bounds.top + first.bounds.bottom) / 2.0,
                0.0
            ),
            Some(first.index)
        );
        assert!(first.bounds.valid());
        assert!(
            first.bounds.left >= 0.0
                && first.bounds.right <= dimensions.width
                && first.bounds.top >= 0.0
                && first.bounds.bottom <= dimensions.height
        );
        let mut ink = false;
        for y in first.bounds.top.floor() as u32..first.bounds.bottom.ceil() as u32 {
            for x in first.bounds.left.floor() as u32..first.bounds.right.ceil() as u32 {
                let index = ((y * full.tile.width + x) * 4) as usize;
                if full.rgba[index..index + 3] != [255, 255, 255] {
                    ink = true;
                }
            }
        }
        assert!(
            ink,
            "character geometry missed rendered glyph on page {page}"
        );
        let request = RenderRequest {
            document: info.handle,
            page,
            scale: 1.0,
            tile: PixelRect {
                x: 32,
                y: 40,
                width: 100,
                height: 80,
            },
            annotations: false,
        };
        let tile = service.render(&request, &token).unwrap();
        for y in 0..80u32 {
            let full_start = (((y + 40) * full.tile.width + 32) * 4) as usize;
            let tile_start = (y * 100 * 4) as usize;
            assert_eq!(
                tile.rgba[tile_start..tile_start + 400],
                full.rgba[full_start..full_start + 400],
                "tile/full raster differs on page {page}, row {y}"
            );
        }
        let cached = service.render(&request, &token).unwrap();
        assert!(cached.from_cache);
        assert_eq!(cached.rgba, tile.rgba);
        assert!(service.cache_bytes() <= 64_000);
    }
    let cancelled = CancellationToken::new();
    cancelled.cancel();
    assert_eq!(
        service
            .characters(info.handle, 0, &cancelled)
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
    assert!(service.close(info.handle).unwrap());
    assert_eq!(service.cache_bytes(), 0);
    assert_eq!(
        service.characters(info.handle, 0, &token).unwrap_err().code,
        ErrorCode::NotFound
    );
}
