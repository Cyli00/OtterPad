use crate::{library::identifier::normalize_doi, storage::Document};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfAttachment {
    pub key: String,
    pub title: String,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportCandidate {
    pub key: String,
    pub document: Document,
    pub attachments: Vec<PdfAttachment>,
}

pub fn local_candidates(items: &[Value], added_at: i64) -> Vec<ImportCandidate> {
    let mut attachments: HashMap<String, Vec<PdfAttachment>> = HashMap::new();
    for item in items {
        let data = &item["data"];
        if deleted(data)
            || data["itemType"] != "attachment"
            || data["contentType"] != "application/pdf"
            || !matches!(
                data["linkMode"].as_str(),
                Some("imported_file" | "imported_url" | "linked_file")
            )
        {
            continue;
        }
        let (Some(parent), Some(key)) = (data["parentItem"].as_str(), item["key"].as_str()) else {
            continue;
        };
        attachments
            .entry(parent.into())
            .or_default()
            .push(PdfAttachment {
                key: key.into(),
                title: text(data, "filename")
                    .or_else(|| text(data, "title"))
                    .unwrap_or_else(|| key.into()),
            });
    }
    items
        .iter()
        .filter_map(|item| {
            let document = to_document(item, added_at)?;
            let key = item["key"].as_str()?.to_owned();
            let mut pdfs = attachments.remove(&key).unwrap_or_default();
            pdfs.sort_by(|a, b| a.key.cmp(&b.key));
            Some(ImportCandidate {
                key,
                document,
                attachments: pdfs,
            })
        })
        .collect()
}

pub fn to_document(item: &Value, added_at: i64) -> Option<Document> {
    let data = &item["data"];
    let kind = data["itemType"].as_str()?;
    if deleted(data)
        || ![
            "journalArticle",
            "conferencePaper",
            "preprint",
            "book",
            "bookSection",
            "thesis",
            "report",
            "manuscript",
            "patent",
            "standard",
            "document",
            "dataset",
            "encyclopediaArticle",
            "dictionaryEntry",
            "magazineArticle",
            "newspaperArticle",
        ]
        .contains(&kind)
    {
        return None;
    }
    let title = text(data, "title")?;
    let mut authors = Vec::new();
    let mut fallback = Vec::new();
    for creator in data["creators"].as_array().into_iter().flatten() {
        let name = text(creator, "name").unwrap_or_else(|| {
            format!(
                "{} {}",
                text(creator, "firstName").unwrap_or_default(),
                text(creator, "lastName").unwrap_or_default()
            )
            .trim()
            .to_owned()
        });
        if name.is_empty() {
            continue;
        }
        if creator["creatorType"] == "author" {
            authors.push(name);
        } else {
            fallback.push(name);
        }
    }
    if authors.is_empty() {
        authors = fallback;
    }
    let container: &[&str] = match kind {
        "journalArticle" => &["publicationTitle"],
        "conferencePaper" => &["proceedingsTitle", "publicationTitle"],
        "bookSection" => &["bookTitle", "publisher"],
        "book" => &["publisher"],
        "preprint" => &["repository", "publicationTitle"],
        _ => &["publicationTitle", "publisher"],
    };
    let journal = container.iter().find_map(|key| text(data, key));
    let year = text(data, "date").and_then(|date| {
        static YEAR: std::sync::LazyLock<regex::Regex> =
            std::sync::LazyLock::new(|| regex::Regex::new(r"\d{4}").unwrap());
        YEAR.find(&date).map(|m| m.as_str().to_owned())
    });
    let doi = text(data, "DOI")
        .and_then(|v| normalize_doi(&v))
        .map(|v| v.to_lowercase());
    if authors.is_empty()
        && journal.is_none()
        && year.is_none()
        && doi.is_none()
        && text(data, "ISBN").is_none()
    {
        return None;
    }
    let mut seen = HashSet::new();
    let keywords = data["tags"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|tag| text(tag, "tag"))
        .filter(|tag| seen.insert(tag.to_lowercase()))
        .collect();
    Some(Document {
        id: String::new(),
        title,
        authors,
        journal,
        year,
        doi,
        keywords,
        content_hash: None,
        added_at,
    })
}
fn deleted(data: &Value) -> bool {
    data["deleted"] == true || data["deleted"] == 1
}
fn text(data: &Value, key: &str) -> Option<String> {
    data[key]
        .as_str()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}
