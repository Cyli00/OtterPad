use super::*;

pub(super) fn first(value: &Value) -> Option<String> {
    value.as_array()?.first().map(|v| {
        v.as_str()
            .map(str::to_owned)
            .unwrap_or_else(|| v.to_string())
    })
}
pub(super) fn year(value: Option<&str>) -> Option<String> {
    YEAR.find(value?).map(|m| m.as_str().into())
}
pub(super) fn person(given: Option<&str>, family: Option<&str>) -> String {
    [given, family]
        .into_iter()
        .flatten()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}
pub(super) fn dedup<'a>(values: impl Iterator<Item = &'a str>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    values
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .filter(|s| seen.insert(s.to_lowercase()))
        .map(str::to_owned)
        .collect()
}
pub(super) fn blank(title: &str) -> Document {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    let id = crate::library::FILE_ID.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    Document {
        id: format!("meta_{now}_{id}"),
        title: title.trim().into(),
        authors: vec![],
        journal: None,
        year: None,
        doi: None,
        keywords: vec![],
        content_hash: None,
        added_at: now,
    }
}
pub(super) fn crossref_document(value: &Value, doi: Option<&str>) -> Result<Document> {
    if !value.is_object() {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "missing Crossref message",
        ));
    }
    let mut document =
        blank(&first(&value["title"]).unwrap_or_else(|| doi.unwrap_or_default().into()));
    document.authors = value["author"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|a| person(a["given"].as_str(), a["family"].as_str()))
        .filter(|s| !s.is_empty())
        .collect();
    document.journal =
        first(&value["container-title"]).or_else(|| first(&value["short-container-title"]));
    document.doi = value["DOI"].as_str().or(doi).map(str::to_lowercase);
    for key in ["published-print", "published-online", "published"] {
        if let Some(y) = value[key]["date-parts"][0][0].as_i64() {
            document.year = Some(y.to_string());
            break;
        }
    }
    Ok(document)
}

pub(super) fn xml(text: &str) -> Result<roxmltree::Document<'_>> {
    roxmltree::Document::parse(text)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "invalid metadata XML"))
}
pub(super) fn child<'a, 'input>(node: Node<'a, 'input>, name: &str) -> Option<Node<'a, 'input>> {
    node.children().find(|n| n.has_tag_name(name))
}
pub(super) fn node_text(node: Node<'_, '_>) -> String {
    node.descendants()
        .filter(|n| n.is_text())
        .filter_map(|n| n.text())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
pub(super) fn child_text(node: Node<'_, '_>, name: &str) -> Option<String> {
    child(node, name).map(node_text).filter(|s| !s.is_empty())
}
pub fn parse_pubmed(text: &str, id: &str) -> Result<Document> {
    let xml = xml(text)?;
    let article = xml
        .descendants()
        .find(|n| n.has_tag_name("PubmedArticle"))
        .ok_or_else(|| OtterError::new(ErrorCode::NotFound, "PubMed article missing"))?;
    let medline = child(article, "MedlineCitation")
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "MedlineCitation missing"))?;
    let body = child(medline, "Article")
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "PubMed Article missing"))?;
    let title = child_text(body, "ArticleTitle").unwrap_or_else(|| id.into());
    let mut document = blank(title.strip_suffix('.').unwrap_or(&title));
    for author in child(body, "AuthorList")
        .into_iter()
        .flat_map(|n| n.children())
        .filter(|n| n.has_tag_name("Author"))
    {
        let family = child_text(author, "LastName");
        let given = child_text(author, "ForeName").or_else(|| child_text(author, "Initials"));
        let name = if family.is_some() {
            person(given.as_deref(), family.as_deref())
        } else {
            child_text(author, "CollectiveName").unwrap_or_default()
        };
        if !name.is_empty() {
            document.authors.push(name);
        }
    }
    if let Some(journal) = child(body, "Journal") {
        document.journal =
            child_text(journal, "Title").or_else(|| child_text(journal, "ISOAbbreviation"));
        if let Some(date) = journal.descendants().find(|n| n.has_tag_name("PubDate")) {
            document.year = child_text(date, "Year")
                .or_else(|| year(child_text(date, "MedlineDate").as_deref()));
        }
    }
    document.doi = article
        .descendants()
        .filter(|n| n.has_tag_name("ArticleId") && n.attribute("IdType") == Some("doi"))
        .map(node_text)
        .rfind(|s| !s.is_empty())
        .map(|s| s.to_lowercase());
    document.keywords = dedup(
        medline
            .descendants()
            .filter(|n| n.has_tag_name("DescriptorName") || n.has_tag_name("Keyword"))
            .map(node_text)
            .collect::<Vec<_>>()
            .iter()
            .map(String::as_str),
    );
    Ok(document)
}
pub fn parse_arxiv(text: &str, id: &str) -> Result<Document> {
    let xml = xml(text)?;
    let entry = xml
        .descendants()
        .find(|n| n.tag_name().name() == "entry")
        .ok_or_else(|| OtterError::new(ErrorCode::NotFound, "arXiv entry missing"))?;
    if child_text(entry, "id").is_none() {
        return Err(OtterError::new(
            ErrorCode::NotFound,
            "arXiv entry id missing",
        ));
    }
    let mut document = blank(&child_text(entry, "title").unwrap_or_else(|| id.into()));
    document.authors = entry
        .children()
        .filter(|n| n.tag_name().name() == "author")
        .filter_map(|n| child_text(n, "name"))
        .collect();
    document.journal = entry
        .descendants()
        .find(|n| n.tag_name().name() == "journal_ref")
        .map(node_text);
    document.year = year(child_text(entry, "published").as_deref());
    document.doi = entry
        .descendants()
        .find(|n| n.tag_name().name() == "doi")
        .map(node_text)
        .map(|s| s.to_lowercase())
        .or_else(|| arxiv_doi(id));
    Ok(document)
}
pub(super) fn normalize_title(text: &str) -> String {
    static NORMALIZE: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"[^a-z0-9一-鿿㐀-䶿]+").unwrap());
    NORMALIZE
        .replace_all(&text.to_lowercase(), " ")
        .trim()
        .into()
}
pub fn dice(a: &str, b: &str) -> f64 {
    if a == b {
        return 1.0;
    }
    let a: Vec<_> = a.encode_utf16().collect();
    let b: Vec<_> = b.encode_utf16().collect();
    if a.len() < 2 || b.len() < 2 {
        return 0.0;
    }
    let mut counts = BTreeMap::new();
    for pair in a.windows(2) {
        *counts.entry((pair[0], pair[1])).or_insert(0usize) += 1;
    }
    let mut intersection = 0;
    for pair in b.windows(2) {
        if let Some(n) = counts.get_mut(&(pair[0], pair[1]))
            && *n > 0
        {
            intersection += 1;
            *n -= 1;
        }
    }
    2.0 * intersection as f64 / (a.len() + b.len() - 2) as f64
}
