use super::*;
use regex::{Captures, Regex};
use std::sync::LazyLock;

pub(super) fn options() -> Options {
    Options::ENABLE_TABLES
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_MATH
        | Options::ENABLE_TASKLISTS
}

// pulldown-cmark 不把 `$ x $` 当公式，OCR 结果却常带内侧空格；与 0.1.x 一样先收紧再解析。
// `$$` 先行匹配并原样保留：显示公式本身允许内侧空格，也避免把两个显示公式之间的正文当成行内公式。
static INLINE_MATH: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\$\$|\$([^$\n]+)\$").unwrap());
static LIST_MARKER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[ \t]*(\d{1,9}[.)]|[-+*])").unwrap());

pub fn inline_runs(markdown: &str) -> Vec<InlineRun> {
    let markdown = INLINE_MATH.replace_all(markdown, |c: &Captures| match c.get(1) {
        Some(inner) => format!("${}$", inner.as_str().trim()),
        None => c[0].to_owned(),
    });
    let mut style = InlineRun::default();
    let mut runs = Vec::new();
    let mut image_depth = 0;
    for (event, range) in Parser::new_ext(&markdown, options()).into_offset_iter() {
        let mut run = style.clone();
        match event {
            // 列表标记取自原文：OCR 的“2. Method”“1) Detail”保留原编号，无序列表显示为“•”。
            Event::Start(Tag::Item) => {
                run.text = match LIST_MARKER.captures(&markdown[range.start..]) {
                    Some(c) if c[1].starts_with(|c: char| c.is_ascii_digit()) => {
                        format!("{} ", &c[1])
                    }
                    _ => "• ".into(),
                };
            }
            Event::Start(Tag::Strong) => {
                style.bold = true;
                continue;
            }
            Event::End(TagEnd::Strong) => {
                style.bold = false;
                continue;
            }
            Event::Start(Tag::Emphasis) => {
                style.italic = true;
                continue;
            }
            Event::End(TagEnd::Emphasis) => {
                style.italic = false;
                continue;
            }
            Event::Start(Tag::Strikethrough) => {
                style.strike = true;
                continue;
            }
            Event::End(TagEnd::Strikethrough) => {
                style.strike = false;
                continue;
            }
            Event::Start(Tag::Link { dest_url, .. }) => {
                style.link = Some(dest_url.into_string());
                continue;
            }
            Event::End(TagEnd::Link) => {
                style.link = None;
                continue;
            }
            Event::Start(Tag::Image { .. }) => {
                image_depth += 1;
                continue;
            }
            Event::End(TagEnd::Image) => {
                image_depth -= 1;
                continue;
            }
            Event::Text(text) => run.text = text.into_string(),
            Event::Code(text) => {
                run.text = text.into_string();
                run.code = true;
            }
            Event::InlineMath(expression) => {
                run.text = format!("${expression}$");
                run.math = Some(expression.into_string());
            }
            Event::DisplayMath(expression) => {
                run.text = format!("$${expression}$$");
                run.math = Some(expression.into_string());
            }
            Event::Html(html) => run.text = html_text(&html),
            Event::InlineHtml(tag) if tag.starts_with("<br") => run.text = "\n".into(),
            Event::SoftBreak | Event::HardBreak => run.text = "\n".into(),
            Event::End(TagEnd::Paragraph | TagEnd::Item | TagEnd::Heading(_)) => {
                run.text = "\n".into()
            }
            _ => continue,
        }
        if image_depth == 0 && !run.text.is_empty() {
            runs.push(run);
        }
    }
    while runs.last().is_some_and(|r| r.text == "\n") {
        runs.pop();
    }
    runs
}

pub fn plain_text(markdown: &str) -> String {
    inline_runs(markdown)
        .iter()
        .map(|r| r.text.as_str())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
pub(super) fn html_text(html: &str) -> String {
    scraper::Html::parse_fragment(html)
        .root_element()
        .text()
        .collect::<Vec<_>>()
        .join("")
}

pub(super) fn classify(native: &LayoutBlock) -> BlockKind {
    match native.block_label.as_str() {
        "doc_title" | "paragraph_title" | "title" | "section_title" => BlockKind::Heading,
        "table" | "table_body" => BlockKind::Table,
        "image" | "chart" | "image_body" | "chart_body" => BlockKind::Figure,
        "formula" | "equation" | "display_formula" | "interline_equation" => BlockKind::Equation,
        "list" => BlockKind::List,
        "quote" | "blockquote" => BlockKind::Quote,
        "code" => BlockKind::Code,
        _ => BlockKind::Paragraph,
    }
}

pub(super) fn make_block(markdown: &str, kind: BlockKind) -> Block {
    let mut runs = inline_runs(markdown);
    if kind != BlockKind::Code {
        let mut started = false;
        let mut pending_space = false;
        for i in 0..runs.len() {
            let mut text = String::new();
            for ch in std::mem::take(&mut runs[i].text).chars() {
                if ch.is_whitespace() {
                    pending_space = started;
                } else {
                    if pending_space {
                        // 公式 run 整体绘制为一个控件，前导空格留给前一个 run 才能显示出来。
                        if runs[i].math.is_some() && text.is_empty() && i > 0 {
                            runs[i - 1].text.push(' ');
                        } else {
                            text.push(' ');
                        }
                        pending_space = false;
                    }
                    text.push(ch);
                    started = true;
                }
            }
            runs[i].text = text;
        }
        runs.retain(|r| !r.text.is_empty());
    }
    let mut text = runs.iter().map(|r| r.text.as_str()).collect::<String>();
    let kind = if kind == BlockKind::Paragraph
        && runs.len() == 1
        && runs[0].math.is_some()
        && markdown.trim_start().starts_with("$$")
    {
        BlockKind::Equation
    } else {
        kind
    };
    let table = if kind == BlockKind::Table {
        Table::parse(markdown)
    } else {
        None
    };
    if let Some(table) = &table {
        text = table.text();
    }
    let heading_level = if kind == BlockKind::Heading {
        Some(
            markdown
                .chars()
                .take_while(|c| *c == '#')
                .count()
                .clamp(1, 6) as u8,
        )
    } else {
        None
    };
    Block {
        id: String::new(),
        kind,
        heading_level,
        source_block_id: None,
        page_index: None,
        source_regions: vec![],
        markdown: markdown.into(),
        revision: revision(&text),
        text,
        runs,
        image: None,
        owner_id: None,
        table,
    }
}
