use std::{
    collections::{BTreeMap, HashSet},
    path::Path,
};

use reqwest::{Client, Method, RequestBuilder, Url};
use serde::{Deserialize, Serialize};
use time::{
    OffsetDateTime,
    format_description::well_known::{Rfc2822, Rfc3339},
};
use tokio_util::sync::CancellationToken;

use super::sigv4::{self, Credentials};
use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
    network::{self, TransferObserver, TransferProgress},
    tasks::{cancellable, check},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RemoteConfig {
    Webdav {
        server_url: String,
        username: String,
        remote_dir: String,
        file_name: String,
    },
    S3 {
        endpoint: String,
        region: String,
        bucket: String,
        object_key: String,
        path_style: bool,
        access_key: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteEntry {
    pub name: String,
    pub size: u64,
    pub modified_at: Option<i64>,
}

pub struct BackupRemote {
    config: RemoteConfig,
    secret: String,
    client: Client,
    base: Url,
    prefix: String,
    fixed_name: String,
}

impl BackupRemote {
    pub fn new(
        config: RemoteConfig,
        secret: String,
        proxy: Option<&str>,
        http2: bool,
    ) -> Result<Self> {
        let client = network::api_client(proxy, http2)?;
        let (endpoint, prefix, fixed_name) = match &config {
            RemoteConfig::Webdav {
                server_url,
                remote_dir,
                file_name,
                ..
            } => {
                let prefix = remote_dir.trim_matches('/');
                validate_segments(prefix)?;
                let name = if file_name.trim().is_empty() {
                    "otter_pad_backup.zip"
                } else {
                    file_name.trim()
                };
                files::component(name)?;
                (server_url, prefix.to_owned(), name.to_owned())
            }
            RemoteConfig::S3 {
                endpoint,
                region,
                bucket,
                object_key,
                access_key,
                ..
            } => {
                if region.trim().is_empty()
                    || bucket.trim().is_empty()
                    || bucket.contains(['/', '\\'])
                    || access_key.trim().is_empty()
                    || secret.is_empty()
                {
                    return Err(OtterError::new(
                        ErrorCode::InvalidArgument,
                        "S3 configuration",
                    ));
                }
                let key = object_key.trim().trim_start_matches('/');
                validate_segments(key)?;
                let (prefix, name) = key.rsplit_once('/').unwrap_or(("", key));
                files::component(name)?;
                (
                    endpoint,
                    if prefix.is_empty() {
                        String::new()
                    } else {
                        format!("{prefix}/")
                    },
                    name.to_owned(),
                )
            }
        };
        let base = Url::parse(endpoint.trim())
            .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "remote URL"))?;
        if !matches!(base.scheme(), "http" | "https")
            || base.host_str().is_none()
            || !base.username().is_empty()
            || base.password().is_some()
            || base.query().is_some()
            || base.fragment().is_some()
        {
            return Err(OtterError::new(ErrorCode::InvalidArgument, "remote URL"));
        }
        Ok(Self {
            config,
            secret,
            client,
            base,
            prefix,
            fixed_name,
        })
    }

    pub fn fixed_name(&self) -> &str {
        &self.fixed_name
    }

    fn webdav_url(&self, name: Option<&str>) -> Result<Url> {
        let mut url = self.base.clone();
        {
            let mut segments = url
                .path_segments_mut()
                .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "remote path"))?;
            segments.pop_if_empty();
            for segment in self.prefix.split('/').filter(|s| !s.is_empty()) {
                segments.push(segment);
            }
            if let Some(name) = name {
                segments.push(files::component(name)?);
            } else {
                segments.push("");
            }
        }
        Ok(url)
    }

    fn request(
        &self,
        method: Method,
        name: Option<&str>,
        payload_hash: &str,
        query: &[(String, String)],
    ) -> Result<RequestBuilder> {
        match &self.config {
            RemoteConfig::Webdav { username, .. } => Ok(self
                .client
                .request(method, self.webdav_url(name)?)
                .basic_auth(username, Some(&self.secret))),
            RemoteConfig::S3 {
                region,
                bucket,
                path_style,
                access_key,
                ..
            } => {
                let mut url = self.base.clone();
                if !path_style {
                    let host = format!("{}.{}", bucket.trim(), url.host_str().unwrap());
                    url.set_host(Some(&host)).map_err(|_| {
                        OtterError::new(ErrorCode::InvalidArgument, "S3 bucket host")
                    })?;
                }
                let mut path = url.path().trim_end_matches('/').to_owned();
                if *path_style {
                    path.push('/');
                    path.push_str(&sigv4::encode(bucket.trim(), false));
                }
                if let Some(name) = name {
                    files::component(name)?;
                    path.push('/');
                    path.push_str(&sigv4::encode(&format!("{}{name}", self.prefix), true));
                }
                if path.is_empty() {
                    path.push('/');
                }
                url.set_path(&path);
                let mut encoded: Vec<_> = query
                    .iter()
                    .map(|(k, v)| (sigv4::encode(k, false), sigv4::encode(v, false)))
                    .collect();
                encoded.sort();
                if !encoded.is_empty() {
                    url.set_query(Some(
                        &encoded
                            .iter()
                            .map(|(k, v)| format!("{k}={v}"))
                            .collect::<Vec<_>>()
                            .join("&"),
                    ));
                }
                let credentials = Credentials {
                    access_key: access_key.trim().into(),
                    secret_key: self.secret.clone(),
                };
                let headers = sigv4::sign(
                    &method,
                    &url,
                    &path,
                    query,
                    payload_hash,
                    region.trim(),
                    &credentials,
                    OffsetDateTime::now_utc(),
                    &BTreeMap::new(),
                )?;
                Ok(self.client.request(method, url).headers(headers))
            }
        }
    }

    pub async fn ping(&self, token: &CancellationToken) -> Result<()> {
        if let RemoteConfig::Webdav { username, .. } = &self.config {
            network::send(
                self.client
                    .request(Method::OPTIONS, self.base.clone())
                    .basic_auth(username, Some(&self.secret)),
                token,
            )
            .await?;
            return Ok(());
        }
        let method = if matches!(self.config, RemoteConfig::Webdav { .. }) {
            Method::OPTIONS
        } else {
            Method::HEAD
        };
        network::send(self.request(method, None, &sigv4::hash(b""), &[])?, token).await?;
        Ok(())
    }

    async fn directories(&self, token: &CancellationToken) -> Result<()> {
        let RemoteConfig::Webdav { username, .. } = &self.config else {
            return Ok(());
        };
        let mut url = self.base.clone();
        for segment in self.prefix.split('/').filter(|s| !s.is_empty()) {
            url.path_segments_mut()
                .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "WebDAV path"))?
                .pop_if_empty()
                .push(segment);
            let request = self
                .client
                .request(Method::from_bytes(b"MKCOL").unwrap(), url.clone())
                .basic_auth(username, Some(&self.secret));
            let response = cancellable(token, async { Ok(request.send().await?) }).await?;
            // RFC 4918 uses 405 for an already existing collection.
            if response.status().as_u16() != 405 {
                network::status(response.status())?;
            }
        }
        Ok(())
    }

    pub async fn upload(
        &self,
        path: &Path,
        name: &str,
        token: &CancellationToken,
        progress: Option<TransferObserver>,
    ) -> Result<()> {
        files::component(name)?;
        check(token)?;
        self.directories(token).await?;
        let body = network::upload_body(path, token, progress.clone()).await?;
        let length = body.length;
        let request = self
            .request(Method::PUT, Some(name), &body.sha256, &[])?
            .header("Content-Length", length)
            .body(body.body);
        network::send(request, token).await?;
        if let Some(progress) = progress {
            progress(TransferProgress {
                transferred: length,
                total: Some(length),
            });
        }
        Ok(())
    }

    pub async fn download(
        &self,
        name: &str,
        path: &Path,
        limit: u64,
        token: &CancellationToken,
        progress: Option<&TransferObserver>,
    ) -> Result<()> {
        files::component(name)?;
        let response = network::send(
            self.request(Method::GET, Some(name), &sigv4::hash(b""), &[])?,
            token,
        )
        .await?;
        network::download_to(response, path, limit, token, progress).await
    }

    pub async fn delete(&self, name: &str, token: &CancellationToken) -> Result<()> {
        files::component(name)?;
        network::send(
            self.request(Method::DELETE, Some(name), &sigv4::hash(b""), &[])?,
            token,
        )
        .await?;
        Ok(())
    }

    pub async fn list(&self, token: &CancellationToken) -> Result<Vec<RemoteEntry>> {
        match self.config {
            RemoteConfig::Webdav { .. } => self.list_webdav(token).await,
            RemoteConfig::S3 { .. } => self.list_s3(token).await,
        }
    }

    async fn list_webdav(&self, token: &CancellationToken) -> Result<Vec<RemoteEntry>> {
        let request=self.request(Method::from_bytes(b"PROPFIND").unwrap(),None,&sigv4::hash(b""),&[])?.header("Depth","1").header("Content-Type","application/xml; charset=utf-8").body("<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>");
        let bytes =
            network::bytes(network::send(request, token).await?, 8 * 1024 * 1024, token).await?;
        let document = xml(&bytes)?;
        if !document
            .root_element()
            .has_tag_name(("DAV:", "multistatus"))
        {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "WebDAV multistatus missing",
            ));
        }
        let root = self.webdav_url(None)?;
        let mut entries = Vec::new();
        for response in document
            .descendants()
            .filter(|n| n.has_tag_name(("DAV:", "response")))
        {
            let Some(href) = child(response, "href") else {
                continue;
            };
            let Ok(url) = root.join(href) else {
                continue;
            };
            if url.origin() != root.origin() {
                continue;
            }
            let Some(name) = url.path().strip_prefix(root.path()) else {
                continue;
            };
            if name.is_empty() || name.contains('/') {
                continue;
            }
            let name = decode(name)?;
            if files::component(&name).is_err() {
                continue;
            }
            for status in response
                .children()
                .filter(|n| n.has_tag_name(("DAV:", "propstat")))
            {
                let successful = child(status, "status")
                    .is_some_and(|s| s.split_whitespace().nth(1) == Some("200"));
                if !successful
                    || status
                        .descendants()
                        .any(|n| n.has_tag_name(("DAV:", "collection")))
                {
                    continue;
                }
                let size = status
                    .descendants()
                    .find(|n| n.has_tag_name(("DAV:", "getcontentlength")))
                    .and_then(|n| n.text())
                    .and_then(|s| s.trim().parse().ok())
                    .unwrap_or(0);
                let modified = status
                    .descendants()
                    .find(|n| n.has_tag_name(("DAV:", "getlastmodified")))
                    .and_then(|n| n.text())
                    .and_then(|s| OffsetDateTime::parse(s, &Rfc2822).ok())
                    .map(milliseconds);
                entries.push(RemoteEntry {
                    name: name.clone(),
                    size,
                    modified_at: modified,
                });
                break;
            }
        }
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(entries)
    }

    async fn list_s3(&self, token: &CancellationToken) -> Result<Vec<RemoteEntry>> {
        let mut entries = Vec::new();
        let mut continuation: Option<String> = None;
        let mut seen = HashSet::new();
        for _ in 0..1000 {
            let mut query = vec![
                ("list-type".into(), "2".into()),
                ("prefix".into(), self.prefix.clone()),
            ];
            if let Some(value) = &continuation {
                query.push(("continuation-token".into(), value.clone()));
            }
            let response = network::send(
                self.request(Method::GET, None, &sigv4::hash(b""), &query)?,
                token,
            )
            .await?;
            let bytes = network::bytes(response, 8 * 1024 * 1024, token).await?;
            let document = xml(&bytes)?;
            for object in document
                .descendants()
                .filter(|n| n.is_element() && n.tag_name().name() == "Contents")
            {
                let Some(key) = child(object, "Key") else {
                    continue;
                };
                let Some(name) = key.strip_prefix(&self.prefix) else {
                    continue;
                };
                if name.contains('/') || files::component(name).is_err() {
                    continue;
                }
                let size = child(object, "Size")
                    .and_then(|s| s.parse().ok())
                    .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "S3 object size"))?;
                let modified = child(object, "LastModified")
                    .and_then(|s| OffsetDateTime::parse(s, &Rfc3339).ok())
                    .map(milliseconds);
                entries.push(RemoteEntry {
                    name: name.into(),
                    size,
                    modified_at: modified,
                });
            }
            let root = document.root_element();
            if root.tag_name().name() != "ListBucketResult" {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "S3 list result missing",
                ));
            }
            if child(root, "IsTruncated") != Some("true") {
                entries.sort_by(|a, b| a.name.cmp(&b.name));
                return Ok(entries);
            }
            let next = child(root, "NextContinuationToken")
                .filter(|s| !s.is_empty())
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "S3 continuation missing"))?
                .to_owned();
            if !seen.insert(next.clone()) {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "S3 pagination cycle",
                ));
            }
            continuation = Some(next);
        }
        Err(OtterError::new(
            ErrorCode::InvalidData,
            "S3 pagination limit",
        ))
    }
}

mod response;
use response::*;
