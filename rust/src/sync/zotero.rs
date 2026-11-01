pub(crate) mod mapper;
pub(crate) mod store;

pub use mapper::{ImportCandidate, PdfAttachment, local_candidates, to_document};
pub use store::{
    ImportReport, LocalSelection, cloud_since, import_cloud, import_local, library_version,
};

use std::{collections::HashSet, path::PathBuf, time::Duration};

use reqwest::{Client, Response, Url};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio_util::sync::CancellationToken;

use crate::{
    error::{ErrorCode, OtterError, Result},
    network,
    tasks::{cancellable, check},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchProgress {
    pub fetched: u64,
    pub total: Option<u64>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CloudLibrary {
    pub user_id: u64,
    pub version: u64,
    pub items: Vec<Value>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalLibrary {
    pub port: u16,
    pub server_id: Option<String>,
    pub items: Vec<Value>,
}

pub struct ZoteroClient {
    client: Client,
    local: Client,
    base: Url,
}
impl ZoteroClient {
    pub fn new(proxy: Option<&str>, http2: bool) -> Result<Self> {
        Self::with_endpoint("https://api.zotero.org/", proxy, http2)
    }
    /// Custom endpoints support private test servers; credentials never follow redirects.
    pub fn with_endpoint(base: &str, proxy: Option<&str>, http2: bool) -> Result<Self> {
        let base = Url::parse(base).map_err(|_| invalid("Zotero base URL"))?;
        if !matches!(base.scheme(), "https" | "http")
            || !base.username().is_empty()
            || base.password().is_some()
            || base.query().is_some()
            || base.fragment().is_some()
            || !base.path().ends_with('/')
        {
            return Err(invalid("Zotero base URL"));
        }
        Ok(Self {
            client: network::api_client(proxy, http2)?,
            local: Client::builder()
                .no_proxy()
                .redirect(reqwest::redirect::Policy::none())
                .connect_timeout(Duration::from_secs(5))
                .timeout(Duration::from_secs(30))
                .build()?,
            base,
        })
    }

    pub async fn user_id(&self, key: &str, token: &CancellationToken) -> Result<u64> {
        check(token)?;
        if key.is_empty() || !key.bytes().all(|b| b.is_ascii_alphanumeric()) {
            return Err(invalid("Zotero API key"));
        }
        let mut url = self.base.clone();
        url.path_segments_mut()
            .map_err(|_| invalid("Zotero base URL"))?
            .pop_if_empty()
            .extend(["keys", key]);
        let response = network::send(
            self.client.get(url).header("Zotero-API-Version", "3"),
            token,
        )
        .await?;
        let value: Value =
            serde_json::from_slice(&network::bytes(response, 1024 * 1024, token).await?)?;
        value["userID"]
            .as_u64()
            .or_else(|| value["userID"].as_str()?.parse().ok())
            .filter(|n| *n > 0)
            .ok_or_else(|| invalid("Zotero user ID"))
    }

    pub async fn fetch_cloud(
        &self,
        key: &str,
        user_id: u64,
        since: u64,
        token: &CancellationToken,
        progress: impl FnMut(FetchProgress),
    ) -> Result<CloudLibrary> {
        let path = format!("users/{user_id}/items/top");
        let (items, version) = self
            .pages(
                self.base
                    .join(&path)
                    .map_err(|_| invalid("Zotero items URL"))?,
                Some(key),
                None,
                Some(since),
                token,
                progress,
            )
            .await?;
        Ok(CloudLibrary {
            user_id,
            version: version.ok_or_else(|| invalid("Zotero library version missing"))?,
            items,
        })
    }

    pub async fn fetch_local(
        &self,
        port: u16,
        token: &CancellationToken,
        progress: impl FnMut(FetchProgress),
    ) -> Result<LocalLibrary> {
        let response = self.local_get(port, "", None, token).await?;
        if header(&response, "zotero-api-version").as_deref() != Some("3") {
            return Err(OtterError::new(
                ErrorCode::Unsupported,
                "Zotero local API version",
            ));
        }
        let server_id = header(&response, "zotero-server-id");
        let (items, _) = self
            .pages(
                local_url(port, "users/0/items")?,
                None,
                server_id.as_deref(),
                None,
                token,
                progress,
            )
            .await?;
        Ok(LocalLibrary {
            port,
            server_id,
            items,
        })
    }

    pub async fn verify_local(
        &self,
        library: &LocalLibrary,
        token: &CancellationToken,
    ) -> Result<()> {
        self.local_get(library.port, "", library.server_id.as_deref(), token)
            .await?;
        Ok(())
    }

    pub async fn attachment_path(
        &self,
        library: &LocalLibrary,
        key: &str,
        token: &CancellationToken,
    ) -> Result<Option<PathBuf>> {
        validate_key(key)?;
        let response = self
            .local_get(
                library.port,
                &format!("users/0/items/{key}/file/view/url"),
                library.server_id.as_deref(),
                token,
            )
            .await?;
        let bytes = network::bytes(response, 64 * 1024, token).await?;
        let text = std::str::from_utf8(&bytes)
            .map_err(|_| invalid("Zotero attachment URL UTF-8"))?
            .trim();
        if text.is_empty() || text == "false" {
            return Ok(None);
        }
        let mut url = Url::parse(text).map_err(|_| invalid("Zotero attachment URL"))?;
        if url.scheme() != "file"
            || url
                .host_str()
                .is_some_and(|h| !h.is_empty() && h != "localhost")
            || url.query().is_some()
            || url.fragment().is_some()
            || !url.path().to_ascii_lowercase().ends_with(".pdf")
        {
            return Err(invalid("Zotero attachment must be a local PDF"));
        }
        url.set_host(None)
            .map_err(|_| invalid("Zotero file host"))?;
        Ok(Some(
            url.to_file_path()
                .map_err(|_| invalid("Zotero local file path"))?,
        ))
    }

    async fn local_get(
        &self,
        port: u16,
        path: &str,
        server: Option<&str>,
        token: &CancellationToken,
    ) -> Result<Response> {
        let mut request = self
            .local
            .get(local_url(port, path)?)
            .header("Zotero-API-Version", "3");
        if let Some(server) = server {
            request = request.header("Zotero-Server-ID", server);
        }
        let response = cancellable(token, async { Ok(request.send().await?) }).await?;
        if response.status().as_u16() == 412 {
            return Err(changed());
        }
        network::status(response.status())?;
        verify_server(&response, server)?;
        Ok(response)
    }

    async fn pages(
        &self,
        url: Url,
        key: Option<&str>,
        server: Option<&str>,
        since: Option<u64>,
        token: &CancellationToken,
        mut progress: impl FnMut(FetchProgress),
    ) -> Result<(Vec<Value>, Option<u64>)> {
        let mut items = Vec::new();
        let mut seen = HashSet::new();
        let mut version = None;
        let mut total = None;
        loop {
            check(token)?;
            let client = if since.is_some() {
                &self.client
            } else {
                &self.local
            };
            let mut request = client
                .get(url.clone())
                .header("Zotero-API-Version", "3")
                .query(&[
                    ("format", "json".to_owned()),
                    ("limit", "100".into()),
                    ("start", items.len().to_string()),
                    ("sort", "dateAdded".into()),
                    ("direction", "asc".into()),
                ]);
            if let Some(key) = key {
                request = request.header("Zotero-API-Key", key);
            }
            if let Some(since) = since {
                request = request.query(&[("since", since)]);
            }
            if let Some(server) = server {
                request = request.header("Zotero-Server-ID", server);
            }
            let response = cancellable(token, async { Ok(request.send().await?) }).await?;
            if response.status().as_u16() == 412 {
                return Err(changed());
            }
            network::status(response.status())?;
            verify_server(&response, server)?;
            let current = number_header(&response, "last-modified-version")?;
            if !items.is_empty() && version != current {
                return Err(changed());
            }
            version = current;
            let current_total = number_header(&response, "total-results")?;
            if total.is_some() && current_total != total {
                return Err(changed());
            }
            total = current_total;
            let backoff = number_header(&response, "backoff")?;
            let page: Vec<Value> =
                serde_json::from_slice(&network::bytes(response, 32 * 1024 * 1024, token).await?)?;
            let count = page.len();
            if count > 100 || items.len().saturating_add(count) > 1_000_000 {
                return Err(invalid("Zotero item count limit"));
            }
            for item in page {
                let key = item["key"]
                    .as_str()
                    .ok_or_else(|| invalid("Zotero item key"))?;
                validate_key(key)?;
                if !item["data"].is_object() {
                    return Err(invalid("Zotero item data"));
                }
                if !seen.insert(key.to_owned()) {
                    return Err(changed());
                }
                items.push(item);
            }
            let fetched = items.len() as u64;
            if total.is_some_and(|n| fetched > n || (count == 0 && fetched < n)) {
                return Err(changed());
            }
            progress(FetchProgress { fetched, total });
            if total.is_some_and(|n| fetched >= n) || (total.is_none() && count < 100) {
                break;
            }
            if let Some(seconds) = backoff {
                cancellable(token, async {
                    tokio::time::sleep(Duration::from_secs(seconds)).await;
                    Ok(())
                })
                .await?;
            }
        }
        Ok((items, version))
    }
}

pub fn local_source(library: &LocalLibrary, directory: Option<&std::path::Path>) -> Result<String> {
    if let Some(id) = library.server_id.as_deref().filter(|s| !s.is_empty()) {
        return Ok(format!("server:{id}:personal"));
    }
    let directory =
        directory.ok_or_else(|| invalid("Zotero directory required without server ID"))?;
    if !directory.join("zotero.sqlite").is_file() {
        return Err(invalid("Zotero directory database missing"));
    }
    let path = directory
        .canonicalize()?
        .to_str()
        .ok_or_else(|| invalid("Zotero directory UTF-8"))?
        .to_owned();
    let path = if cfg!(windows) {
        path.to_lowercase()
    } else {
        path
    };
    Ok(format!("directory:{path}:personal"))
}

fn local_url(port: u16, path: &str) -> Result<Url> {
    if port == 0 {
        return Err(invalid("Zotero local port"));
    }
    Url::parse(&format!("http://127.0.0.1:{port}/api/{path}"))
        .map_err(|_| invalid("Zotero local URL"))
}
fn header(response: &Response, name: &str) -> Option<String> {
    response
        .headers()
        .get(name)?
        .to_str()
        .ok()
        .map(str::to_owned)
}
fn number_header(response: &Response, name: &str) -> Result<Option<u64>> {
    header(response, name)
        .map(|s| s.parse().map_err(|_| invalid("Zotero numeric header")))
        .transpose()
}
fn verify_server(response: &Response, expected: Option<&str>) -> Result<()> {
    if expected.is_some() && header(response, "zotero-server-id").as_deref() != expected {
        Err(changed())
    } else {
        Ok(())
    }
}
fn validate_key(key: &str) -> Result<()> {
    if key.len() == 8
        && key
            .bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
    {
        Ok(())
    } else {
        Err(invalid("Zotero item key"))
    }
}
fn invalid(detail: &str) -> OtterError {
    OtterError::new(ErrorCode::InvalidData, detail)
}
fn changed() -> OtterError {
    OtterError::new(ErrorCode::Conflict, "Zotero library changed")
}
