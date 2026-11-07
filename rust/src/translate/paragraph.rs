use std::{collections::HashSet, ops::Range, sync::LazyLock};

use pulldown_cmark::{Event, Options, Parser, Tag};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::document::{Block, BlockKind, DocumentModel, revision};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paragraph {
    pub hash: String,
    pub source: String,
    pub start_utf16: usize,
    pub end_utf16: usize,
}

#[derive(Debug, Clone)]
pub struct Section {
    pub id: String,
    pub heading: Range<usize>,
    pub content: Range<usize>,
}

struct Rule {
    id: String,
    minimum: f64,
    regex: Regex,
}
static RULES: LazyLock<Vec<Rule>> = LazyLock::new(|| {
    let patterns: Value = serde_json::from_str(include_str!(
        "../../../assets/config/back_matter_sections.json"
    ))
    .unwrap();
    let categories: Value =
        serde_json::from_str(include_str!("back_matter_categories.json")).unwrap();
    let mut rules = Vec::new();
    for (level, minimum) in [("l1", 0.0), ("l2", 0.5), ("l3", 0.6)] {
        for category in categories.as_array().unwrap() {
            let matches: Vec<&str> = patterns[level]["patterns"]
                .as_array()
                .unwrap()
                .iter()
                .filter_map(Value::as_str)
                .filter(|pattern| {
                    // First matching category owns a pattern, exactly as in v0.1.7.
                    categories
                        .as_array()
                        .unwrap()
                        .iter()
                        .find(|candidate| {
                            candidate["keywords"]
                                .as_array()
                                .unwrap()
                                .iter()
                                .any(|word| {
                                    let plain = word
                                        .as_str()
                                        .unwrap()
                                        .replace(r"\b", "")
                                        .replace(r"\s", " ")
                                        .trim()
                                        .to_lowercase();
                                    !plain.is_empty() && pattern.to_lowercase().contains(&plain)
                                })
                        })
                        .is_some_and(|owner| owner["id"] == category["id"])
                })
                .collect();
            if !matches.is_empty() {
                let regex = Regex::new(&format!(
                    r"(?mi)^\s*#{{1,6}}\s*(?:\d+(?:\.\d+)*[.)]?\s*)?(?:{})\s*(?:[:：\-–—].*)?$",
                    matches.join("|")
                ))
                .unwrap();
                rules.push(Rule {
                    id: category["id"].as_str().unwrap().into(),
                    minimum,
                    regex,
                });
            }
        }
    }
    rules
});

pub fn sections(markdown: &str) -> Vec<Section> {
    let length = markdown.encode_utf16().count();
    let next_heading = Regex::new(r"(?m)^#{1,3}\s+\S").unwrap();
    let mut result = Vec::new();
    for rule in RULES.iter() {
        for matched in rule.regex.find_iter(markdown) {
            if markdown[..matched.start()].encode_utf16().count()
                < (length as f64 * rule.minimum).floor() as usize
            {
                continue;
            }
            let start = matched.end() + markdown[matched.end()..].len()
                - markdown[matched.end()..]
                    .trim_start_matches([' ', '\t', '\n', '\r'])
                    .len();
            let mut end = next_heading
                .find(&markdown[matched.end()..])
                .map(|m| m.start() + matched.end())
                .unwrap_or(markdown.len());
            end -= markdown[..end].len()
                - markdown[..end]
                    .trim_end_matches([' ', '\t', '\n', '\r'])
                    .len();
            if start < end {
                result.push(Section {
                    id: rule.id.clone(),
                    heading: matched.range(),
                    content: start..end,
                });
            }
        }
    }
    result.sort_by_key(|s| s.heading.start);
    result.dedup_by(|a, b| a.id == b.id && a.content == b.content);
    result
}

pub fn extract(markdown: &str, ignored: &HashSet<String>) -> Vec<Paragraph> {
    let mut skip = Vec::new();
    for (event, range) in
        Parser::new_ext(markdown, Options::ENABLE_TABLES | Options::ENABLE_MATH).into_offset_iter()
    {
        if matches!(
            event,
            Event::Start(Tag::CodeBlock(_) | Tag::Table(_)) | Event::DisplayMath(_)
        ) {
            skip.push(range);
        }
    }
    // Preserve the old rule: a paragraph touching any display equation is left alone.
    for matched in Regex::new(r"(?s)\$\$.*?\$\$").unwrap().find_iter(markdown) {
        skip.push(matched.range());
    }
    let image_only = Regex::new(r"^!\[[^\]]*\]\([^)]*\)[ \t]*$").unwrap();
    let table = Regex::new(r"(?m)^\s*\|[- :|]+\|\s*$").unwrap();
    let separator = Regex::new(r"\n[ \t]*\n").unwrap();
    let detected = sections(markdown);
    skip.extend(detected.iter().map(|s| s.content.clone()));
    let mut ranges = Vec::new();
    let mut cursor = 0;
    for sep in separator.find_iter(markdown) {
        ranges.push(cursor..sep.start());
        cursor = sep.end();
    }
    ranges.push(cursor..markdown.len());
    let mut result = Vec::new();
    for range in ranges {
        if skip
            .iter()
            .any(|r| range.start < r.end && range.end > r.start)
        {
            continue;
        }
        let text = markdown[range.clone()].trim();
        if text.is_empty() || image_only.is_match(text) || table.is_match(text) {
            continue;
        }
        let start = range.start + markdown[range.clone()].find(text).unwrap();
        result.push(paragraph(markdown, start..start + text.len()));
    }
    for section in detected {
        if !ignored.contains(&section.id) {
            result.push(paragraph(markdown, section.content));
        }
    }
    result.sort_by_key(|p| p.start_utf16);
    result
}

fn paragraph(markdown: &str, range: Range<usize>) -> Paragraph {
    Paragraph {
        hash: revision(markdown[range.clone()].trim()),
        source: markdown[range.clone()].into(),
        start_utf16: markdown[..range.start].encode_utf16().count(),
        end_utf16: markdown[..range.end].encode_utf16().count(),
    }
}

/// 块级译文键：`revision(markdown.trim())`，与阅读器和 0.1.x 迁移的译文一致。
/// 公式、代码、图内块与只有图片的块不翻译，返回 `None`。
pub fn block_key(block: &Block) -> Option<String> {
    let text = block.markdown.trim();
    let translatable = block.owner_id.is_none()
        && !matches!(block.kind, BlockKind::Equation | BlockKind::Code)
        && !text.is_empty()
        && !text.contains("$$")
        && !Regex::new(r"^!\[[^\]]*\]\([^)]*\)[ \t]*$")
            .unwrap()
            .is_match(text);
    translatable.then(|| revision(text))
}

/// 全文翻译的单位：文档模型中每个可翻译块一段。尾部章节（参考文献等）按
/// [`sections`] 规则识别，`ignored` 中的章节整段跳过。
pub fn blocks(model: &DocumentModel, ignored: &HashSet<String>) -> Vec<Paragraph> {
    // 以块拼出 Markdown（标题补回 `#`），复用章节识别规则。
    let mut markdown = String::new();
    let mut spans = Vec::new();
    for block in &model.blocks {
        let Some(hash) = block_key(block) else {
            continue;
        };
        if !markdown.is_empty() {
            markdown.push_str("\n\n");
        }
        let start = markdown.len();
        if block.kind == BlockKind::Heading {
            markdown.push_str(&"#".repeat(block.heading_level.unwrap_or(2).into()));
            markdown.push(' ');
            markdown.push_str(block.markdown.trim().trim_start_matches('#').trim_start());
        } else {
            markdown.push_str(block.markdown.trim());
        }
        spans.push((
            start..markdown.len(),
            hash,
            block.markdown.trim().to_owned(),
        ));
    }
    let skipped: Vec<_> = sections(&markdown)
        .into_iter()
        .filter(|s| ignored.contains(&s.id))
        .map(|s| s.content)
        .collect();
    let mut utf16 = 0;
    let mut last = 0;
    let mut result = Vec::new();
    for (range, hash, source) in spans {
        utf16 += markdown[last..range.start].encode_utf16().count();
        let length = markdown[range.clone()].encode_utf16().count();
        last = range.end;
        let start = utf16;
        utf16 += length;
        if skipped
            .iter()
            .any(|r| range.start < r.end && range.end > r.start)
        {
            continue;
        }
        result.push(Paragraph {
            hash,
            source,
            start_utf16: start,
            end_utf16: utf16,
        });
    }
    result
}
