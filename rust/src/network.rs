use std::time::Duration;

use futures_util::StreamExt;
use reqwest::{Client, Response, StatusCode};
use serde_json::Value;
use tokio_util::sync::CancellationToken;

use crate::{
    error::{ErrorCode, OtterError, Result},
    tasks::cancellable,
};

pub fn client(proxy: Option<&str>, http2: bool) -> Result<Client> {
    build_client(proxy, http2, true)
}

/// Credential-bearing API requests must not forward custom key headers on redirects.
pub fn api_client(proxy: Option<&str>, http2: bool) -> Result<Client> {
    build_client(proxy, http2, false)
}

fn build_client(proxy: Option<&str>, http2: bool, redirects: bool) -> Result<Client> {
    let mut builder = Client::builder()
        .connect_timeout(Duration::from_secs(30))
        .timeout(Duration::from_secs(600));
    if !redirects {
        builder = builder.redirect(reqwest::redirect::Policy::none());
    }
    if !http2 {
        builder = builder.http1_only();
    }
    if let Some(proxy) = proxy {
        builder = if proxy.is_empty() {
            builder.no_proxy()
        } else {
            builder.proxy(reqwest::Proxy::all(proxy).map_err(OtterError::from)?)
        };
    }
    Ok(builder.build()?)
}

pub fn status(status: StatusCode) -> Result<()> {
    if status.is_success() {
        return Ok(());
    }
    let code = match status.as_u16() {
        401 | 403 => ErrorCode::Authentication,
        404 => ErrorCode::NotFound,
        429 => ErrorCode::RateLimited,
        _ => ErrorCode::Remote,
    };
    Err(OtterError::new(code, format!("HTTP {}", status.as_u16())))
}

pub async fn send(request: reqwest::RequestBuilder, token: &CancellationToken) -> Result<Response> {
    cancellable(token, async {
        let response = request.send().await?;
        status(response.status())?;
        Ok(response)
    })
    .await
}

pub async fn api_response(response: Response, token: &CancellationToken) -> Result<Response> {
    let Err(mut error) = status(response.status()) else {
        return Ok(response);
    };
    match bytes(response, 64 * 1024, token).await {
        Ok(body) => {
            if let Ok(value) = serde_json::from_slice::<Value>(&body) {
                let exhausted = [
                    &value["error"]["type"],
                    &value["error"]["code"],
                    &value["code"],
                ]
                .iter()
                .filter_map(|v| v.as_str())
                .any(|code| {
                    matches!(
                        code,
                        "insufficient_quota"
                            | "billing_hard_limit_reached"
                            | "usage_limit_exceeded"
                            | "credit_balance_too_low"
                            | "OUT_OF_CREDITS"
                    )
                });
                if exhausted {
                    error.code = ErrorCode::QuotaExceeded;
                }
            }
        }
        Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
        Err(_) => {}
    }
    Err(error)
}

pub async fn send_api(
    request: reqwest::RequestBuilder,
    token: &CancellationToken,
) -> Result<Response> {
    let response = cancellable(token, async { Ok(request.send().await?) }).await?;
    api_response(response, token).await
}

pub async fn json(request: reqwest::RequestBuilder, token: &CancellationToken) -> Result<Value> {
    cancellable(token, async {
        Ok(send(request, token).await?.json().await?)
    })
    .await
}

pub async fn bytes(response: Response, limit: usize, token: &CancellationToken) -> Result<Vec<u8>> {
    if response
        .content_length()
        .is_some_and(|length| length > limit as u64)
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "HTTP body exceeds limit",
        ));
    }
    let mut stream = response.bytes_stream();
    let mut bytes = Vec::new();
    while let Some(chunk) =
        cancellable(token, async { Ok(stream.next().await.transpose()?) }).await?
    {
        if bytes.len().saturating_add(chunk.len()) > limit {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "HTTP body exceeds limit",
            ));
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TransferProgress {
    pub transferred: u64,
    pub total: Option<u64>,
}
pub type TransferObserver = std::sync::Arc<dyn Fn(TransferProgress) + Send + Sync>;

struct DownloadTemporary(std::path::PathBuf);
impl Drop for DownloadTemporary {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}
static DOWNLOAD_IDS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// Streams to a sibling temporary; cancellation/EOF/limit errors preserve the destination.
pub async fn download_to(
    response: Response,
    path: &std::path::Path,
    limit: u64,
    token: &CancellationToken,
    progress: Option<&TransferObserver>,
) -> Result<()> {
    use std::sync::atomic::Ordering;
    use tokio::io::AsyncWriteExt;
    crate::tasks::check(token)?;
    let total = response.content_length();
    if total.is_some_and(|n| n > limit) {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "download exceeds limit",
        ));
    }
    let parent = path
        .parent()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "download parent"))?;
    std::fs::create_dir_all(parent)?;
    let temporary_path = parent.join(format!(
        ".download-{}-{}.part",
        std::process::id(),
        DOWNLOAD_IDS.fetch_add(1, Ordering::Relaxed)
    ));
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary_path)?;
    let temporary = DownloadTemporary(temporary_path);
    let mut file = tokio::fs::File::from_std(file);
    let mut transferred = 0u64;
    if let Some(progress) = progress {
        progress(TransferProgress { transferred, total });
    }
    let mut stream = response.bytes_stream();
    while let Some(bytes) =
        cancellable(token, async { Ok(stream.next().await.transpose()?) }).await?
    {
        transferred = transferred
            .checked_add(bytes.len() as u64)
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "download size overflow"))?;
        if transferred > limit {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "download exceeds limit",
            ));
        }
        cancellable(token, async {
            file.write_all(&bytes).await?;
            Ok(())
        })
        .await?;
        if let Some(progress) = progress {
            progress(TransferProgress { transferred, total });
        }
    }
    if total.is_some_and(|n| n != transferred) {
        return Err(OtterError::new(
            ErrorCode::IncompleteResponse,
            "download content length mismatch",
        ));
    }
    cancellable(token, async {
        file.sync_all().await?;
        Ok(())
    })
    .await?;
    drop(file);
    crate::tasks::check(token)?;
    std::fs::rename(&temporary.0, path)?;
    #[cfg(unix)]
    std::fs::File::open(parent)?.sync_all()?;
    Ok(())
}

pub struct UploadBody {
    pub body: reqwest::Body,
    pub length: u64,
    pub sha256: String,
}

pub async fn upload_body(
    path: &std::path::Path,
    token: &CancellationToken,
    progress: Option<TransferObserver>,
) -> Result<UploadBody> {
    use sha2::{Digest, Sha256};
    use tokio::io::{AsyncReadExt, AsyncSeekExt};
    let mut file = cancellable(token, async { Ok(tokio::fs::File::open(path).await?) }).await?;
    let mut hash = Sha256::new();
    let mut length = 0u64;
    let mut buffer = vec![0u8; 64 * 1024];
    loop {
        let count = cancellable(token, async { Ok(file.read(&mut buffer).await?) }).await?;
        if count == 0 {
            break;
        }
        length += count as u64;
        hash.update(&buffer[..count]);
    }
    let metadata = file.metadata().await?;
    if metadata.len() != length {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "upload changed during hashing",
        ));
    }
    file.seek(std::io::SeekFrom::Start(0)).await?;
    let mut transferred = 0u64;
    let stream = tokio_util::io::ReaderStream::new(file).map(move |chunk| {
        if let Ok(bytes) = &chunk {
            transferred += bytes.len() as u64;
            if let Some(progress) = &progress {
                progress(TransferProgress {
                    transferred,
                    total: Some(length),
                });
            }
        }
        chunk
    });
    Ok(UploadBody {
        body: reqwest::Body::wrap_stream(stream),
        length,
        sha256: hash.finalize().iter().map(|b| format!("{b:02x}")).collect(),
    })
}
