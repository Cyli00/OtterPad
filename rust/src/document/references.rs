//! 参考文献列表：阅读器大纲的「参考文献」页。规则沿用 0.1.x `outline_panel.dart`：
//! 先认编号条目（`1.`、`1)`、`[1]`），没有编号时按段落取像引用的条目。

use std::sync::LazyLock;

use regex::Regex;
use serde::{Deserialize, Serialize};

use super::{Block, BlockKind};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Reference {
    pub number: u32,
    pub text: String,
    /// 条目所在的正文块，供跳转。
    pub block_id: String,
    /// 原文带编号；无编号时 `number` 只是顺序号。
    pub numbered: bool,
}

static HEADING: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)^(?:\d+(?:\.\d+)*[.)]?\s*)?(?:References|参考文献|Bibliography|Works?\s+Cited)",
    )
    .unwrap()
});
static ITEM: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?m)^\s*(?:\[(\d+)\]|(\d+)[.)])\s+").unwrap());
static LIKE_REFERENCE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\((?:19|20)\d{2}[a-z]?\)|\b(?:19|20)\d{2}[.,;]|\bdoi[:\s]|https?://").unwrap()
});
static SPACE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s+").unwrap());

fn normalize(text: &str) -> String {
    SPACE.replace_all(text, " ").trim().to_owned()
}

fn heading_level(block: &Block) -> u8 {
    block.heading_level.unwrap_or(1)
}

/// 第一个参考文献标题之后、下一个一至三级标题之前的条目。
pub fn references(blocks: &[Block]) -> Vec<Reference> {
    let Some(start) = blocks
        .iter()
        .position(|b| b.kind == BlockKind::Heading && HEADING.is_match(b.text.trim()))
    else {
        return vec![];
    };
    let section: Vec<&Block> = blocks[start + 1..]
        .iter()
        .take_while(|b| b.kind != BlockKind::Heading || heading_level(b) > 3)
        .filter(|b| b.owner_id.is_none())
        .collect();

    // 拼成一段文本并记下每块的起点，编号可能跨块（每条一块）也可能在同一块内。
    let mut text = String::new();
    let mut starts = Vec::with_capacity(section.len());
    for block in &section {
        if !text.is_empty() {
            text.push_str("\n\n");
        }
        starts.push(text.len());
        text.push_str(&block.markdown);
    }
    let owner = |offset: usize| {
        let index = starts.partition_point(|&s| s <= offset).saturating_sub(1);
        section[index].id.clone()
    };

    let matches: Vec<_> = ITEM.captures_iter(&text).collect();
    let mut numbered = Vec::new();
    for (i, captures) in matches.iter().enumerate() {
        let whole = captures.get(0).unwrap();
        let end = matches
            .get(i + 1)
            .map_or(text.len(), |next| next.get(0).unwrap().start());
        let body = normalize(&text[whole.end()..end]);
        if body.is_empty() {
            continue;
        }
        let number = captures
            .get(1)
            .or_else(|| captures.get(2))
            .and_then(|m| m.as_str().parse().ok())
            .unwrap_or(i as u32 + 1);
        numbered.push(Reference {
            number,
            text: body,
            block_id: owner(whole.start()),
            numbered: true,
        });
    }
    if !numbered.is_empty() {
        return numbered;
    }

    let mut items = Vec::new();
    for block in section {
        for paragraph in block.markdown.split("\n\n") {
            let body = normalize(paragraph);
            if body.chars().count() < 20 || !LIKE_REFERENCE.is_match(&body) {
                continue;
            }
            items.push(Reference {
                number: items.len() as u32 + 1,
                text: body,
                block_id: block.id.clone(),
                numbered: false,
            });
        }
    }
    items
}
