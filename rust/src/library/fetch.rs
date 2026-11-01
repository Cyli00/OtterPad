//! Publisher landing-page, open-access and Europe PMC PDF acquisition.
use super::identifier::normalize_doi;
use crate::{
    error::{ErrorCode, OtterError, Result},
    network::{self, TransferObserver},
    sync::archive::Stage,
    tasks::{cancellable, check},
};
use futures_util::StreamExt;
use reqwest::{Client, Response, Url};
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{io::Read, path::Path, time::Duration};
use tokio_util::sync::CancellationToken;

const BROWSER: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const API_AGENT: &str = "OtterPad/0.2 (Rust; mailto:dev@otterpad.app)";
const PDF_LIMIT: u64 = 4 * 1024 * 1024 * 1024;
#[derive(Debug, Clone)]
pub struct PdfEndpoints {
    pub doi: String,
    pub unpaywall: String,
    pub pubmed: String,
    pub pmc: String,
}
impl Default for PdfEndpoints {
    fn default() -> Self {
        Self {
            doi: "https://doi.org/".into(),
            unpaywall: "https://api.unpaywall.org/v2/".into(),
            pubmed: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi".into(),
            pmc: "https://europepmc.org/articles/".into(),
        }
    }
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum PdfSource {
    Publisher,
    Citation,
    PublisherPattern,
    Unpaywall,
    EuropePmc,
    Direct,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchReport {
    pub source: PdfSource,
    pub warnings: Vec<ErrorCode>,
}
pub struct PdfFetcher {
    pub client: Client,
    pub endpoints: PdfEndpoints,
}
impl PdfFetcher {
    pub fn new(client: Client) -> Self {
        Self {
            client,
            endpoints: PdfEndpoints::default(),
        }
    }
    fn request(&self, url: Url) -> reqwest::RequestBuilder {
        self.client
            .get(url)
            .header("User-Agent", BROWSER)
            .header(
                "Accept",
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            )
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
    }
    pub async fn fetch_url(
        &self,
        url: &str,
        path: &Path,
        token: &CancellationToken,
        progress: Option<&TransferObserver>,
    ) -> Result<FetchReport> {
        self.download(http_url(url)?, None, path, token, progress)
            .await?;
        Ok(FetchReport {
            source: PdfSource::Direct,
            warnings: Vec::new(),
        })
    }
    pub async fn fetch_doi(
        &self,
        doi: &str,
        path: &Path,
        token: &CancellationToken,
        progress: Option<&TransferObserver>,
    ) -> Result<FetchReport> {
        let doi = normalize_doi(doi)
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "invalid PDF DOI"))?;
        let doi_url = endpoint(&self.endpoints.doi, &doi)?;
        let mut warnings = Vec::new();
        let mut landing = None;
        match network::send(
            self.request(doi_url.clone())
                .timeout(Duration::from_secs(60)),
            token,
        )
        .await
        {
            Ok(response) => {
                let real = response.url().clone();
                landing = Some(real.clone());
                let content_type = response
                    .headers()
                    .get("content-type")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                let disposition = response
                    .headers()
                    .get("content-disposition")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                if content_type.contains("application/pdf") || disposition.contains(".pdf") {
                    match save_pdf(response, path, token, progress).await {
                        Ok(()) => {
                            return Ok(FetchReport {
                                source: PdfSource::Publisher,
                                warnings,
                            });
                        }
                        Err(error) => record_error(error, &mut warnings)?,
                    }
                } else {
                    match prefix(response, 3 * 1024 * 1024, token).await {
                        Ok(bytes) => {
                            let candidate = if bytes.starts_with(b"%PDF-") {
                                Some(real.clone())
                            } else {
                                let base = real.clone();
                                crate::tasks::blocking(token, move || {
                                    Ok(citation_pdf_url(&String::from_utf8_lossy(&bytes), &base))
                                })
                                .await?
                            };
                            if let Some(candidate) = candidate {
                                match self
                                    .download(candidate, Some(&real), path, token, progress)
                                    .await
                                {
                                    Ok(()) => {
                                        return Ok(FetchReport {
                                            source: PdfSource::Citation,
                                            warnings,
                                        });
                                    }
                                    Err(error) => record_error(error, &mut warnings)?,
                                }
                            }
                        }
                        Err(error) => record_error(error, &mut warnings)?,
                    }
                }
            }
            Err(error) => record_error(error, &mut warnings)?,
        }
        if let Some(landing) = landing
            && let Some(url) = publisher_pdf_url(&landing, &doi)
        {
            match self
                .download(url, Some(&landing), path, token, progress)
                .await
            {
                Ok(()) => {
                    return Ok(FetchReport {
                        source: PdfSource::PublisherPattern,
                        warnings,
                    });
                }
                Err(error) => record_error(error, &mut warnings)?,
            }
        }
        let mut url = endpoint(&self.endpoints.unpaywall, &doi)?;
        url.query_pairs_mut()
            .append_pair("email", "dev@otterpad.app");
        let lookup = async {
            let response =
                network::send(self.client.get(url).header("User-Agent", API_AGENT), token).await?;
            let value: Value =
                serde_json::from_slice(&network::bytes(response, 8 * 1024 * 1024, token).await?)?;
            let url = value["best_oa_location"]["url_for_pdf"]
                .as_str()
                .ok_or_else(|| OtterError::new(ErrorCode::NotFound, "open access PDF missing"))?;
            self.download(http_url(url)?, None, path, token, progress)
                .await
        }
        .await;
        match lookup {
            Ok(()) => Ok(FetchReport {
                source: PdfSource::Unpaywall,
                warnings,
            }),
            Err(error) => {
                record_error(error, &mut warnings)?;
                Err(OtterError::new(
                    ErrorCode::NotFound,
                    "PDF sources exhausted",
                ))
            }
        }
    }
    pub async fn fetch_pmid(
        &self,
        pmid: &str,
        path: &Path,
        token: &CancellationToken,
        progress: Option<&TransferObserver>,
    ) -> Result<FetchReport> {
        if pmid.is_empty() || !pmid.bytes().all(|b| b.is_ascii_digit()) {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "invalid PDF PMID",
            ));
        }
        let response = network::send(
            self.client
                .get(http_url(&self.endpoints.pubmed)?)
                .header("User-Agent", API_AGENT)
                .query(&[("db", "pubmed"), ("id", pmid), ("retmode", "json")]),
            token,
        )
        .await?;
        let value: Value =
            serde_json::from_slice(&network::bytes(response, 8 * 1024 * 1024, token).await?)?;
        let pmcid = value["result"][pmid]["articleids"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|v| v["idtype"] == "pmc")
            .and_then(|v| v["value"].as_str())
            .filter(|s| {
                s.starts_with("PMC") && s[3..].bytes().all(|b| b.is_ascii_digit()) && s.len() > 3
            })
            .ok_or_else(|| OtterError::new(ErrorCode::NotFound, "PMCID missing"))?;
        let mut url = endpoint(&self.endpoints.pmc, pmcid)?;
        url.query_pairs_mut().append_pair("pdf", "render");
        self.download(url, None, path, token, progress).await?;
        Ok(FetchReport {
            source: PdfSource::EuropePmc,
            warnings: Vec::new(),
        })
    }
    async fn download(
        &self,
        url: Url,
        referer: Option<&Url>,
        path: &Path,
        token: &CancellationToken,
        progress: Option<&TransferObserver>,
    ) -> Result<()> {
        let mut request = self
            .request(url)
            .header(
                "Accept",
                "application/pdf,application/octet-stream;q=0.9,*/*;q=0.8",
            )
            .timeout(Duration::from_secs(180));
        if let Some(referer) = referer {
            request = request.header("Referer", referer.as_str());
        }
        let response = network::send(request, token).await?;
        save_pdf(response, path, token, progress).await
    }
}
pub fn citation_pdf_url(html: &str, base: &Url) -> Option<Url> {
    let document = Html::parse_document(html);
    let selector = Selector::parse("meta").expect("fixed meta selector");
    document.select(&selector).find_map(|element| {
        let name = element
            .value()
            .attr("name")
            .or_else(|| element.value().attr("property"))?;
        if !name.eq_ignore_ascii_case("citation_pdf_url") {
            return None;
        }
        let value = element.value().attr("content")?.trim();
        if value.is_empty() {
            return None;
        }
        let url = base.join(value).ok()?;
        (matches!(url.scheme(), "https" | "http")
            && url.username().is_empty()
            && url.password().is_none())
        .then_some(url)
    })
}
pub fn publisher_pdf_url(landing: &Url, doi: &str) -> Option<Url> {
    let host = landing.host_str()?.to_ascii_lowercase();
    let mut url = landing.clone();
    url.set_query(None);
    url.set_fragment(None);
    let path = landing.path();
    if host_is(&host, "arxiv.org") {
        let id = path.strip_prefix("/abs/")?;
        url.set_path(&format!("/pdf/{id}"));
    } else if host_is(&host, "biorxiv.org") || host_is(&host, "medrxiv.org") {
        let path = path.trim_end_matches('/');
        if !path.starts_with("/content/10.1101/") {
            return None;
        }
        url.set_path(&format!("{path}.full.pdf"));
    } else if host_is(&host, "link.springer.com") {
        url.set_path(&format!("/content/pdf/{doi}.pdf"));
    } else if host_is(&host, "nature.com") {
        let parts = path.trim_matches('/').split('/').collect::<Vec<_>>();
        if parts.len() < 2 || parts[parts.len() - 2] != "articles" {
            return None;
        }
        url.set_path(&format!("/articles/{}.pdf", parts.last()?));
    } else if host_is(&host, "onlinelibrary.wiley.com") {
        url.set_path(&format!("/doi/pdfdirect/{doi}"));
        url.set_query(Some("download=true"));
    } else if host_is(&host, "sciencedirect.com") || host_is(&host, "linkinghub.elsevier.com") {
        url.set_path(&format!("{path}/pdfft"));
        url.set_query(Some("download=true"));
    } else if host_is(&host, "pubs.acs.org") || host_is(&host, "tandfonline.com") {
        url.set_path(&format!("/doi/pdf/{doi}"));
    } else if host_is(&host, "pubs.rsc.org") {
        if !path.contains("articlelanding") {
            return None;
        }
        url.set_path(&path.replacen("articlelanding", "articlepdf", 1));
    } else if host_is(&host, "mdpi.com") {
        url.set_path(&format!("{}/pdf", path.trim_end_matches('/')));
    } else {
        return None;
    }
    Some(url)
}
fn host_is(host: &str, domain: &str) -> bool {
    host == domain
        || host
            .strip_suffix(domain)
            .is_some_and(|prefix| prefix.ends_with('.'))
}
fn http_url(value: &str) -> Result<Url> {
    let url =
        Url::parse(value).map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "PDF URL"))?;
    if !matches!(url.scheme(), "http" | "https")
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "PDF URL scheme/credentials",
        ));
    }
    Ok(url)
}
fn endpoint(base: &str, segment: &str) -> Result<Url> {
    let mut url = http_url(base)?;
    url.path_segments_mut()
        .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "PDF endpoint"))?
        .pop_if_empty()
        .push(segment);
    Ok(url)
}
fn record_error(error: OtterError, warnings: &mut Vec<ErrorCode>) -> Result<()> {
    if error.code == ErrorCode::Cancelled {
        Err(error)
    } else {
        warnings.push(error.code);
        Ok(())
    }
}
async fn prefix(response: Response, limit: usize, token: &CancellationToken) -> Result<Vec<u8>> {
    let mut stream = response.bytes_stream();
    let mut result = Vec::new();
    while let Some(chunk) =
        cancellable(token, async { Ok(stream.next().await.transpose()?) }).await?
    {
        result.extend_from_slice(&chunk[..chunk.len().min(limit - result.len())]);
        if result.len() == limit {
            break;
        }
    }
    Ok(result)
}
async fn save_pdf(
    response: Response,
    path: &Path,
    token: &CancellationToken,
    progress: Option<&TransferObserver>,
) -> Result<()> {
    check(token)?;
    let parent = path
        .parent()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "PDF destination parent"))?;
    let stage = Stage::new(parent, "pdf-fetch")?;
    let file = stage.path.join("source.pdf");
    network::download_to(response, &file, PDF_LIMIT, token, progress).await?;
    let mut header = [0; 5];
    if std::fs::File::open(&file)?.read_exact(&mut header).is_err() || &header != b"%PDF-" {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "downloaded content is not PDF",
        ));
    }
    check(token)?;
    // The download stage is a sibling, so this is a same-volume atomic replacement.
    std::fs::rename(file, path)?;
    #[cfg(unix)]
    std::fs::File::open(parent)?.sync_all()?;
    Ok(())
}
