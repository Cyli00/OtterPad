use std::{
    collections::{BTreeMap, BTreeSet},
    sync::LazyLock,
};

use regex::Regex;
use reqwest::{Client, Url};
use roxmltree::Node;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio_util::sync::CancellationToken;

use crate::{
    error::{ErrorCode, OtterError, Result},
    network,
    storage::Document,
    tasks::cancellable,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IdentifierKind {
    Doi,
    Pmid,
    Arxiv,
    Isbn,
    Unknown,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Identifier {
    pub kind: IdentifierKind,
    pub value: String,
}
static DOI: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^10\.\d{4,}/\S+$").unwrap());
static ARXIV: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^(?:\d{4}\.\d{4,5}|[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)?/\d{7})(?:v\d+)?$").unwrap()
});
static ELIFE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)^10\.7554/elife\.(\d+)(?:\.\d+)?$").unwrap());
static YEAR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d{4}").unwrap());

pub fn normalize_doi(raw: &str) -> Option<String> {
    let mut value = raw.trim();
    for prefix in [
        "https://doi.org/",
        "http://doi.org/",
        "https://dx.doi.org/",
        "http://dx.doi.org/",
        "doi:",
    ] {
        if value.to_ascii_lowercase().starts_with(prefix) {
            value = value[prefix.len()..].trim();
            break;
        }
    }
    static XML: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?i)</[A-Za-z][^<>\s]*>$").unwrap());
    let value = XML.replace_all(value, "");
    let value = if value.to_ascii_lowercase().ends_with(".pdf") {
        &value[..value.len() - 4]
    } else {
        &value
    };
    let value = value.trim_end_matches(['.', ',', ';', ')', ']']);
    DOI.is_match(value).then(|| value.to_owned())
}

pub fn parse(raw: &str) -> Identifier {
    if let Some(value) = normalize_doi(raw) {
        return Identifier {
            kind: IdentifierKind::Doi,
            value,
        };
    }
    let mut value = raw.trim();
    for prefix in [
        "https://arxiv.org/abs/",
        "http://arxiv.org/abs/",
        "https://arxiv.org/pdf/",
        "http://arxiv.org/pdf/",
        "arxiv:",
    ] {
        if value.to_ascii_lowercase().starts_with(prefix) {
            value = value[prefix.len()..].trim();
            break;
        }
    }
    let value = value.split(['?', '#']).next().unwrap_or_default();
    let value = if value.to_ascii_lowercase().ends_with(".pdf") {
        &value[..value.len() - 4]
    } else {
        value
    };
    if ARXIV.is_match(value) {
        return Identifier {
            kind: IdentifierKind::Arxiv,
            value: value.into(),
        };
    }
    let mut value = raw.trim();
    if value
        .get(..5)
        .is_some_and(|s| s.eq_ignore_ascii_case("pmid:"))
    {
        value = value[5..].trim();
    }
    if !value.is_empty() && value.len() <= 8 && value.bytes().all(|c| c.is_ascii_digit()) {
        return Identifier {
            kind: IdentifierKind::Pmid,
            value: value.into(),
        };
    }
    let mut value = raw.trim();
    for prefix in ["isbn-10:", "isbn-13:", "isbn:"] {
        if value.to_ascii_lowercase().starts_with(prefix) {
            value = value[prefix.len()..].trim();
            break;
        }
    }
    let value: String = value
        .chars()
        .filter(|c| *c != '-' && !c.is_whitespace())
        .collect();
    if value.len() == 13 && value.bytes().all(|c| c.is_ascii_digit())
        || value.len() == 10
            && value.as_bytes()[..9].iter().all(u8::is_ascii_digit)
            && value
                .as_bytes()
                .get(9)
                .is_some_and(|c| c.is_ascii_digit() || *c == b'X' || *c == b'x')
    {
        return Identifier {
            kind: IdentifierKind::Isbn,
            value,
        };
    }
    Identifier {
        kind: IdentifierKind::Unknown,
        value: raw.trim().into(),
    }
}

pub fn arxiv_doi(id: &str) -> Option<String> {
    if !ARXIV.is_match(id.trim()) {
        return None;
    }
    static VERSION: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)v\d+$").unwrap());
    let id = VERSION.replace(id.trim(), "");
    let id = if let Some((archive, number)) = id.split_once('/') {
        format!("{}/{number}", archive.split('.').next().unwrap_or(archive))
    } else {
        id.into_owned()
    };
    Some(format!("10.48550/arxiv.{}", id.to_ascii_lowercase()))
}

#[derive(Debug, Clone)]
pub struct MetadataEndpoints {
    pub crossref: String,
    pub pubmed: String,
    pub arxiv: String,
    pub openlibrary: String,
    pub elife: String,
    pub doi: String,
}
impl Default for MetadataEndpoints {
    fn default() -> Self {
        Self {
            crossref: "https://api.crossref.org".into(),
            pubmed: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils".into(),
            arxiv: "https://export.arxiv.org/api/query".into(),
            openlibrary: "https://openlibrary.org".into(),
            elife: "https://api.elifesciences.org".into(),
            doi: "https://doi.org".into(),
        }
    }
}
pub struct MetadataResolver {
    pub client: Client,
    pub endpoints: MetadataEndpoints,
}
impl MetadataResolver {
    pub fn new(client: Client) -> Self {
        Self {
            client,
            endpoints: MetadataEndpoints::default(),
        }
    }
    pub async fn resolve(&self, input: &str, token: &CancellationToken) -> Result<Document> {
        let identifier = parse(input);
        match identifier.kind {
            IdentifierKind::Doi => {
                if identifier
                    .value
                    .to_ascii_lowercase()
                    .starts_with("10.48550/arxiv.")
                {
                    let response = network::send(
                        self.client
                            .head(endpoint(&self.endpoints.doi, &[&identifier.value])?),
                        token,
                    )
                    .await?;
                    let id = response
                        .url()
                        .path()
                        .strip_prefix("/abs/")
                        .ok_or_else(|| {
                            OtterError::new(ErrorCode::NotFound, "arXiv DOI did not resolve")
                        })?
                        .to_owned();
                    return self.arxiv(&id, token).await;
                }
                let doi = if let Some(capture) = ELIFE.captures(&identifier.value) {
                    let article = &capture[1];
                    match self.elife(article, token).await {
                        Ok(document) => return Ok(document),
                        Err(e) if e.code == ErrorCode::Cancelled => return Err(e),
                        Err(_) => {}
                    }
                    format!("10.7554/elife.{article}")
                } else {
                    identifier.value
                };
                let response = network::json(
                    self.client
                        .get(endpoint(&self.endpoints.crossref, &["works", &doi])?)
                        .query(&[("mailto", "dev@otterpad.app")]),
                    token,
                )
                .await?;
                crossref_document(&response["message"], Some(&doi))
            }
            IdentifierKind::Pmid => self.pubmed(&identifier.value, token).await,
            IdentifierKind::Arxiv => self.arxiv(&identifier.value, token).await,
            IdentifierKind::Isbn => self.isbn(&identifier.value, token).await,
            IdentifierKind::Unknown => Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "unrecognized identifier",
            )),
        }
    }

    async fn text(
        &self,
        request: reqwest::RequestBuilder,
        token: &CancellationToken,
    ) -> Result<String> {
        cancellable(token, async {
            Ok(network::send(request, token).await?.text().await?)
        })
        .await
    }

    async fn pubmed(&self, id: &str, token: &CancellationToken) -> Result<Document> {
        let text = self
            .text(
                self.client
                    .get(endpoint(&self.endpoints.pubmed, &["efetch.fcgi"])?)
                    .query(&[("db", "pubmed"), ("id", id), ("retmode", "xml")]),
                token,
            )
            .await?;
        parse_pubmed(&text, id)
    }
    async fn arxiv(&self, id: &str, token: &CancellationToken) -> Result<Document> {
        let text = self
            .text(
                self.client
                    .get(&self.endpoints.arxiv)
                    .query(&[("id_list", id)]),
                token,
            )
            .await?;
        parse_arxiv(&text, id)
    }
    async fn isbn(&self, id: &str, token: &CancellationToken) -> Result<Document> {
        let response = network::json(
            self.client.get(endpoint(
                &self.endpoints.openlibrary,
                &["isbn", &format!("{id}.json")],
            )?),
            token,
        )
        .await?;
        let mut document = blank(response["title"].as_str().unwrap_or(id));
        document.journal = first(&response["publishers"]);
        document.year = year(response["publish_date"].as_str());
        for author in response["authors"].as_array().into_iter().flatten().take(5) {
            let Some(key) = author["key"]
                .as_str()
                .filter(|s| s.starts_with("/authors/") && !s.contains(".."))
            else {
                continue;
            };
            match network::json(
                self.client.get(format!(
                    "{}{}.json",
                    self.endpoints.openlibrary.trim_end_matches('/'),
                    key
                )),
                token,
            )
            .await
            {
                Ok(author) => {
                    if let Some(name) = author["name"].as_str() {
                        document.authors.push(name.into());
                    }
                }
                Err(e) if e.code == ErrorCode::Cancelled => return Err(e),
                Err(_) => {}
            }
        }
        Ok(document)
    }
    async fn elife(&self, id: &str, token: &CancellationToken) -> Result<Document> {
        let response = network::json(
            self.client
                .get(endpoint(&self.endpoints.elife, &["articles", id])?),
            token,
        )
        .await?;
        let doi = format!("10.7554/elife.{id}");
        let mut document = blank(
            response["title"]
                .as_str()
                .filter(|s| !s.trim().is_empty())
                .unwrap_or(&doi),
        );
        document.doi = Some(
            response["doi"]
                .as_str()
                .and_then(normalize_doi)
                .unwrap_or(doi)
                .to_lowercase(),
        );
        document.journal = Some("eLife".into());
        document.year = year(response["published"].as_str());
        document.authors = response["authors"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|a| a["name"]["preferred"].as_str())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
            .collect();
        if document.authors.is_empty() {
            document.authors = response["authorLine"]
                .as_str()
                .unwrap_or_default()
                .replace("...", ",")
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_owned)
                .collect();
        }
        document.keywords = dedup(
            response["keywords"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .chain(
                    response["subjects"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|s| s["name"].as_str()),
                ),
        );
        Ok(document)
    }

    pub async fn search_by_title(
        &self,
        title: &str,
        author: Option<&str>,
        token: &CancellationToken,
    ) -> Result<Option<Document>> {
        let query = normalize_title(title);
        if query.chars().count() < 4 {
            return Ok(None);
        }
        let mut request = self
            .client
            .get(endpoint(&self.endpoints.crossref, &["works"])?)
            .query(&[
                ("query.bibliographic", title),
                ("rows", "5"),
                ("mailto", "dev@otterpad.app"),
            ]);
        if let Some(author) = author.filter(|s| !s.is_empty()) {
            request = request.query(&[("query.author", author)]);
        }
        let response = network::json(request, token).await?;
        let mut best = None;
        let mut best_score = 0.0;
        for item in response["message"]["items"]
            .as_array()
            .into_iter()
            .flatten()
        {
            let document = crossref_document(item, None)?;
            if document.title.is_empty() {
                continue;
            }
            let score = dice(&query, &normalize_title(&document.title));
            if score > best_score && score >= 0.55 {
                best_score = score;
                best = Some(document);
            }
        }
        Ok(best)
    }
}

pub(crate) fn endpoint(base: &str, segments: &[&str]) -> Result<Url> {
    let mut url = Url::parse(base)
        .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "invalid service URL"))?;
    url.path_segments_mut()
        .map_err(|_| {
            OtterError::new(
                ErrorCode::InvalidArgument,
                "service URL has no hierarchical path",
            )
        })?
        .pop_if_empty()
        .extend(segments);
    Ok(url)
}

mod parsers;
use parsers::*;
pub use parsers::{dice, parse_arxiv, parse_pubmed};
