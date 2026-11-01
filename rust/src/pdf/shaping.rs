//! PDF overlay layout using the exact font bytes supplied to the renderer.
//! Advances are shaped for each final line; isolated-character widths cannot
//! represent Arabic joining, Indic clusters, ligatures or bidirectional text.
use super::geometry::{LayoutRegion, PositionedLine};
use crate::error::{ErrorCode, OtterError, Result};
use rustybuzz::{Direction, Face, UnicodeBuffer};
use std::{collections::BTreeSet, ops::Range};
use unicode_bidi::{BidiInfo, Level};
use unicode_script::UnicodeScript;

pub struct ShapedTranslationInput {
    pub text: String,
    pub font_data: Vec<u8>,
    pub font_index: u32,
    pub regions: Vec<LayoutRegion>,
    pub obstacles: Vec<LayoutRegion>,
    pub font_size: f32,
    pub minimum_font_size: f32,
    pub line_height: f32,
}
pub struct ShapedGlyph {
    pub glyph_id: u32,
    pub cluster_start: u32,
    pub cluster_end: u32,
    pub x: f32,
    pub y: f32,
    pub advance: f32,
}
pub struct ShapedLine {
    pub layout: PositionedLine,
    pub right_to_left: bool,
    pub baseline: f32,
    /// Visual order; clusters reference the original text in UTF-16 units.
    pub glyphs: Vec<ShapedGlyph>,
}
struct Shaping {
    width: f32,
    glyphs: Vec<ShapedGlyph>,
}

pub fn layout(input: &ShapedTranslationInput) -> Result<Vec<ShapedLine>> {
    let valid = |region: &LayoutRegion| {
        let r = region.bounds;
        [r.left, r.right, r.top, r.bottom]
            .into_iter()
            .all(f32::is_finite)
            && r.right > r.left
            && r.bottom > r.top
    };
    if input.font_data.len() > 32 * 1024 * 1024
        || input.text.len() > 1024 * 1024
        || !input.font_size.is_finite()
        || !input.minimum_font_size.is_finite()
        || input.minimum_font_size <= 0.0
        || input.font_size < input.minimum_font_size
        || input.font_size > 200.0
        || !input.line_height.is_finite()
        || input.line_height < 1.0
        || input
            .regions
            .iter()
            .chain(&input.obstacles)
            .any(|r| !valid(r))
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "shaped translation layout",
        ));
    }
    let face = Face::from_slice(&input.font_data, input.font_index)
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "translation font face"))?;
    if input.text.is_empty() {
        return Ok(Vec::new());
    }
    let bidi = BidiInfo::new(&input.text, None);
    let breaks: BTreeSet<_> = unicode_linebreak::linebreaks(&input.text)
        .map(|(end, _)| end)
        .collect();
    let mut size = input.font_size;
    loop {
        if let Some(lines) = fit(input, &face, &bidi, &breaks, size)? {
            return Ok(lines);
        }
        if size <= input.minimum_font_size {
            break;
        }
        size = (size - 0.5).max(input.minimum_font_size);
    }
    Err(OtterError::new(
        ErrorCode::LayoutOverflow,
        "shaped translation does not fit",
    ))
}

fn fit(
    input: &ShapedTranslationInput,
    face: &Face<'_>,
    bidi: &BidiInfo<'_>,
    breaks: &BTreeSet<usize>,
    size: f32,
) -> Result<Option<Vec<ShapedLine>>> {
    let mut cursor = 0;
    let mut lines = Vec::new();
    let em = face.units_per_em() as f32;
    let ascender = f32::from(face.ascender()) / em;
    let descender = f32::from(face.descender()) / em;
    let height = size * input.line_height.max(ascender - descender);
    for region in &input.regions {
        let mut top = region.bounds.top;
        while cursor < input.text.len() && top + height <= region.bounds.bottom + 0.001 {
            let mut gaps = vec![(region.bounds.left, region.bounds.right)];
            for obstacle in input.obstacles.iter().filter(|o| {
                o.page == region.page && o.bounds.top < top + height && top < o.bounds.bottom
            }) {
                gaps = gaps
                    .into_iter()
                    .flat_map(|(left, right)| {
                        if obstacle.bounds.left >= right || obstacle.bounds.right <= left {
                            return vec![(left, right)];
                        }
                        let mut out = Vec::new();
                        if obstacle.bounds.left > left {
                            out.push((left, obstacle.bounds.left));
                        }
                        if obstacle.bounds.right < right {
                            out.push((obstacle.bounds.right, right));
                        }
                        out
                    })
                    .collect();
            }
            let Some((left, right)) = gaps
                .into_iter()
                .max_by(|a, b| (a.1 - a.0).total_cmp(&(b.1 - b.0)))
            else {
                top += height;
                continue;
            };
            let paragraph = bidi
                .paragraphs
                .iter()
                .find(|p| p.range.contains(&cursor))
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "translation paragraph"))?;
            let remaining = &input.text[cursor..paragraph.range.end];
            let hard_end = remaining
                .find(['\r', '\n'])
                .map_or(paragraph.range.end, |n| cursor + n);
            let mut chosen = None;
            for end in breaks.range((
                std::ops::Bound::Excluded(cursor),
                std::ops::Bound::Included(hard_end),
            )) {
                let shaped = shape(
                    face,
                    &input.text[cursor..*end],
                    paragraph.level,
                    utf16(&input.text[..cursor]),
                )?;
                if shaped.width * size > right - left + 0.001 {
                    break;
                }
                chosen = Some((*end, shaped));
            }
            // A final paragraph or hard newline need not itself be a soft break.
            if chosen.as_ref().is_none_or(|(end, _)| *end < hard_end) {
                let shaped = shape(
                    face,
                    &input.text[cursor..hard_end],
                    paragraph.level,
                    utf16(&input.text[..cursor]),
                )?;
                if shaped.width * size <= right - left + 0.001 {
                    chosen = Some((hard_end, shaped));
                } else if chosen.is_none() {
                    // Long words can break only between shaped clusters, never
                    // inside a combining sequence or ligature.
                    let cluster_ends: BTreeSet<_> = shaped
                        .glyphs
                        .iter()
                        .map(|g| g.cluster_end as usize)
                        .collect();
                    let offset = utf16(&input.text[..cursor]) as usize;
                    let mut units = offset;
                    for (byte, ch) in input.text[cursor..hard_end].char_indices() {
                        units += ch.len_utf16();
                        if !cluster_ends.contains(&units) {
                            continue;
                        }
                        let end = cursor + byte + ch.len_utf8();
                        let candidate = shape(
                            face,
                            &input.text[cursor..end],
                            paragraph.level,
                            offset as u32,
                        )?;
                        if candidate.width * size > right - left + 0.001 {
                            break;
                        }
                        chosen = Some((end, candidate));
                    }
                }
            }
            let Some((end, mut shaped)) = chosen else {
                top += height;
                continue;
            };
            let hard_break = end == hard_end
                && end < input.text.len()
                && input.text[end..].starts_with(['\r', '\n']);
            let consumed = if hard_break {
                if input.text[end..].starts_with("\r\n") {
                    end + 2
                } else {
                    end + 1
                }
            } else {
                end
            };
            if consumed == cursor {
                top += height;
                continue;
            }
            let width = shaped.width * size;
            let x = if paragraph.level.is_rtl() {
                right - width
            } else {
                left
            };
            let baseline = top + (height - (ascender - descender) * size) / 2.0 + ascender * size;
            for glyph in &mut shaped.glyphs {
                glyph.x = x + glyph.x * size;
                glyph.y = baseline - glyph.y * size;
                glyph.advance *= size;
            }
            lines.push(ShapedLine {
                layout: PositionedLine {
                    page: region.page,
                    text: input.text[cursor..end].to_owned(),
                    start: utf16(&input.text[..cursor]) as usize,
                    end: utf16(&input.text[..consumed]) as usize,
                    left: x,
                    top,
                    width,
                    height,
                    font_size: size,
                    hard_break,
                },
                right_to_left: paragraph.level.is_rtl(),
                baseline,
                glyphs: shaped.glyphs,
            });
            cursor = consumed;
            top += height;
        }
    }
    Ok((cursor == input.text.len()).then_some(lines))
}

fn shape(face: &Face<'_>, text: &str, level: Level, offset: u32) -> Result<Shaping> {
    let mut result = Shaping {
        width: 0.0,
        glyphs: Vec::new(),
    };
    if text.is_empty() {
        return Ok(result);
    }
    let bidi = BidiInfo::new(text, Some(level));
    let (_, runs) = bidi.visual_runs(&bidi.paragraphs[0], 0..text.len());
    let em = face.units_per_em() as f32;
    for run in runs {
        let rtl = bidi.levels[run.start].is_rtl();
        let mut scripts: Vec<Range<usize>> = Vec::new();
        let mut previous = unicode_script::Script::Common;
        for (index, ch) in text[run.clone()].char_indices() {
            let script = ch.script();
            if !matches!(
                script,
                unicode_script::Script::Common | unicode_script::Script::Inherited
            ) {
                if script != previous && previous != unicode_script::Script::Common {
                    scripts.last_mut().unwrap().end = run.start + index;
                    scripts.push(run.start + index..run.end);
                }
                previous = script;
            }
            if scripts.is_empty() {
                scripts.push(run.clone());
            }
        }
        if rtl {
            scripts.reverse();
        }
        for segment in scripts {
            let mut buffer = UnicodeBuffer::new();
            buffer.push_str(&text[segment.clone()]);
            buffer.set_direction(if rtl {
                Direction::RightToLeft
            } else {
                Direction::LeftToRight
            });
            buffer.guess_segment_properties();
            let shaped = rustybuzz::shape(face, &[], buffer);
            let ends: BTreeSet<_> = shaped
                .glyph_infos()
                .iter()
                .map(|info| info.cluster as usize)
                .chain([segment.len()])
                .collect();
            for (info, position) in shaped.glyph_infos().iter().zip(shaped.glyph_positions()) {
                if info.glyph_id == 0 {
                    return Err(OtterError::new(
                        ErrorCode::Unsupported,
                        "translation font lacks a glyph",
                    ));
                }
                let start = segment.start + info.cluster as usize;
                let end = segment.start
                    + ends
                        .range((info.cluster as usize + 1)..)
                        .next()
                        .copied()
                        .unwrap_or(segment.len());
                let advance = position.x_advance as f32 / em;
                result.glyphs.push(ShapedGlyph {
                    glyph_id: info.glyph_id,
                    cluster_start: offset + utf16(&text[..start]),
                    cluster_end: offset + utf16(&text[..end]),
                    x: result.width + position.x_offset as f32 / em,
                    y: position.y_offset as f32 / em,
                    advance,
                });
                result.width += advance;
            }
        }
    }
    Ok(result)
}
fn utf16(text: &str) -> u32 {
    text.encode_utf16().count() as u32
}
