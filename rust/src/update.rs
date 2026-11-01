//! Release discovery and APK transfer; OS installation stays with the host app.
use crate::{
    error::{ErrorCode, OtterError, Result},
    network::{self, TransferObserver},
    tasks::check as check_cancel,
};
use serde_json::Value;
use std::path::Path;
use tokio_util::sync::CancellationToken;

pub const RELEASES_URL: &str = "https://api.github.com/repos/Cyli00/OtterPad/releases/latest";
pub struct ApkAsset {
    pub url: String,
    pub size: u64,
    pub abi: String,
}
pub struct UpdateInfo {
    pub current_version: String,
    pub remote_version: String,
    pub has_update: bool,
    pub ignored: bool,
    pub release_url: String,
    pub changelog: Vec<String>,
    pub apk: Option<ApkAsset>,
}
pub fn compare_versions(a: &str, b: &str) -> std::cmp::Ordering {
    let a: Vec<_> = a
        .split('.')
        .map(|s| s.parse::<u64>().unwrap_or(0))
        .collect();
    let b: Vec<_> = b
        .split('.')
        .map(|s| s.parse::<u64>().unwrap_or(0))
        .collect();
    (0..a.len().max(b.len()))
        .find_map(|i| {
            let order = a.get(i).unwrap_or(&0).cmp(b.get(i).unwrap_or(&0));
            (order != std::cmp::Ordering::Equal).then_some(order)
        })
        .unwrap_or(std::cmp::Ordering::Equal)
}
pub fn parse(
    value: &Value,
    current: &str,
    abis: &[String],
    ignored: Option<&str>,
) -> Result<UpdateInfo> {
    let tag = value["tag_name"]
        .as_str()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "release tag missing"))?;
    let version = tag.strip_prefix('v').unwrap_or(tag);
    let url = value["html_url"]
        .as_str()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "release URL missing"))?;
    let mut apk = None;
    if let Some(assets) = value["assets"].as_array() {
        for abi in abis {
            if let Some(asset) = assets.iter().find(|asset| {
                asset["name"]
                    .as_str()
                    .is_some_and(|name| name.ends_with(&format!("-{abi}.apk")))
            }) {
                apk = Some(ApkAsset {
                    url: asset["browser_download_url"]
                        .as_str()
                        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "APK URL missing"))?
                        .into(),
                    size: asset["size"].as_u64().unwrap_or(0),
                    abi: abi.clone(),
                });
                break;
            }
        }
    }
    Ok(UpdateInfo {
        current_version: current.into(),
        remote_version: version.into(),
        has_update: compare_versions(version, current).is_gt(),
        ignored: ignored == Some(version),
        release_url: url.into(),
        changelog: value["body"]
            .as_str()
            .unwrap_or("")
            .lines()
            .map(str::trim)
            .filter_map(|s| s.strip_prefix("- "))
            .map(|s| s.trim().to_owned())
            .collect(),
        apk,
    })
}
pub async fn check(
    client: &reqwest::Client,
    endpoint: &str,
    current: &str,
    abis: &[String],
    ignored: Option<&str>,
    token: &CancellationToken,
) -> Result<UpdateInfo> {
    let value = network::json(
        client
            .get(endpoint)
            .header("User-Agent", "OtterPad/0.2 (Rust; mailto:dev@otterpad.app)"),
        token,
    )
    .await?;
    parse(&value, current, abis, ignored)
}
pub async fn download(
    client: &reqwest::Client,
    asset: &ApkAsset,
    path: &Path,
    token: &CancellationToken,
    progress: Option<&TransferObserver>,
) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "APK destination"))?;
    let stage = crate::sync::archive::Stage::new(parent, "update")?;
    let target = stage.path.join("download.apk");
    let response = network::send(client.get(&asset.url), token).await?;
    network::download_to(response, &target, 1024 * 1024 * 1024, token, progress).await?;
    let length = std::fs::metadata(&target)?.len();
    if length == 0 || (asset.size != 0 && length != asset.size) {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "APK transfer size differs from release",
        ));
    }
    check_cancel(token)?;
    std::fs::rename(target, path)?;
    #[cfg(unix)]
    std::fs::File::open(parent)?.sync_all()?;
    Ok(())
}
