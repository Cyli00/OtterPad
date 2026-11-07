pub mod figures;
pub mod structure;
pub(crate) mod table;
pub use table::{Table, TableCell};

use std::collections::BTreeMap;

use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::error::{ErrorCode, OtterError, Result};
use structure::{LayoutBlock, Structure, TextRegion, is_visual};

pub fn revision(text: &str) -> String {
    Sha256::digest(text.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

pub(crate) fn extraction_directory(directory: &std::path::Path) -> Result<std::path::PathBuf> {
    let pointer = directory.join("ocr-current.json");
    if pointer.is_file() {
        let pointer: serde_json::Value = serde_json::from_slice(&std::fs::read(pointer)?)?;
        let generation = pointer["generation"]
            .as_str()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "OCR generation pointer"))?;
        Ok(directory
            .join("ocr")
            .join(crate::files::component(generation)?))
    } else {
        Ok(directory.to_owned())
    }
}
pub(crate) fn load(directory: &std::path::Path) -> Result<DocumentModel> {
    let directory = extraction_directory(directory)?;
    let path = directory.join("document.json");
    let model: DocumentModel = if path.is_file() {
        serde_json::from_slice(&std::fs::read(path)?)?
    } else {
        DocumentModel::from_markdown(&crate::ai::chat::read_markdown(&directory)?)
    };
    if model.version != 1 {
        return Err(OtterError::new(
            ErrorCode::Unsupported,
            "document model version",
        ));
    }
    Ok(model)
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlockKind {
    Heading,
    Paragraph,
    List,
    Quote,
    Figure,
    Table,
    Equation,
    Code,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct InlineRun {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub code: bool,
    pub strike: bool,
    pub link: Option<String>,
    pub math: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Block {
    pub id: String,
    pub kind: BlockKind,
    pub heading_level: Option<u8>,
    pub source_block_id: Option<String>,
    pub page_index: Option<i64>,
    pub source_regions: Vec<TextRegion>,
    pub markdown: String,
    pub text: String,
    pub revision: String,
    pub runs: Vec<InlineRun>,
    pub image: Option<String>,
    pub owner_id: Option<String>,
    pub table: Option<Table>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DocumentModel {
    pub version: u32,
    pub blocks: Vec<Block>,
    #[serde(default)]
    pub figures: Vec<figures::FigureSegment>,
}

impl DocumentModel {
    pub fn from_structure(structure: &Structure) -> Self {
        let mut model = Self {
            version: 1,
            blocks: vec![],
            figures: figures::find_figures(structure),
        };
        let mut occurrences = BTreeMap::<String, usize>::new();
        let mut emitted = std::collections::BTreeSet::new();
        for page in &structure.pages {
            for native in &page.blocks {
                if matches!(
                    native.block_label.as_str(),
                    "header"
                        | "footer"
                        | "number"
                        | "page_number"
                        | "header_image"
                        | "footer_image"
                ) {
                    continue;
                }
                if native.block_content.trim().is_empty() && !is_visual(&native.block_label) {
                    continue;
                }
                let kind = classify(native);
                let remainder = caption_remainder(
                    &native.block_content,
                    page.page_index,
                    &native.block_id,
                    &model.figures,
                );
                let mut block =
                    make_block(remainder.as_deref().unwrap_or(&native.block_content), kind);
                block.source_block_id = Some(native.block_id.clone());
                block.page_index = Some(page.page_index);
                block.source_regions = if page.page_size.is_none() {
                    vec![]
                } else if !native.text_regions.is_empty() {
                    native.text_regions.clone()
                } else if native.raw_bbox.len() == 4 {
                    vec![TextRegion {
                        page_index: page.page_index,
                        bbox: native.bbox(),
                        source_length: block.text.encode_utf16().count(),
                    }]
                } else {
                    vec![]
                };
                block.image = native.source_image.clone();
                let owner = model.figures.iter().find(|f| {
                    f.page_index == page.page_index
                        && f.blocks.iter().any(|b| b.block_id == native.block_id)
                        || f.caption_refs.iter().any(|r| {
                            r.page_index == page.page_index
                                && r.block_id.as_deref() == Some(native.block_id.as_str())
                        })
                });
                if let Some(figure) = owner {
                    if remainder.is_none() {
                        block.owner_id = Some(figure.id.clone());
                    }
                    if figure.page_index == page.page_index
                        && is_visual(&native.block_label)
                        && emitted.insert(figure.id.clone())
                    {
                        let mut root = make_block(
                            &figure.caption_text,
                            if figure.kind == "table" {
                                BlockKind::Table
                            } else {
                                BlockKind::Figure
                            },
                        );
                        root.id = figure.id.clone();
                        root.page_index = Some(page.page_index);
                        root.source_block_id = Some(native.block_id.clone());
                        root.image = figure.blocks.iter().find_map(|b| b.source_image.clone());
                        root.source_regions = figure
                            .blocks
                            .iter()
                            .filter(|b| {
                                is_visual(&b.block_label)
                                    && b.raw_bbox.len() == 4
                                    && page.page_size.is_some()
                            })
                            .map(|b| TextRegion {
                                page_index: page.page_index,
                                bbox: b.bbox(),
                                source_length: root.text.encode_utf16().count(),
                            })
                            .collect();
                        root.table = figure
                            .blocks
                            .iter()
                            .find(|b| b.block_label == "table")
                            .and_then(|b| Table::parse(&b.block_content));
                        model.blocks.push(root);
                    }
                }
                let identity = format!(
                    "p{}_{}_{:?}",
                    page.page_index,
                    revision(&block.text),
                    block.kind
                );
                let duplicate = occurrences.entry(identity.clone()).or_default();
                block.id = format!("{}_{}", revision(&identity), duplicate);
                *duplicate += 1;
                model.blocks.push(block);
            }
        }
        model
    }

    /// Fallback for imported Markdown with no provider layout. Top-level ranges
    /// preserve nested lists/quotes/code as a single semantic block.
    pub fn from_markdown(markdown: &str) -> Self {
        let mut model = Self {
            version: 1,
            blocks: vec![],
            figures: vec![],
        };
        let mut depth = 0;
        let mut start = 0;
        let mut kind = BlockKind::Paragraph;
        let mut occurrences = BTreeMap::<String, usize>::new();
        for (event, range) in Parser::new_ext(markdown, options()).into_offset_iter() {
            match event {
                Event::Start(tag) => {
                    if depth == 0 {
                        start = range.start;
                        kind = match tag {
                            Tag::Heading { .. } => BlockKind::Heading,
                            Tag::List(_) => BlockKind::List,
                            Tag::BlockQuote(_) => BlockKind::Quote,
                            Tag::CodeBlock(_) => BlockKind::Code,
                            Tag::Table(_) => BlockKind::Table,
                            _ => BlockKind::Paragraph,
                        };
                    }
                    depth += 1;
                }
                Event::End(_) => {
                    depth -= 1;
                    if depth == 0 {
                        let mut block = make_block(markdown[start..range.end].trim(), kind.clone());
                        let key = revision(&format!("{:?}:{}", kind, block.text));
                        let count = occurrences.entry(key.clone()).or_default();
                        block.id = format!("{key}_{count}");
                        *count += 1;
                        model.blocks.push(block);
                    }
                }
                Event::DisplayMath(expression) if depth == 0 => {
                    let mut block = make_block(&format!("$${expression}$$"), BlockKind::Equation);
                    let key = revision(&block.text);
                    let count = occurrences.entry(key.clone()).or_default();
                    block.id = format!("{key}_{count}");
                    *count += 1;
                    model.blocks.push(block);
                }
                _ => {}
            }
        }
        model
    }

    pub fn block(&self, id: &str) -> Option<&Block> {
        self.blocks.iter().find(|b| b.id == id)
    }

    pub fn resolve(&self, range: &AnchorRange) -> Option<AnchorRange> {
        if range.language != "source" || range.quote.is_empty() {
            return None;
        }
        if let Some(block) = self.block(&range.block_id) {
            if block.revision == range.revision
                && utf16_slice(&block.text, range.start, range.end) == Some(range.quote.as_str())
            {
                return Some(range.clone());
            }
            if let Some((start, end)) = find_quote(&block.text, range) {
                return Some(range.at(block, start, end));
            }
        }
        let matches: Vec<_> = self
            .blocks
            .iter()
            .filter(|block| block.owner_id.is_none())
            .filter_map(|block| find_quote(&block.text, range).map(|(s, e)| range.at(block, s, e)))
            .collect();
        if matches.len() == 1 {
            matches.into_iter().next()
        } else {
            None
        }
    }

    pub fn anchor(&self, id: &str, start: usize, end: usize) -> Result<AnchorRange> {
        let b = self
            .block(id)
            .ok_or_else(|| OtterError::new(ErrorCode::NotFound, "anchor block missing"))?;
        let quote = utf16_slice(&b.text, start, end)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                OtterError::new(ErrorCode::InvalidArgument, "invalid UTF-16 anchor range")
            })?;
        let prefix = b.text.encode_utf16().take(start).collect::<Vec<_>>();
        let suffix = b.text.encode_utf16().skip(end).take(32).collect::<Vec<_>>();
        Ok(AnchorRange {
            block_id: id.into(),
            language: "source".into(),
            revision: b.revision.clone(),
            start,
            end,
            quote: quote.into(),
            prefix: String::from_utf16_lossy(&prefix[prefix.len().saturating_sub(32)..]),
            suffix: String::from_utf16_lossy(&suffix),
        })
    }
}

fn caption_remainder(
    text: &str,
    page: i64,
    id: &str,
    figures: &[figures::FigureSegment],
) -> Option<String> {
    let mut ranges: Vec<_> = figures
        .iter()
        .flat_map(|f| &f.caption_refs)
        .filter(|r| r.page_index == page && r.block_id.as_deref() == Some(id))
        .filter_map(|r| Some((r.start?, r.end?)))
        .collect();
    if ranges.is_empty() {
        return None;
    }
    ranges.sort();
    let mut cursor = 0;
    let mut parts = Vec::new();
    for (start, end) in ranges {
        if start > cursor {
            parts.push(utf16_slice(text, cursor, start)?);
        }
        cursor = cursor.max(end);
    }
    parts.push(utf16_slice(text, cursor, text.encode_utf16().count())?);
    let remainder = parts.join("\n\n");
    (!remainder.trim().is_empty()).then_some(remainder)
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnchorRange {
    #[serde(alias = "paragraphId")]
    pub block_id: String,
    pub language: String,
    pub revision: String,
    pub start: usize,
    pub end: usize,
    pub quote: String,
    #[serde(default)]
    pub prefix: String,
    #[serde(default)]
    pub suffix: String,
}

impl AnchorRange {
    fn at(&self, block: &Block, start: usize, end: usize) -> Self {
        Self {
            block_id: block.id.clone(),
            revision: block.revision.clone(),
            start,
            end,
            ..self.clone()
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Anchor {
    pub version: u32,
    pub ranges: Vec<AnchorRange>,
}

pub fn utf16_slice(text: &str, start: usize, end: usize) -> Option<&str> {
    if end < start {
        return None;
    }
    let mut units = 0;
    let mut from = None;
    let mut to = None;
    for (byte, ch) in text.char_indices() {
        if units == start {
            from = Some(byte);
        }
        if units == end {
            to = Some(byte);
            break;
        }
        units += ch.len_utf16();
    }
    if units == start && from.is_none() {
        from = Some(text.len());
    }
    if units == end && to.is_none() {
        to = Some(text.len());
    }
    text.get(from?..to?)
}

fn find_quote(text: &str, range: &AnchorRange) -> Option<(usize, usize)> {
    let mut found = None;
    for (byte, _) in text.char_indices() {
        if !text[byte..].starts_with(&range.quote) {
            continue;
        }
        let end = byte + range.quote.len();
        if text[..byte].ends_with(&range.prefix) && text[end..].starts_with(&range.suffix) {
            if found.is_some() {
                return None;
            }
            let start = text[..byte].encode_utf16().count();
            found = Some((start, start + range.quote.encode_utf16().count()));
        }
    }
    found
}

mod markdown;
/// 译文的展示块：与原文块同类、同页，行内公式与样式按正文规则解析。
/// id 为原文块 id 加 `#t`，不归属任何图表。
pub fn translated_block(source: &Block, markdown: &str) -> Block {
    let mut block = make_block(markdown, source.kind.clone());
    block.id = format!("{}#t", source.id);
    block.heading_level = source.heading_level;
    block.page_index = source.page_index;
    block.source_block_id = source.source_block_id.clone();
    block
}

use markdown::*;
pub use markdown::{inline_runs, plain_text};
