use super::*;

pub(super) fn caption_matches(text: &str) -> Vec<(usize, usize, String)> {
    let mut matches = Vec::new();
    for pattern in PATTERNS.iter() {
        for capture in pattern.regex.captures_iter(text) {
            let m = capture.get(0).unwrap();
            // Equivalent to the legacy prefix's negative lookahead: a joined letter
            // must introduce a numbered suffix (FigS1), never complete another word.
            if let (Some(prefix), Some(number)) = (capture.name("prefix"), capture.name("number"))
                && prefix.as_str().ends_with(|c: char| c.is_ascii_alphabetic())
                && number
                    .as_str()
                    .starts_with(|c: char| c.is_ascii_alphabetic())
            {
                let rest = &number.as_str()[1..];
                let rest = rest.trim_start_matches(['.', '．', '-', '‐', '‑', '–']);
                if !rest.starts_with(|c: char| c.is_ascii_digit() || ('０'..='９').contains(&c)) {
                    continue;
                }
            }
            matches.push((m.start(), m.end(), pattern.kind.clone()));
        }
    }
    matches.sort_by(|a, b| a.0.cmp(&b.0).then(b.1.cmp(&a.1)));
    matches.dedup_by(|a, b| a.0 == b.0);
    matches
}
pub(super) fn main_caption(text: &str) -> bool {
    caption_matches(&normalized(text))
        .first()
        .is_some_and(|m| m.0 == 0)
}
pub(super) fn caption_name(text: &str) -> String {
    let text = normalized(text);
    caption_matches(&text)
        .first()
        .filter(|m| m.0 == 0)
        .map(|m| {
            text[..m.1]
                .replace('.', "")
                .replace(' ', "_")
                .trim()
                .to_owned()
        })
        .unwrap_or_default()
}
pub(super) fn complete(text: &str) -> bool {
    let text = normalized(text);
    caption_matches(&text).first().is_some_and(|m| {
        m.0 == 0 && !text[m.1..].trim().is_empty() && text.ends_with(['.', '?', '!'])
    })
}
pub(super) fn stable(b: &LayoutBlock) -> bool {
    !sublabel(b)
        && (matches!(
            b.block_label.as_str(),
            "text"
                | "paragraph_title"
                | "abstract"
                | "header"
                | "footer"
                | "header_image"
                | "aside_text"
                | "number"
                | "formula"
        ) || b.block_label == "figure_title" && usable(&b.block_content))
}
pub(super) fn annotation(b: &LayoutBlock) -> bool {
    matches!(b.block_label.as_str(), "vision_footnote" | "vision_footer")
}
pub(super) fn note(b: &LayoutBlock) -> bool {
    annotation(b) && normalized(&b.block_content).encode_utf16().count() > 30 && !sublabel(b)
}
pub(super) fn body_continuation(b: &LayoutBlock) -> bool {
    matches!(
        b.block_label.as_str(),
        "text" | "paragraph_title" | "abstract" | "aside_text"
    )
}

pub(super) fn ranges(b: &LayoutBlock) -> Vec<(usize, usize)> {
    let text = &b.block_content;
    let starts: Vec<_> = caption_matches(text)
        .into_iter()
        .filter(|(start, end, _)| {
            let line = text[..*start].rfind('\n').map_or(0, |v| v + 1);
            let prefix = &text[line..*start];
            prefix.trim().is_empty()
                || prefix
                    .chars()
                    .all(|c| c.is_whitespace() || "#*_".contains(c))
                || (prefix.ends_with(char::is_whitespace)
                    && prefix
                        .trim_end()
                        .ends_with(['。', '！', '？', '.', '!', '?'])
                    && text[*start..*end].contains([':', '：', '|']))
        })
        .map(|m| m.0)
        .collect();
    if starts.is_empty() && is_caption(&b.block_label) && usable(text) {
        return vec![(0, text.len())];
    }
    let paragraph = Regex::new(r"\r?\n\s*\r?\n").unwrap();
    starts
        .iter()
        .enumerate()
        .map(|(i, start)| {
            let end = starts.get(i + 1).copied().unwrap_or(text.len());
            let end = paragraph
                .find(&text[*start..end])
                .map_or(end, |m| start + m.start());
            (*start, end)
        })
        .collect()
}

pub(super) fn continuations(page: &StructurePage, index: usize) -> Vec<usize> {
    let anchor = &page.blocks[index];
    let a = Box_::of(anchor);
    let height = a.b - a.t;
    let width = a.r - a.l;
    if height <= 0.0 || width <= 0.0 {
        return vec![];
    }
    let max_gap = (height * 0.8).max(15.0);
    let mut previous = a;
    let mut accumulated = normalized(&anchor.block_content);
    let mut result = Vec::new();
    for j in index + 1..page.blocks.len() {
        let candidate = &page.blocks[j];
        let text = candidate.block_content.trim();
        let b = Box_::of(candidate);
        let same_band = candidate.raw_bbox.len() == 4
            && b.l >= previous.r
            && b.l - previous.r <= width * 0.2
            && (b.t - previous.t).abs() <= 12f64.max(height * 0.2)
            && b.r - b.l >= width * 0.6;
        let modifier_tail = modifier_tail(&accumulated);
        if main_caption(text) && !(same_band && modifier_tail) {
            break;
        }
        if is_visual(&candidate.block_label) {
            if b.b <= a.t {
                continue;
            }
            break;
        }
        if matches!(
            candidate.block_label.as_str(),
            "header" | "footer" | "number" | "doc_title" | "paragraph_title"
        ) && !NOTE_LEAD.is_match(text)
        {
            break;
        }
        if !main_caption(&anchor.block_content) && body_continuation(candidate) {
            break;
        }
        let gap = b.t - previous.b;
        let overlapping_note = matches!(
            candidate.block_label.as_str(),
            "footnote" | "vision_footnote" | "vision_footer" | "footer" | "header"
        ) && b.t > previous.t
            && b.b > previous.b;
        if !same_band && ((gap < 0.0 && !overlapping_note) || gap > max_gap) {
            break;
        }
        let overlap = (a.r.min(b.r) - a.l.max(b.l)).max(0.0);
        let aligned = (b.l - a.l).abs() <= height
            && (matches!(
                candidate.block_label.as_str(),
                "footnote" | "vision_footnote" | "vision_footer"
            ) || NOTE_LEAD.is_match(text));
        let overlap_width = if aligned { width.min(b.r - b.l) } else { width };
        if !same_band && (overlap_width <= 0.0 || overlap / overlap_width < 0.6) {
            break;
        }
        if body_continuation(candidate) && complete(&accumulated) && !NOTE_LEAD.is_match(text) {
            break;
        }
        if body_continuation(candidate) && !complete(&accumulated) && a.l - b.l > width {
            break;
        }
        if !same_band
            && candidate.group_id.is_some()
            && page
                .blocks
                .get(j + 1)
                .is_some_and(|b| b.group_id == candidate.group_id)
        {
            break;
        }
        previous = b;
        if text.is_empty() {
            continue;
        }
        result.push(j);
        accumulated = joined([accumulated.as_str(), text]);
    }
    result
}
pub(super) fn modifier_tail(text: &str) -> bool {
    static MODIFIERS: LazyLock<Vec<String>> = LazyLock::new(|| {
        let config: Value = serde_json::from_str(include_str!(
            "../../../../assets/config/caption_patterns.json"
        ))
        .unwrap();
        config["supplementary"]["modifiers"]
            .as_object()
            .into_iter()
            .flatten()
            .flat_map(|(_, v)| v.as_array().into_iter().flatten())
            .filter_map(Value::as_str)
            .map(|s| s.to_lowercase())
            .collect()
    });
    let text = text.trim_end().to_lowercase();
    MODIFIERS.iter().any(|m| text.ends_with(m))
}

pub(super) fn collect(page: &StructurePage, index: usize) -> Vec<Caption> {
    let anchors: Vec<_> = page
        .blocks
        .iter()
        .enumerate()
        .filter(|(_, b)| !is_visual(&b.block_label))
        .flat_map(|(i, b)| {
            ranges(b)
                .into_iter()
                .filter(|(s, e)| usable(b.block_content[*s..*e].trim()))
                .map(move |(s, e)| (i, s, e))
        })
        .collect();
    let mut consumed = BTreeSet::new();
    let mut captions = Vec::new();
    for &(i, start, end) in &anchors {
        let b = &page.blocks[i];
        if consumed.contains(&i) {
            continue;
        }
        let name = caption_name(&b.block_content);
        let duplicates: Vec<_> = anchors
            .iter()
            .map(|a| a.0)
            .filter(|other| {
                *other != i
                    && !name.is_empty()
                    && caption_name(&page.blocks[*other].block_content) == name
                    && Box_::of(b).overlaps(Box_::of(&page.blocks[*other]))
            })
            .collect();
        if duplicates.iter().any(|d| {
            page.blocks[*d].block_content.encode_utf16().count()
                > b.block_content.encode_utf16().count()
        }) {
            continue;
        }
        let mut parts = if b.parent_id.is_some() || end < b.block_content.trim_end().len() {
            vec![]
        } else {
            continuations(page, i)
        };
        parts.extend(duplicates.iter().copied());
        consumed.extend(parts.iter().copied());
        let text = joined(
            std::iter::once(&b.block_content[start..end]).chain(
                parts
                    .iter()
                    .filter(|p| !duplicates.contains(p))
                    .map(|p| page.blocks[*p].block_content.as_str()),
            ),
        );
        let mut refs = vec![CaptionRef {
            page_index: page.page_index,
            text: b.block_content[start..end].into(),
            block_id: Some(b.block_id.clone()),
            line_index: None,
            start: Some(b.block_content[..start].encode_utf16().count()),
            end: Some(b.block_content[..end].encode_utf16().count()),
        }];
        refs.extend(parts.iter().map(|p| CaptionRef {
            page_index: page.page_index,
            text: page.blocks[*p].block_content.clone(),
            block_id: Some(page.blocks[*p].block_id.clone()),
            line_index: None,
            start: None,
            end: None,
        }));
        captions.push(Caption {
            page: index,
            name: caption_name(&b.block_content[start..end]),
            text,
            box_: (b.raw_bbox.len() == 4).then(|| {
                Box_::union(std::iter::once(b).chain(parts.iter().map(|p| &page.blocks[*p])))
            }),
            block: Some(i),
            continuations: parts,
            refs,
            line: None,
        });
    }
    let mut known: BTreeSet<_> = captions.iter().map(|c| c.name.clone()).collect();
    let lines: Vec<_> = page.markdown.split('\n').collect();
    for (line_index, line) in lines.iter().enumerate() {
        let text = normalized(line);
        if text.is_empty() || !main_caption(&text) {
            continue;
        }
        let name = caption_name(&text);
        if name.is_empty()
            || known.contains(&name)
            || captions.iter().any(|c| c.text.contains(&text))
        {
            continue;
        }
        known.insert(name.clone());
        let mut parts = vec![text];
        for line in lines.iter().skip(line_index + 1) {
            let text = normalized(line);
            if text.is_empty() {
                continue;
            }
            if NOTE_LEAD.is_match(&text) {
                parts.push(text);
            } else {
                break;
            }
        }
        captions.push(Caption {
            page: index,
            name,
            text: joined(parts.iter().map(String::as_str)),
            box_: None,
            block: None,
            continuations: vec![],
            refs: vec![],
            line: Some(line_index),
        });
    }
    captions
}
