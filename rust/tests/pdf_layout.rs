use otter_core::{
    error::ErrorCode,
    pdf::{
        Rect,
        geometry::{GlyphMetric, LayoutRegion, TranslationLayout, layout_translation},
    },
};

#[test]
fn actual_font_shapes_arabic_ligatures_bidi_clusters_and_reports_missing_glyphs() {
    use otter_core::pdf::shaping::{self, ShapedTranslationInput};
    let font = std::env::var_os("OTTER_TEST_FONT_PATH")
        .map(std::path::PathBuf::from)
        .or_else(|| {
            [
                "/System/Library/Fonts/Supplemental/Arial.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                "C:/Windows/Fonts/arial.ttf",
            ]
            .into_iter()
            .map(std::path::PathBuf::from)
            .find(|path| path.is_file())
        })
        .expect("real Arabic-capable Arial/DejaVu test font; set OTTER_TEST_FONT_PATH");
    let mut input = ShapedTranslationInput {
        text: "لا".into(),
        font_data: std::fs::read(font).unwrap(),
        font_index: 0,
        regions: vec![LayoutRegion {
            page: 0,
            bounds: Rect {
                left: 0.0,
                top: 0.0,
                right: 200.0,
                bottom: 200.0,
            },
        }],
        obstacles: vec![],
        font_size: 12.0,
        minimum_font_size: 12.0,
        line_height: 1.2,
    };
    let lines = shaping::layout(&input).unwrap();
    assert_eq!(lines.len(), 1);
    assert!(lines[0].right_to_left);
    assert_eq!(
        lines[0].glyphs.len(),
        1,
        "lam-alef must be shaped as one ligature"
    );
    assert_eq!(
        (
            lines[0].glyphs[0].cluster_start,
            lines[0].glyphs[0].cluster_end
        ),
        (0, 2)
    );
    assert!((lines[0].layout.left + lines[0].layout.width - 200.0).abs() < 0.01);
    input.text = "\nالعربية English لا\r\nMixed e\u{301} text".into();
    input.regions[0].bounds.right = 70.0;
    input.obstacles.push(LayoutRegion {
        page: 0,
        bounds: Rect {
            left: 0.0,
            top: 0.0,
            right: 20.0,
            bottom: 20.0,
        },
    });
    let lines = shaping::layout(&input).unwrap();
    let mut reconstructed = String::new();
    let units: Vec<_> = input.text.encode_utf16().collect();
    for line in &lines {
        assert!(line.layout.width + line.layout.left <= 70.01);
        assert!(
            line.baseline >= line.layout.top
                && line.baseline <= line.layout.top + line.layout.height
        );
        assert!(line.layout.left >= 20.0 || line.layout.top >= 20.0);
        reconstructed
            .push_str(&String::from_utf16(&units[line.layout.start..line.layout.end]).unwrap());
        for glyph in &line.glyphs {
            assert!(glyph.cluster_start < glyph.cluster_end);
            assert!(
                (glyph.cluster_start as usize) >= line.layout.start
                    && (glyph.cluster_end as usize) <= line.layout.end
            );
        }
    }
    assert_eq!(reconstructed, input.text);
    input.text = "\u{10ffff}".into();
    assert_eq!(
        shaping::layout(&input).err().unwrap().code,
        ErrorCode::Unsupported
    );
    input.font_data.clear();
    assert_eq!(
        shaping::layout(&input).err().unwrap().code,
        ErrorCode::InvalidData
    );
}

#[test]
fn translation_layout_preserves_all_text_avoids_obstacles_and_reports_overflow() {
    let text = "A translated paragraph wraps across pages. 第二段文字。";
    let glyphs = text
        .chars()
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .map(|character| GlyphMetric {
            character,
            advance_em: 0.6,
        })
        .collect();
    let obstacle = LayoutRegion {
        page: 0,
        bounds: Rect {
            left: 35.0,
            top: 0.0,
            right: 65.0,
            bottom: 24.0,
        },
    };
    let input = TranslationLayout {
        text: text.into(),
        regions: vec![
            LayoutRegion {
                page: 0,
                bounds: Rect {
                    left: 0.0,
                    top: 0.0,
                    right: 100.0,
                    bottom: 48.0,
                },
            },
            LayoutRegion {
                page: 1,
                bounds: Rect {
                    left: 0.0,
                    top: 0.0,
                    right: 100.0,
                    bottom: 100.0,
                },
            },
        ],
        obstacles: vec![obstacle.clone()],
        glyphs,
        font_size: 10.0,
        minimum_font_size: 8.0,
        line_height: 1.2,
    };
    let lines = layout_translation(&input).unwrap();
    assert_eq!(
        lines.iter().map(|l| l.text.as_str()).collect::<String>(),
        text
    );
    assert!(lines.iter().any(|l| l.page == 1));
    for line in &lines {
        let rect = Rect {
            left: line.left,
            top: line.top,
            right: line.left + line.width,
            bottom: line.top + line.height,
        };
        assert!(!(line.page == obstacle.page && rect.overlaps(obstacle.bounds)));
        assert!(line.width <= 100.0);
    }
    let mut impossible = input.clone();
    impossible.regions = vec![LayoutRegion {
        page: 0,
        bounds: Rect {
            left: 0.0,
            top: 0.0,
            right: 1.0,
            bottom: 1.0,
        },
    }];
    assert_eq!(
        layout_translation(&impossible).unwrap_err().code,
        ErrorCode::LayoutOverflow
    );
    let mut missing = input;
    missing.glyphs.clear();
    assert_eq!(
        layout_translation(&missing).unwrap_err().code,
        ErrorCode::InvalidArgument
    );
}
