//! Local metadata rules retained from the v0.1.7 filename, layout and Chinese extractors.
use super::identifier::{self, Identifier, IdentifierKind};
use crate::document::structure::LayoutBlock;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, sync::LazyLock};

macro_rules! pattern {
    ($name:ident,$value:literal) => {
        static $name: LazyLock<Regex> =
            LazyLock::new(|| Regex::new($value).expect("static metadata regex"));
    };
}
pattern!(DOI, r#"(?i)10\.\d{4,}/[^\s"{}|\\^`\[\]]+"#);
pattern!(YEAR, r"(?:19|20)\d{2}");
pattern!(YEAR_ONLY, r"^\d{4}$");
pattern!(DRIVE, r"^[A-Za-z]:[\\/]");
pattern!(
    WORD_PLACEHOLDER,
    r"(?i)^(microsoft\s*word\s*-\s*)?document\d*$"
);
pattern!(UNTITLED, r"(?i)^untitled-?\d+$");
pattern!(CNKI_NAME, r"^[一-鿿·]{2,4}$");
pattern!(NAME, r"[一-鿿]{2,4}");
pattern!(HAN, r"[一-鿿]");
pattern!(AUTHOR_ROLE, r"(?:编著|主编|编|著|译|改编)\s*$");
pattern!(EXCLUDED_ROLE, r"(?:主审|审校|审|校)\s*$");
pattern!(
    AUTHOR_END,
    r"(?i)[（(]\s*1\s*[.．、]|摘\s*要|关\s*键\s*词|Abstract|Key\s*words"
);
pattern!(DELIMITER, r"[,，、;；]");
pattern!(
    AUTHOR_SEQUENCE,
    r"(?:[一-鿿]{2,4}[,，、;；\d\s*]*){2,}[一-鿿]{2,4}"
);
pattern!(CN_YEAR, r"((?:19|20)\d{2})\s*年");
pattern!(
    ARTICLE_YEAR,
    r"文章编号[：:][\d-]+[（(]((?:19|20)\d{2})[）)]"
);
pattern!(
    JOURNAL,
    r"[一-鿿]{2,12}(?:学报|学刊|杂志|通报|导报|公报|评论|论坛|科学|医学|科技|工程|译丛|文摘|研究|进展|报告|纪要|年鉴|快报|通讯|集刊|丛刊|学术|综述)"
);
pattern!(VOLUME, r"第\s*\d+\s*[卷期]");
pattern!(YEAR_MONTH, r"(?:19|20)\d{2}\s*年(?:\s*\d{1,2}\s*月)?");
pattern!(ASCII_NOISE, r"[A-Za-z0-9．.:：/\-]+");
pattern!(
    ARXIV_NEW,
    r"(?i)(?:arXiv:\s*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?)"
);
pattern!(
    ARXIV_OLD,
    r"(?i)(?:arXiv:\s*|arxiv\.org/(?:abs|pdf)/)?([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)?/\d{7}(?:v\d+)?)"
);
pattern!(
    ISBN,
    r"(?i)(?:ISBN(?:-1[03])?[:\s-]*)([0-9Xx][0-9Xx\s-]{8,20})"
);

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Metadata {
    pub title: Option<String>,
    pub authors: Vec<String>,
    pub journal: Option<String>,
    pub year: Option<String>,
    pub doi: Option<String>,
}
impl Metadata {
    pub fn has_any(&self) -> bool {
        !self.authors.is_empty()
            || [
                self.title.as_deref(),
                self.journal.as_deref(),
                self.year.as_deref(),
                self.doi.as_deref(),
            ]
            .into_iter()
            .flatten()
            .any(|s| !s.is_empty())
    }
    pub fn merge(self, other: Self) -> Self {
        Self {
            title: clean(other.title.as_deref()).or(self.title),
            authors: if other.authors.is_empty() {
                self.authors
            } else {
                other.authors
            },
            journal: clean(other.journal.as_deref()).or(self.journal),
            year: clean(other.year.as_deref()).or(self.year),
            doi: clean(other.doi.as_deref()).or(self.doi),
        }
    }
    pub fn apply(&self, document: &mut crate::storage::Document) {
        if let Some(title) = clean(self.title.as_deref()) {
            document.title = title;
        }
        if !self.authors.is_empty() {
            document.authors = self.authors.clone();
        }
        if let Some(journal) = clean(self.journal.as_deref()) {
            document.journal = Some(journal);
        }
        if let Some(year) = clean(self.year.as_deref()) {
            document.year = Some(year);
        }
        if let Some(doi) = clean(self.doi.as_deref()) {
            document.doi = Some(doi.to_lowercase());
        }
    }
}
#[derive(Debug, Clone, Default)]
pub struct PdfProperties {
    pub title: Option<String>,
    pub author: Option<String>,
    pub subject: Option<String>,
    pub keywords: Option<String>,
}

pub fn plausible_title(value: &str) -> bool {
    let value = value.trim();
    let lower = value.to_lowercase();
    !value.is_empty()
        && !value.starts_with('/')
        && !value.starts_with("\\\\")
        && !DRIVE.is_match(value)
        && lower != "untitled"
        && !WORD_PLACEHOLDER.is_match(value)
        && !UNTITLED.is_match(value)
        && ![
            ".eps", ".ps", ".dvi", ".tif", ".tiff", ".fig", ".bbl", ".aux", ".log", ".tex", ".cls",
            ".sty", ".synctex",
        ]
        .iter()
        .any(|suffix| lower.ends_with(suffix))
}
pub fn parse_text(value: &str) -> Metadata {
    let value = value.trim();
    let text = normalize(if value.to_ascii_lowercase().ends_with(".pdf") {
        &value[..value.len() - 4]
    } else {
        value
    });
    if text.is_empty() {
        return Metadata::default();
    }
    let parse_year_leading = |text: &str| -> Option<Metadata> {
        let parts = text
            .split('-')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>();
        if parts.len() < 3 || !YEAR_ONLY.is_match(parts[0]) {
            return None;
        }
        let title = parts[2..].join("-");
        Some(Metadata {
            title: Some(title),
            authors: vec![parts[1].into()],
            year: Some(parts[0].into()),
            doi: extract_doi(text),
            ..Default::default()
        })
    };
    if let Some(metadata) = parse_year_leading(&text) {
        return metadata;
    }
    for year in YEAR.find_iter(&text) {
        if let Some(metadata) = parse_year_leading(&text[year.start()..]) {
            return metadata;
        }
    }
    if is_chinese(&text)
        && let Some((title, author)) = text.rsplit_once('_')
        && !title.trim().is_empty()
        && CNKI_NAME.is_match(author.trim())
    {
        return Metadata {
            title: Some(title.trim().into()),
            authors: vec![author.trim().into()],
            ..Default::default()
        };
    }
    Metadata {
        doi: extract_doi(&text),
        year: extract_year(&text),
        ..Default::default()
    }
}
pub fn parse_filename(path: &str) -> Metadata {
    parse_text(path.rsplit(['/', '\\']).next().unwrap_or(path))
}
pub fn extract_doi(text: &str) -> Option<String> {
    DOI.find(text)
        .and_then(|m| identifier::normalize_doi(m.as_str()))
}
pub fn extract_year(text: &str) -> Option<String> {
    YEAR.find(text).map(|m| m.as_str().into())
}
pub fn identifier_from_text(text: &str) -> Option<Identifier> {
    if let Some(value) = extract_doi(text) {
        return Some(Identifier {
            kind: IdentifierKind::Doi,
            value,
        });
    }
    for pattern in [&*ARXIV_NEW, &*ARXIV_OLD] {
        if let Some(capture) = pattern.captures(text) {
            return Some(Identifier {
                kind: IdentifierKind::Arxiv,
                value: capture[1].into(),
            });
        }
    }
    ISBN.captures(text)
        .map(|c| identifier::parse(&c[1]))
        .filter(|id| id.kind == IdentifierKind::Isbn)
}
pub fn from_properties(properties: &PdfProperties) -> Metadata {
    let title = clean(properties.title.as_deref()).filter(|s| plausible_title(s));
    let parsed = title.as_deref().map(parse_text).unwrap_or_default();
    let text = [
        title.as_deref(),
        properties.subject.as_deref(),
        properties.keywords.as_deref(),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join(" ");
    let author_separator = Regex::new(r"(?i)\s*(?:;|\band\b)\s*").unwrap();
    let authors = properties
        .author
        .as_deref()
        .into_iter()
        .flat_map(|a| author_separator.split(a))
        .filter_map(|s| clean(Some(s)))
        .filter(|name| {
            !["cnki", "中国知网", "china academic journal"]
                .iter()
                .any(|marker| name.to_lowercase().contains(marker))
        })
        .collect();
    Metadata {
        title,
        ..Default::default()
    }
    .merge(parsed)
    .merge(Metadata {
        authors,
        journal: clean(properties.subject.as_deref()).filter(|s| extract_doi(s).is_none()),
        year: extract_year(&text),
        doi: extract_doi(&text),
        ..Default::default()
    })
}
pub fn from_first_page(blocks: &[LayoutBlock]) -> Metadata {
    let Some(content) = blocks
        .iter()
        .find(|b| b.block_label == "doc_title" && !b.block_content.trim().is_empty())
        .map(|b| b.block_content.trim())
    else {
        return Metadata::default();
    };
    let lines = content
        .lines()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>();
    let mut chinese = lines
        .iter()
        .copied()
        .filter(|s| is_chinese(s))
        .collect::<Vec<_>>();
    chinese.sort_by_key(|s| std::cmp::Reverse(s.encode_utf16().count()));
    let title = chinese
        .first()
        .copied()
        .or_else(|| lines.first().copied())
        .map(str::to_owned);
    let authors = blocks
        .iter()
        .filter(|b| b.block_label == "text")
        .flat_map(|b| b.block_content.lines())
        .map(str::trim)
        .filter(|s| !EXCLUDED_ROLE.is_match(s) && AUTHOR_ROLE.is_match(s))
        .find_map(|line| {
            let names = NAME
                .find_iter(AUTHOR_ROLE.replace(line, "").trim())
                .map(|m| m.as_str().to_owned())
                .collect::<Vec<_>>();
            (!names.is_empty()).then_some(names)
        })
        .unwrap_or_default();
    Metadata {
        title,
        authors,
        ..Default::default()
    }
}

fn normalize(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}
fn clean(value: Option<&str>) -> Option<String> {
    value.map(normalize).filter(|s| !s.is_empty())
}

/// Streams the same uncompressed XMP packets supported by 0.1.x, without reading
/// the whole PDF into a second buffer. Info-dictionary strings come from PDFium.
mod chinese;
pub use chinese::{from_chinese_text, is_chinese, non_person_name};
mod xmp;
pub use xmp::{from_xmp, xmp_from_pdf};
mod inspection;
pub use inspection::{
    LocalInspection, complete, duplicate, inspect_local, needs_repair, same_core,
};
