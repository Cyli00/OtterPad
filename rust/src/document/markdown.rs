use super::*;

pub(super) fn options() -> Options {
    Options::ENABLE_TABLES
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_MATH
        | Options::ENABLE_TASKLISTS
}

pub fn inline_runs(markdown: &str) -> Vec<InlineRun> {
    let mut style = InlineRun::default();
    let mut runs = Vec::new();
    let mut image_depth = 0;
    for event in Parser::new_ext(markdown, options()) {
        let mut run = style.clone();
        match event {
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
        for run in &mut runs {
            let mut text = String::new();
            for ch in run.text.chars() {
                if ch.is_whitespace() {
                    pending_space = started;
                } else {
                    if pending_space {
                        text.push(' ');
                        pending_space = false;
                    }
                    text.push(ch);
                    started = true;
                }
            }
            run.text = text;
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
