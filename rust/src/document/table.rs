use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd};
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TableCell {
    pub text: String,
    pub row_span: u32,
    pub col_span: u32,
    pub header: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Table {
    pub rows: Vec<Vec<TableCell>>,
}

impl Table {
    pub fn parse(input: &str) -> Option<Self> {
        if input.to_ascii_lowercase().contains("<table") {
            let html = Html::parse_fragment(input);
            let tables = Selector::parse("table").ok()?;
            let rows = Selector::parse("tr").ok()?;
            let cells = Selector::parse("td, th").ok()?;
            let table = html.select(&tables).next()?;
            let rows = table
                .select(&rows)
                .filter(|row| {
                    row.ancestors()
                        .filter_map(scraper::ElementRef::wrap)
                        .find(|e| e.value().name() == "table")
                        .is_some_and(|p| p.id() == table.id())
                })
                .map(|row| {
                    row.select(&cells)
                        .filter(|cell| {
                            cell.ancestors()
                                .filter_map(scraper::ElementRef::wrap)
                                .find(|e| e.value().name() == "tr")
                                .is_some_and(|p| p.id() == row.id())
                        })
                        .map(|cell| TableCell {
                            text: cell
                                .text()
                                .collect::<Vec<_>>()
                                .join("")
                                .split_whitespace()
                                .collect::<Vec<_>>()
                                .join(" "),
                            row_span: cell
                                .value()
                                .attr("rowspan")
                                .and_then(|s| s.parse().ok())
                                .unwrap_or(1)
                                .clamp(1, 1000),
                            col_span: cell
                                .value()
                                .attr("colspan")
                                .and_then(|s| s.parse().ok())
                                .unwrap_or(1)
                                .clamp(1, 1000),
                            header: cell.value().name() == "th",
                        })
                        .collect()
                })
                .collect::<Vec<_>>();
            return (!rows.is_empty()).then_some(Self { rows });
        }
        let mut rows = Vec::new();
        let mut row = Vec::new();
        let mut cell = None::<String>;
        let mut header = false;
        let mut in_table = false;
        for event in Parser::new_ext(input, Options::ENABLE_TABLES | Options::ENABLE_MATH) {
            match event {
                Event::Start(Tag::Table(_)) => in_table = true,
                Event::End(TagEnd::Table) => break,
                Event::Start(Tag::TableHead) => {
                    header = true;
                }
                Event::Start(Tag::TableRow) => {
                    header = false;
                }
                Event::Start(Tag::TableCell) if in_table => cell = Some(String::new()),
                Event::Text(t) | Event::Code(t) if cell.is_some() => cell.as_mut()?.push_str(&t),
                Event::InlineMath(t) if cell.is_some() => {
                    cell.as_mut()?.push_str(&format!("${t}$"))
                }
                Event::SoftBreak | Event::HardBreak if cell.is_some() => cell.as_mut()?.push(' '),
                Event::End(TagEnd::TableCell) => row.push(TableCell {
                    text: cell.take().unwrap_or_default(),
                    row_span: 1,
                    col_span: 1,
                    header,
                }),
                Event::End(TagEnd::TableHead | TagEnd::TableRow) => {
                    rows.push(std::mem::take(&mut row))
                }
                _ => {}
            }
        }
        (!rows.is_empty()).then_some(Self { rows })
    }

    pub fn text(&self) -> String {
        self.rows
            .iter()
            .map(|row| {
                row.iter()
                    .map(|cell| cell.text.as_str())
                    .collect::<Vec<_>>()
                    .join("\t")
            })
            .collect::<Vec<_>>()
            .join("\n")
    }
}
