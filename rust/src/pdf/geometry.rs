use super::PdfChar;
use crate::error::{ErrorCode, OtterError, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Rect {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Alignment {
    pub located: bool,
    pub confidence: f32,
    pub characters: Vec<AlignedChar>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlignedChar {
    pub page: u32,
    pub source_start: usize,
    pub source_end: usize,
    pub pdf_index: u32,
    pub pdf_start: usize,
    pub pdf_end: usize,
    pub bounds: Rect,
}

fn normalized_chars(text: &str) -> Vec<(char, usize, usize)> {
    let mut offset = 0;
    let mut result = Vec::new();
    for ch in text.chars() {
        let end = offset + ch.len_utf16();
        if !ch.is_whitespace() && !matches!(ch, '\u{00ad}' | '\u{200b}' | '-' | '‐' | '‑') {
            let ch = match ch {
                '‘' | '’' => '\'',
                '“' | '”' => '"',
                _ => ch,
            };
            for value in ch.to_lowercase() {
                result.push((value, offset, end));
            }
        }
        offset = end;
    }
    result
}

/// Align only against actual PDF glyphs in the OCR region. A partial OCR/PDF
/// mismatch produces partial evidence, never invented character rectangles.
pub fn align_region(source: &str, chars: &[PdfChar], region: Rect) -> Result<Alignment> {
    align_regions(
        source,
        chars,
        &[LayoutRegion {
            page: chars.first().map_or(0, |c| c.page),
            bounds: region,
        }],
    )
}

pub fn align_regions(
    source: &str,
    chars: &[PdfChar],
    regions: &[LayoutRegion],
) -> Result<Alignment> {
    if regions.iter().any(|r| !r.bounds.valid()) {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "invalid OCR alignment region",
        ));
    }
    let source = normalized_chars(source);
    let mut pdf = Vec::new();
    let mut visited = std::collections::BTreeSet::new();
    for region in regions {
        for ch in chars.iter().filter(|c| {
            c.page == region.page
                && c.bounds.valid()
                && region.bounds.contains(
                    (c.bounds.left + c.bounds.right) / 2.0,
                    (c.bounds.top + c.bounds.bottom) / 2.0,
                )
        }) {
            if !visited.insert((ch.page, ch.index)) {
                continue;
            }
            for (value, _, _) in normalized_chars(&ch.text) {
                pdf.push((value, ch));
            }
        }
    }
    let empty = || Alignment {
        located: false,
        confidence: 0.0,
        characters: vec![],
    };
    if source.is_empty() || pdf.is_empty() {
        return Ok(empty());
    }
    let exact: Vec<_> = pdf
        .windows(source.len())
        .enumerate()
        .filter(|(_, w)| w.iter().zip(&source).all(|(p, s)| p.0 == s.0))
        .map(|(i, _)| i)
        .take(2)
        .collect();
    let pairs = if exact.len() == 1 {
        (0..source.len())
            .map(|i| (i, exact[0] + i))
            .collect::<Vec<_>>()
    } else if exact.len() > 1 {
        return Ok(empty());
    } else {
        let rows = source.len() + 1;
        let columns = pdf.len() + 1;
        if rows
            .checked_mul(columns)
            .is_none_or(|cells| cells > 4_000_000)
            || source.len() > u16::MAX as usize
            || pdf.len() > u16::MAX as usize
        {
            return Ok(empty());
        }
        let mut scores = vec![0u16; rows * columns];
        for i in 1..rows {
            for j in 1..columns {
                scores[i * columns + j] = if source[i - 1].0 == pdf[j - 1].0 {
                    scores[(i - 1) * columns + j - 1] + 1
                } else {
                    scores[(i - 1) * columns + j].max(scores[i * columns + j - 1])
                };
            }
        }
        let (mut i, mut j) = (source.len(), pdf.len());
        let mut pairs = Vec::new();
        while i > 0 && j > 0 {
            if source[i - 1].0 == pdf[j - 1].0 {
                pairs.push((i - 1, j - 1));
                i -= 1;
                j -= 1;
            } else if scores[(i - 1) * columns + j] >= scores[i * columns + j - 1] {
                i -= 1;
            } else {
                j -= 1;
            }
        }
        pairs.reverse();
        pairs
    };
    let confidence = pairs.len() as f32 / source.len() as f32;
    if confidence < 0.6 {
        return Ok(Alignment {
            confidence,
            ..empty()
        });
    }
    let mut characters = Vec::new();
    for (s, p) in pairs {
        let glyph = pdf[p].1;
        let (_, start, end) = source[s];
        if characters
            .last()
            .is_some_and(|a: &AlignedChar| a.source_start == start && a.pdf_index == glyph.index)
        {
            continue;
        }
        characters.push(AlignedChar {
            page: glyph.page,
            source_start: start,
            source_end: end,
            pdf_index: glyph.index,
            pdf_start: glyph.utf16_start,
            pdf_end: glyph.utf16_end,
            bounds: glyph.bounds,
        });
    }
    Ok(Alignment {
        located: true,
        confidence,
        characters,
    })
}

pub fn selection_rects(chars: &[PdfChar], start: usize, end: usize) -> Vec<Rect> {
    let mut result: Vec<Rect> = Vec::new();
    for character in chars
        .iter()
        .filter(|c| c.utf16_start < end && c.utf16_end > start && c.bounds.valid())
    {
        let b = character.bounds;
        if let Some(previous) = result.last_mut().filter(|a| {
            a.top < b.bottom
                && b.top < a.bottom
                && b.left >= a.left
                && b.left - a.right <= a.height().max(b.height()) * 1.5
        }) {
            *previous = previous.union(b);
        } else {
            result.push(b);
        }
    }
    result
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchHit {
    pub start: usize,
    pub end: usize,
    pub rectangles: Vec<Rect>,
}
pub fn search(chars: &[PdfChar], query: &str, case_sensitive: bool) -> Vec<SearchHit> {
    if query.is_empty() {
        return vec![];
    }
    let mut text = String::new();
    let mut offsets = BTreeMap::new();
    for c in chars {
        let value = if case_sensitive {
            c.text.clone()
        } else {
            c.text.to_lowercase()
        };
        for ch in value.chars() {
            offsets.insert(text.len(), (c.utf16_start, c.utf16_end));
            text.push(ch);
        }
    }
    let query = if case_sensitive {
        query.to_owned()
    } else {
        query.to_lowercase()
    };
    let mut hits = Vec::new();
    for (start, matched) in text.match_indices(&query) {
        let Some((_, last)) = offsets.range(start..start + matched.len()).next_back() else {
            continue;
        };
        let Some(first) = offsets.get(&start) else {
            continue;
        };
        hits.push(SearchHit {
            start: first.0,
            end: last.1,
            rectangles: selection_rects(chars, first.0, last.1),
        });
    }
    hits
}

pub fn hit_test(chars: &[PdfChar], x: f32, y: f32, tolerance: f32) -> Option<u32> {
    if !x.is_finite() || !y.is_finite() || !tolerance.is_finite() || tolerance < 0.0 {
        return None;
    }
    chars
        .iter()
        .filter(|c| c.bounds.valid())
        .filter_map(|c| {
            let b = c.bounds;
            let dx = (b.left - x).max(x - b.right).max(0.0);
            let dy = (b.top - y).max(y - b.bottom).max(0.0);
            let distance = dx.hypot(dy);
            (distance <= tolerance).then_some((distance, c.index))
        })
        .min_by(|a, b| a.0.total_cmp(&b.0))
        .map(|p| p.1)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayoutRegion {
    pub page: u32,
    pub bounds: Rect,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlyphMetric {
    pub character: char,
    pub advance_em: f32,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranslationLayout {
    pub text: String,
    pub regions: Vec<LayoutRegion>,
    pub obstacles: Vec<LayoutRegion>,
    pub glyphs: Vec<GlyphMetric>,
    pub font_size: f32,
    pub minimum_font_size: f32,
    pub line_height: f32,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PositionedLine {
    pub page: u32,
    pub text: String,
    pub start: usize,
    pub end: usize,
    pub left: f32,
    pub top: f32,
    pub width: f32,
    pub height: f32,
    pub font_size: f32,
    pub hard_break: bool,
}

/// Glyph advances are supplied in em by the font measurer used for the Flutter
/// PDF overlay. Rust chooses font size, rows, page regions and obstacle gaps.
pub fn layout_translation(input: &TranslationLayout) -> Result<Vec<PositionedLine>> {
    if !input.font_size.is_finite()
        || !input.minimum_font_size.is_finite()
        || !input.line_height.is_finite()
        || input.minimum_font_size <= 0.0
        || input.font_size < input.minimum_font_size
        || input.font_size > 200.0
        || input.line_height < 1.0
        || input
            .regions
            .iter()
            .chain(&input.obstacles)
            .any(|r| !r.bounds.valid())
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "invalid PDF translation layout",
        ));
    }
    let metrics: BTreeMap<_, _> = input
        .glyphs
        .iter()
        .map(|g| (g.character, g.advance_em))
        .collect();
    if input
        .text
        .chars()
        .filter(|c| !matches!(c, '\r' | '\n'))
        .any(|c| {
            metrics
                .get(&c)
                .is_none_or(|width| !width.is_finite() || *width < 0.0)
        })
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "missing or invalid glyph advance",
        ));
    }
    let mut size = input.font_size;
    loop {
        if let Some(lines) = try_layout(input, &metrics, size) {
            return Ok(lines);
        }
        if size <= input.minimum_font_size {
            break;
        }
        size = (size - 0.5).max(input.minimum_font_size);
    }
    Err(OtterError::new(
        ErrorCode::LayoutOverflow,
        "translation does not fit available PDF regions",
    ))
}

fn try_layout(
    input: &TranslationLayout,
    metrics: &BTreeMap<char, f32>,
    font_size: f32,
) -> Option<Vec<PositionedLine>> {
    let chars: Vec<_> = input.text.chars().collect();
    if chars.is_empty() {
        return Some(vec![]);
    }
    let height = font_size * input.line_height;
    let mut cursor = 0;
    let mut offset = 0;
    let mut result = Vec::new();
    for region in &input.regions {
        let mut top = region.bounds.top;
        while top + height <= region.bounds.bottom + 0.001 && cursor < chars.len() {
            let mut gaps = vec![(region.bounds.left, region.bounds.right)];
            for obstacle in input.obstacles.iter().filter(|o| {
                o.page == region.page && o.bounds.top < top + height && top < o.bounds.bottom
            }) {
                let mut next = Vec::new();
                for (left, right) in gaps {
                    if obstacle.bounds.left >= right || obstacle.bounds.right <= left {
                        next.push((left, right));
                    } else {
                        if obstacle.bounds.left > left {
                            next.push((left, obstacle.bounds.left));
                        }
                        if obstacle.bounds.right < right {
                            next.push((obstacle.bounds.right, right));
                        }
                    }
                }
                gaps = next;
            }
            let Some((left, right)) = gaps
                .into_iter()
                .max_by(|a, b| (a.1 - a.0).total_cmp(&(b.1 - b.0)))
            else {
                top += height;
                continue;
            };
            let available = right - left;
            let start = cursor;
            let start_offset = offset;
            let mut end = cursor;
            let mut width = 0.0;
            let mut break_at = None;
            let mut hard = false;
            while end < chars.len() {
                let ch = chars[end];
                if matches!(ch, '\r' | '\n') {
                    hard = true;
                    break;
                }
                let advance = metrics.get(&ch)? * font_size;
                if width + advance > available {
                    break;
                }
                width += advance;
                if ch.is_whitespace() {
                    break_at = Some((end + 1, width));
                }
                end += 1;
            }
            if end == start && !hard {
                top += height;
                continue;
            }
            if end < chars.len()
                && !hard
                && let Some((at, advance)) = break_at
            {
                end = at;
                width = advance;
            }
            let text: String = chars[start..end].iter().collect();
            offset += text.encode_utf16().count();
            cursor = end;
            if hard {
                let first = chars[cursor];
                offset += chars[cursor].len_utf16();
                cursor += 1;
                if first == '\r' && chars.get(cursor) == Some(&'\n') {
                    offset += 1;
                    cursor += 1;
                }
            }
            result.push(PositionedLine {
                page: region.page,
                text,
                start: start_offset,
                end: offset,
                left,
                top,
                width,
                height,
                font_size,
                hard_break: hard,
            });
            top += height;
        }
        if cursor == chars.len() {
            return Some(result);
        }
    }
    None
}
impl Rect {
    pub fn width(self) -> f32 {
        self.right - self.left
    }
    pub fn height(self) -> f32 {
        self.bottom - self.top
    }
    pub fn valid(self) -> bool {
        [self.left, self.top, self.right, self.bottom]
            .iter()
            .all(|v| v.is_finite())
            && self.width() > 0.0
            && self.height() > 0.0
    }
    pub fn contains(self, x: f32, y: f32) -> bool {
        x >= self.left && x <= self.right && y >= self.top && y <= self.bottom
    }
    pub fn overlaps(self, b: Self) -> bool {
        self.left < b.right && b.left < self.right && self.top < b.bottom && b.top < self.bottom
    }
    pub fn union(self, b: Self) -> Self {
        Self {
            left: self.left.min(b.left),
            top: self.top.min(b.top),
            right: self.right.max(b.right),
            bottom: self.bottom.max(b.bottom),
        }
    }
}
