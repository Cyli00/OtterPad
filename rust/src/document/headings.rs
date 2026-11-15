//! 标题分级：OCR 只标出“这是标题”，层级按编号体系、版面字号与首页大标题推断。
use std::sync::LazyLock;

use regex::Regex;

use super::{Block, BlockKind};

/// 同一层级的估算字号允许的相对差。
const SIZE_TOLERANCE: f64 = 0.1;
/// 首页无编号标题的字号达到标题字号中位数的该倍数时视为文档标题。
const TITLE_RATIO: f64 = 1.3;
/// 只靠字号分层时最多的层数，再细的差异多为识别噪声。
const MAX_SIZE_TIERS: usize = 3;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Family {
    /// 十进制编号的深度：`1` 为 1，`2.1` 为 2，附录 `A.1` 为 2。
    Decimal(usize),
    Named(&'static str),
}

struct Heading {
    family: Option<Family>,
    /// 字母编号或单字符罗马数字的首字母。
    letter: Option<char>,
    size: Option<f64>,
    first_page: bool,
}

/// 重算未归属图表的标题块的 `heading_level`；只改层级，块 id、markdown 与译文键不变。
pub(crate) fn assign(blocks: &mut [Block]) {
    let indices: Vec<_> = blocks
        .iter()
        .enumerate()
        .filter(|(_, b)| b.kind == BlockKind::Heading && b.owner_id.is_none())
        .map(|(i, _)| i)
        .collect();
    if indices.is_empty() {
        return;
    }
    let first_page = blocks.iter().filter_map(|b| b.page_index).min();
    let mut headings: Vec<_> = indices
        .iter()
        .map(|&i| Heading {
            // 编号取自 OCR 原文：解析后的文字会把行首的“2.”“1)”当作列表标记去掉。
            family: numbering(&blocks[i].markdown),
            letter: blocks[i]
                .markdown
                .trim_start_matches(['#', '*', ' '])
                .chars()
                .next()
                .filter(char::is_ascii_uppercase),
            size: font_size(&blocks[i]),
            first_page: first_page.is_some() && blocks[i].page_index == first_page,
        })
        .collect();
    // 单个 I/V/X 既可能是罗马数字也可能是字母编号：紧接在前一个字母（H、U、W）之后时算字母，
    // 否则看全文有没有多字符罗马数字。
    let roman = headings
        .iter()
        .any(|h| h.family == Some(Family::Named("roman")));
    let mut previous_letter = None;
    for heading in &mut headings {
        if heading.family == Some(Family::Named("roman?")) {
            let follows = heading
                .letter
                .zip(previous_letter)
                .is_some_and(|(c, p): (char, char)| c as u32 == p as u32 + 1);
            heading.family = Some(Family::Named(if roman && !follows {
                "roman"
            } else {
                "upper"
            }));
        }
        if heading.family == Some(Family::Named("upper")) {
            previous_letter = heading.letter;
        }
    }
    for (i, level) in indices.into_iter().zip(levels(&headings)) {
        blocks[i].heading_level = Some(level);
    }
}

fn levels(headings: &[Heading]) -> Vec<u8> {
    let mut sizes: Vec<_> = headings.iter().filter_map(|h| h.size).collect();
    sizes.sort_by(f64::total_cmp);
    let median = sizes.get(sizes.len() / 2).copied();
    let title: Vec<_> = headings
        .iter()
        .map(|h| {
            h.family.is_none()
                && h.first_page
                && h.size
                    .zip(median)
                    .is_some_and(|(s, m)| s >= m * TITLE_RATIO)
        })
        .collect();
    let base = if title.contains(&true) { 2 } else { 1 };

    // 编号家族按首次出现排序；十进制家族之间按深度排序，避免漏识别上一级时层级倒置。
    let mut order: Vec<Family> = Vec::new();
    for family in headings.iter().filter_map(|h| h.family) {
        if !order.contains(&family) {
            order.push(family);
        }
    }
    let slots: Vec<_> = (0..order.len())
        .filter(|&i| matches!(order[i], Family::Decimal(_)))
        .collect();
    let mut decimals: Vec<_> = slots.iter().map(|&i| order[i]).collect();
    decimals.sort_by_key(|f| match f {
        Family::Decimal(depth) => *depth,
        Family::Named(_) => 0,
    });
    for (slot, family) in slots.into_iter().zip(decimals) {
        order[slot] = family;
    }
    let rank = |family: Family| order.iter().position(|f| *f == family).unwrap_or(0);

    // 各编号层级的典型字号，供无编号标题（Abstract、References 等）对齐。
    let mut numbered_sizes = vec![Vec::new(); order.len()];
    for heading in headings {
        if let (Some(family), Some(size)) = (heading.family, heading.size) {
            numbered_sizes[rank(family)].push(size);
        }
    }
    let tiers: Vec<_> = numbered_sizes
        .into_iter()
        .enumerate()
        .filter_map(|(rank, mut sizes)| {
            sizes.sort_by(f64::total_cmp);
            sizes.get(sizes.len() / 2).map(|size| (rank, *size))
        })
        .collect();
    let unnumbered_tiers = size_tiers(
        headings
            .iter()
            .zip(&title)
            .filter(|(h, title)| h.family.is_none() && !**title)
            .filter_map(|(h, _)| h.size),
    );

    headings
        .iter()
        .zip(&title)
        .map(|(heading, title)| {
            if *title {
                return 1;
            }
            let depth = if let Some(family) = heading.family {
                rank(family)
            } else if let Some(size) = heading.size {
                if tiers.is_empty() {
                    unnumbered_tiers
                        .iter()
                        .position(|top| size >= top * (1.0 - SIZE_TOLERANCE))
                        .unwrap_or(unnumbered_tiers.len().saturating_sub(1))
                } else {
                    tiers
                        .iter()
                        .min_by(|a, b| (size / a.1).ln().abs().total_cmp(&(size / b.1).ln().abs()))
                        .map_or(0, |t| t.0)
                }
            } else {
                0
            };
            (base + depth).min(6) as u8
        })
        .collect()
}

/// 无编号标题的字号层：从大到小，比当前层最大字号小出容差才另起一层。
fn size_tiers(sizes: impl Iterator<Item = f64>) -> Vec<f64> {
    let mut sizes: Vec<_> = sizes.collect();
    sizes.sort_by(|a, b| b.total_cmp(a));
    let mut tops: Vec<f64> = Vec::new();
    for size in sizes {
        if tops
            .last()
            .is_none_or(|top| size < top * (1.0 - SIZE_TOLERANCE))
            && tops.len() < MAX_SIZE_TIERS
        {
            tops.push(size);
        }
    }
    tops
}

/// 由版面框估算字号（坐标单位）：单行时取框高，文字宽度明显超出框宽时按多行面积估算。
fn font_size(block: &Block) -> Option<f64> {
    let region = block.source_regions.first()?;
    let [l, t, r, b] = region.bbox.as_slice() else {
        return None;
    };
    let (width, height) = (r - l, b - t);
    let units: f64 = block.text.trim().chars().map(em_width).sum();
    if width <= 0.0 || height <= 0.0 || units <= 0.0 {
        return None;
    }
    let single = height / 1.25;
    Some(if units * single > width * 1.6 {
        (width * height / (1.25 * units)).sqrt()
    } else {
        single
    })
}

fn em_width(c: char) -> f64 {
    match c {
        '\u{2E80}'..='\u{9FFF}'
        | '\u{AC00}'..='\u{D7AF}'
        | '\u{F900}'..='\u{FAFF}'
        | '\u{FF00}'..='\u{FFEF}' => 1.0,
        c if c.is_whitespace() => 0.3,
        'A'..='Z' => 0.65,
        _ => 0.5,
    }
}

fn numbering(text: &str) -> Option<Family> {
    static NAMED: LazyLock<Vec<(Regex, &'static str)>> = LazyLock::new(|| {
        [
            (
                r"^第[一二三四五六七八九十百零〇两\d]+[章篇部]",
                "zh_chapter",
            ),
            (r"^第[一二三四五六七八九十百零〇两\d]+节", "zh_section"),
            (r"^[一二三四五六七八九十]+\s*[、.．]", "zh_number"),
            (r"^[（(]\s*[一二三四五六七八九十]+\s*[）)]", "zh_paren"),
            (r"^[（(]\s*\d{1,2}\s*[）)]", "paren_digit"),
            (r"^\d{1,2}\s*[)）]", "digit_paren"),
        ]
        .into_iter()
        .map(|(pattern, family)| (Regex::new(pattern).unwrap(), family))
        .collect()
    });
    static APPENDIX: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"^[A-Z]((?:[.．]\d{1,2})+)[.．]?(?:\s|$)").unwrap());
    static DECIMAL: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"^\d{1,2}((?:[.．]\d{1,2})*)(?:[.．、]\s*|\s+)\S").unwrap());
    static ROMAN: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"^([IVXLC]{1,7})[.．]\s*\S").unwrap());
    static UPPER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-Z][.．]\s+\S").unwrap());
    static LOWER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[a-z][.．)]\s+\S").unwrap());
    let text = text.trim_start_matches(['#', '*', ' ']).trim_start();
    if let Some((_, family)) = NAMED.iter().find(|(re, _)| re.is_match(text)) {
        return Some(Family::Named(family));
    }
    let depth = |groups: &str| groups.matches(['.', '．']).count() + 1;
    if let Some(c) = APPENDIX.captures(text) {
        return Some(Family::Decimal(depth(&c[1])));
    }
    if let Some(c) = DECIMAL.captures(text) {
        return Some(Family::Decimal(depth(&c[1])));
    }
    // 单个 C、L 作罗马数字意味着第 100、50 节，按字母编号处理。
    if let Some(c) = ROMAN.captures(text).filter(|c| !matches!(&c[1], "C" | "L")) {
        return Some(Family::Named(if c[1].len() == 1 {
            "roman?"
        } else {
            "roman"
        }));
    }
    if UPPER.is_match(text) {
        return Some(Family::Named("upper"));
    }
    LOWER.is_match(text).then_some(Family::Named("lower"))
}

#[cfg(test)]
mod tests {
    use crate::document::{DocumentModel, load, structure::Structure};
    use serde_json::json;

    #[test]
    fn saved_models_are_relevelled_on_load() {
        let heading = |id: &str, text: &str, top: f64, size: f64| {
            json!({"block_id":id,"block_label":"paragraph_title","block_content":text,
                   "block_bbox":[70.0, top, 1100.0, top + size * 1.25]})
        };
        let raw = json!([{"page_size":[1200,1600],"markdown":{"text":""},"prunedResult":{
        "parsing_res_list":[
            heading("a", "1 Introduction", 100.0, 18.0),
            heading("b", "1.1 Background", 200.0, 16.0),
        ]}}]);
        let mut model = DocumentModel::from_structure(&Structure::from_value(&raw).unwrap());
        // 旧版本保存的模型：所有标题都是 1 级。
        for block in &mut model.blocks {
            block.heading_level = Some(1);
        }
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join("document.json"),
            serde_json::to_vec(&model).unwrap(),
        )
        .unwrap();
        let levels: Vec<_> = load(directory.path())
            .unwrap()
            .blocks
            .iter()
            .map(|b| b.heading_level)
            .collect();
        assert_eq!(levels, vec![Some(1), Some(2)]);
    }
}
