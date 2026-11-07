use super::{
    archive::{self, BackupScope},
    remote::RemoteConfig,
};
use crate::{error::Result, library, storage::Storage, tasks::check};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, fs, path::Path};
use tokio_util::sync::CancellationToken;

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocumentFingerprint {
    pub id: String,
    pub content: String,
    pub metadata: String,
    pub files: String,
}
#[derive(Serialize, Deserialize)]
pub struct BackupSnapshot {
    pub version: u32,
    pub at: i64,
    pub scope: BackupScope,
    pub remote: String,
    pub device: Option<String>,
    pub documents: Vec<DocumentFingerprint>,
}
/// 文献相对上次备份快照的状态；变化时给出最显著的原因（内容 > 元数据 > 附属文件）。
pub enum BackupState {
    /// 还没有任何备份快照。
    NeverBackedUp,
    /// 上次备份之后新增的文献。
    Added,
    ContentChanged,
    MetadataChanged,
    FilesChanged,
    Unchanged,
}
pub struct DocumentBackupState {
    pub document_id: String,
    pub state: BackupState,
}
pub struct BackupStatus {
    pub last_backup_at: Option<i64>,
    pub last_scope: Option<BackupScope>,
    /// 上次备份的远端描述与设备名。
    pub last_remote: Option<String>,
    pub last_device: Option<String>,
    pub changed: bool,
    pub documents: Vec<DocumentBackupState>,
}

fn hash(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
pub fn fingerprints(
    storage: &Storage,
    token: &CancellationToken,
) -> Result<Vec<DocumentFingerprint>> {
    let mut result = Vec::new();
    for document in storage.documents(u32::MAX, 0)? {
        check(token)?;
        let notes = library::highlights(storage, &document.id)?;
        let mut stats = BTreeMap::new();
        let root = library::document_directory(storage, &document.id)?;
        stat_files(&root, &root, &document.id, token, &mut stats)?;
        result.push(DocumentFingerprint {
            id: document.id.clone(),
            content: document.content_hash.clone().unwrap_or_default(),
            metadata: hash(&serde_json::to_vec(&(document, notes))?),
            files: hash(&serde_json::to_vec(&stats)?),
        });
    }
    Ok(result)
}
fn stat_files(
    root: &Path,
    directory: &Path,
    id: &str,
    token: &CancellationToken,
    result: &mut BTreeMap<String, (u64, u128)>,
) -> Result<()> {
    if !directory.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(directory)? {
        check(token)?;
        let entry = entry?;
        if entry.file_type()?.is_symlink() {
            continue;
        }
        if entry.file_type()?.is_dir() {
            stat_files(root, &entry.path(), id, token, result)?;
        } else if entry.file_type()?.is_file() {
            let path = entry.path();
            let relative = format!(
                "{id}/{}",
                path.strip_prefix(root)
                    .unwrap()
                    .to_string_lossy()
                    .replace('\\', "/")
            );
            if archive::include(&relative, BackupScope::DataOnly) {
                let metadata = entry.metadata()?;
                result.insert(
                    relative,
                    (
                        metadata.len(),
                        metadata
                            .modified()?
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_nanos(),
                    ),
                );
            }
        }
    }
    Ok(())
}
pub fn load(storage: &Storage) -> Result<Option<BackupSnapshot>> {
    let Some(value) = storage.setting("last_backup_snapshot")? else {
        return Ok(None);
    };
    let value = if let Some(text) = value.as_str() {
        serde_json::from_str(text).ok()
    } else {
        Some(value)
    };
    // The old v1 stat/JSON fingerprints use Dart serialization. Treat them as a
    // previous baseline that needs one fresh backup, never as false proof of sync.
    Ok(value
        .and_then(|v| serde_json::from_value::<BackupSnapshot>(v).ok())
        .filter(|s| s.version == 2))
}
pub fn save(storage: &Storage, snapshot: &BackupSnapshot) -> Result<()> {
    storage.put_setting(
        "last_backup_snapshot",
        &serde_json::Value::String(serde_json::to_string(snapshot)?),
    )
}
pub fn status(storage: &Storage, token: &CancellationToken) -> Result<BackupStatus> {
    let current = fingerprints(storage, token)?;
    let previous = load(storage)?;
    let mut changed = previous
        .as_ref()
        .is_none_or(|s| s.documents.len() != current.len());
    let documents = current
        .into_iter()
        .map(|fingerprint| {
            let state = match &previous {
                None => {
                    changed = true;
                    BackupState::NeverBackedUp
                }
                Some(snapshot) => {
                    match snapshot.documents.iter().find(|d| d.id == fingerprint.id) {
                        Some(old) if old == &fingerprint => BackupState::Unchanged,
                        found => {
                            changed = true;
                            match found {
                                None => BackupState::Added,
                                Some(old) if old.content != fingerprint.content => {
                                    BackupState::ContentChanged
                                }
                                Some(old) if old.metadata != fingerprint.metadata => {
                                    BackupState::MetadataChanged
                                }
                                Some(_) => BackupState::FilesChanged,
                            }
                        }
                    }
                }
            };
            DocumentBackupState {
                document_id: fingerprint.id,
                state,
            }
        })
        .collect();
    Ok(BackupStatus {
        last_backup_at: previous.as_ref().map(|s| s.at),
        last_scope: previous.as_ref().map(|s| s.scope),
        last_remote: previous.as_ref().map(|s| s.remote.clone()),
        last_device: previous.and_then(|s| s.device),
        changed,
        documents,
    })
}
pub fn remote_identity(config: &RemoteConfig) -> Result<String> {
    Ok(hash(&serde_json::to_vec(config)?))
}
pub fn automatic_due(
    storage: &Storage,
    config: &RemoteConfig,
    now: i64,
    token: &CancellationToken,
) -> Result<bool> {
    let period = match storage
        .setting("auto_backup_interval")?
        .and_then(|v| v.as_str().map(str::to_owned))
        .as_deref()
    {
        Some("daily") => 24 * 3600 * 1000,
        Some("weekly") => 7 * 24 * 3600 * 1000,
        _ => return Ok(false),
    };
    if let Some(snapshot) = load(storage)? {
        if snapshot.remote != remote_identity(config)? {
            return Ok(true);
        }
        if now.saturating_sub(snapshot.at) < period {
            return Ok(false);
        }
        return Ok(status(storage, token)?.changed);
    }
    Ok(true)
}

pub fn automatic_configuration(storage: &Storage) -> Result<Option<(RemoteConfig, BackupScope)>> {
    let text = |key: &str, default: &str| -> Result<String> {
        Ok(storage
            .setting(key)?
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_else(|| default.into()))
    };
    if !matches!(
        text("auto_backup_interval", "off")?.as_str(),
        "daily" | "weekly"
    ) {
        return Ok(None);
    }
    let scope = if text("auto_backup_scope", "dataOnly")? == "full" {
        BackupScope::Full
    } else {
        BackupScope::DataOnly
    };
    let config = if text("backup_remote_type", "s3")? == "webdav" {
        let server_url = text("backup_webdav_server_url", "")?;
        let username = text("backup_webdav_username", "")?;
        if server_url.trim().is_empty() || username.trim().is_empty() {
            return Ok(None);
        }
        RemoteConfig::Webdav {
            server_url,
            username,
            remote_dir: text("backup_webdav_remote_dir", "/OtterPad")?,
            file_name: text("backup_webdav_file_name", "otter_pad_backup.zip")?,
        }
    } else {
        let endpoint = text("backup_s3_endpoint", "https://s3.amazonaws.com")?;
        let region = text("backup_s3_region", "us-east-1")?;
        let bucket = text("backup_s3_bucket", "")?;
        let access_key = text("backup_s3_access_key_id", "")?;
        if [&endpoint, &region, &bucket, &access_key]
            .iter()
            .any(|s| s.trim().is_empty())
        {
            return Ok(None);
        }
        RemoteConfig::S3 {
            endpoint,
            region,
            bucket,
            access_key,
            object_key: text("backup_s3_object_key", "otter-pad/otter_pad_backup.zip")?,
            path_style: storage
                .setting("backup_s3_use_path_style")?
                .and_then(|v| v.as_bool())
                .unwrap_or(true),
        }
    };
    Ok(Some((config, scope)))
}
