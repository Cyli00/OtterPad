use reqwest::Client;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use crate::{
    error::{ErrorCode, OtterError, Result},
    network,
    tasks::check,
};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SearchProvider {
    Tavily,
    Exa,
    Brave,
}

/// Memory-only key: deliberately has no Serialize or Debug implementation.
pub struct SearchService {
    pub provider: SearchProvider,
    pub endpoint: String,
    key: String,
    client: Client,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub title: String,
    pub url: String,
    pub text: String,
    pub published_at: Option<String>,
}

impl SearchService {
    pub fn new(
        proxy: Option<&str>,
        http2: bool,
        provider: SearchProvider,
        key: String,
    ) -> Result<Self> {
        let client = network::api_client(proxy, http2)?;
        let endpoint = match provider {
            SearchProvider::Tavily => "https://api.tavily.com/search",
            SearchProvider::Exa => "https://api.exa.ai/search",
            SearchProvider::Brave => "https://api.search.brave.com/res/v1/web/search",
        }
        .into();
        Ok(Self {
            client,
            provider,
            endpoint,
            key,
        })
    }

    pub async fn search(
        &self,
        query: &str,
        token: &CancellationToken,
    ) -> Result<Vec<SearchResult>> {
        if query.trim().is_empty() || query.len() > 4096 || self.key.is_empty() {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "search configuration/query",
            ));
        }
        let request = match self.provider {
            SearchProvider::Tavily => self.client.post(&self.endpoint).bearer_auth(&self.key).json(&json!({"query":query,"max_results":5})),
            SearchProvider::Exa => self.client.post(&self.endpoint).header("x-api-key",&self.key).json(&json!({"query":query,"numResults":5,"contents":{"text":{"maxCharacters":2000}}})),
            SearchProvider::Brave => self.client.get(&self.endpoint).header("X-Subscription-Token",&self.key).query(&[("q",query),("count","5")]),
        };
        let bytes =
            network::bytes(network::send(request, token).await?, 8 * 1024 * 1024, token).await?;
        let value: Value = serde_json::from_slice(&bytes)?;
        let entries = match self.provider {
            SearchProvider::Brave => &value["web"]["results"],
            _ => &value["results"],
        };
        let Some(entries) = entries.as_array() else {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "search result structure",
            ));
        };
        Ok(entries
            .iter()
            .take(5)
            .filter_map(|entry| {
                let url = entry["url"].as_str()?;
                if !reqwest::Url::parse(url).is_ok_and(|u| matches!(u.scheme(), "http" | "https")) {
                    return None;
                }
                let field = match self.provider {
                    SearchProvider::Tavily => "content",
                    SearchProvider::Exa => "text",
                    SearchProvider::Brave => "description",
                };
                Some(SearchResult {
                    title: entry["title"].as_str().unwrap_or("").into(),
                    url: url.into(),
                    text: entry[field]
                        .as_str()
                        .unwrap_or("")
                        .chars()
                        .take(4000)
                        .collect(),
                    published_at: entry["published_date"]
                        .as_str()
                        .or_else(|| entry["publishedDate"].as_str())
                        .map(str::to_owned),
                })
            })
            .collect())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UrlContext {
    pub url: String,
    pub title: String,
    pub text: String,
}

pub async fn fetch_context(
    client: &Client,
    message: &str,
    token: &CancellationToken,
) -> Result<Vec<UrlContext>> {
    let regex = regex::Regex::new(r#"https?://[^\s<>\"'⟪⟫]+"#).unwrap();
    let mut urls = Vec::new();
    for matched in regex.find_iter(message) {
        let url = matched
            .as_str()
            .trim_end_matches(['.', ',', ';', ':', ')', ']', '}', '。', '，', '；']);
        if !urls.contains(&url) {
            urls.push(url);
        }
        if urls.len() == 3 {
            break;
        }
    }
    let mut results = Vec::new();
    let scripts = regex::Regex::new(
        r"(?is)<(?:script|style|noscript)\b[^>]*>.*?</(?:script|style|noscript)\s*>",
    )
    .unwrap();
    for url in urls {
        check(token)?;
        let result = async {
            let response = network::send(
                client
                    .get(url)
                    .header("User-Agent", "Mozilla/5.0 OtterPad/0.2"),
                token,
            )
            .await?;
            let mime = response
                .headers()
                .get("content-type")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .to_lowercase();
            if !(mime.starts_with("text/") || mime.contains("json") || mime.contains("xml")) {
                return Err(OtterError::new(ErrorCode::Unsupported, "URL content type"));
            }
            let bytes = network::bytes(response, 2 * 1024 * 1024, token).await?;
            let text = std::str::from_utf8(&bytes)
                .map_err(|_| OtterError::new(ErrorCode::InvalidData, "URL text encoding"))?;
            let (title, text) = if mime.contains("html") {
                // Removing entire script/style nodes before text extraction avoids exposing scripts as prose.
                let clean = scripts.replace_all(text, "");
                let document = Html::parse_document(&clean);
                let title = document
                    .select(&Selector::parse("title").unwrap())
                    .next()
                    .map(|e| e.text().collect::<String>())
                    .unwrap_or_default();
                let body = document
                    .select(&Selector::parse("body").unwrap())
                    .next()
                    .map(|e| e.text().collect::<Vec<_>>().join(" "))
                    .unwrap_or_default();
                (title, body.split_whitespace().collect::<Vec<_>>().join(" "))
            } else {
                (String::new(), text.to_owned())
            };
            Ok::<_, OtterError>(UrlContext {
                url: url.into(),
                title,
                text: text.chars().take(10_000).collect(),
            })
        }
        .await;
        match result {
            Ok(page) => results.push(page),
            Err(e) if e.code == ErrorCode::Cancelled => return Err(e),
            Err(_) => {} // An unavailable page does not prevent the conversation.
        }
    }
    Ok(results)
}
