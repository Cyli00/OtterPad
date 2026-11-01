use std::{
    collections::{BTreeMap, HashSet},
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;
use zip::{ZipArchive, ZipWriter, write::SimpleFileOptions};

use crate::{
    ai::chat::now,
    error::{ErrorCode, OtterError, Result},
    files,
    storage::Storage,
    tasks::check,
};

const ROOT: &str = "otter_pad_backup";
const MAX_FILES: usize = 100_000;
const MAX_BYTES: u64 = 64 * 1024 * 1024 * 1024;
const MAX_MANIFEST: u64 = 64 * 1024 * 1024;
static STAGE_IDS: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BackupScope {
    Full,
    #[serde(alias = "data_only")]
    DataOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub app: String,
    pub format_version: u32,
    pub created_at: String,
    pub scope: BackupScope,
    pub database_checksum: Option<String>,
    pub file_checksums: Option<BTreeMap<String, String>>,
    #[serde(default)]
    pub data_format: Option<String>,
    #[serde(default)]
    pub device_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BackupStage {
    Snapshot,
    HashFiles,
    Pack,
    Validate,
    Extract,
    Prepare,
    Publish,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupProgress {
    pub stage: BackupStage,
    pub done: u64,
    pub total: Option<u64>,
}

/// Created beside the live data so publishing a prepared restore uses same-volume renames.
pub(crate) struct Stage {
    pub path: PathBuf,
}
impl Stage {
    pub fn new(parent: &Path, prefix: &str) -> Result<Self> {
        fs::create_dir_all(parent)?;
        let path = parent.join(format!(
            ".{prefix}-{}-{}-{}",
            std::process::id(),
            time::OffsetDateTime::now_utc().unix_timestamp_nanos(),
            STAGE_IDS.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path)?;
        Ok(Self { path })
    }
}
impl Drop for Stage {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

pub struct ExtractedBackup {
    pub manifest: Manifest,
    pub(crate) stage: Stage,
}
impl ExtractedBackup {
    pub fn directory(&self) -> &Path {
        &self.stage.path
    }
}

pub(crate) fn database_revision(storage: &Storage) -> Result<(i64, i64)> {
    let changes = storage
        .connection
        .query_row("SELECT total_changes()", [], |r| r.get(0))?;
    let version = storage
        .connection
        .pragma_query_value(None, "data_version", |r| r.get(0))?;
    Ok((changes, version))
}

pub(crate) fn snapshot(storage: &Storage, path: &Path) -> Result<()> {
    // VACUUM INTO accepts a bound filename expression; never interpolate user paths into SQL.
    storage.connection.execute(
        "VACUUM INTO ?1",
        [path
            .to_str()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "snapshot path UTF-8"))?],
    )?;
    crate::storage::repair_snapshot_index(path)?;
    File::open(path)?.sync_all()?;
    Ok(())
}

pub fn create(
    storage: &Storage,
    path: &Path,
    scope: BackupScope,
    device_name: Option<String>,
    token: &CancellationToken,
    mut progress: impl FnMut(BackupProgress),
) -> Result<Manifest> {
    check(token)?;
    let parent = storage
        .directory()
        .parent()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "storage parent"))?;
    let stage = Stage::new(parent, "backup")?;
    let revision = database_revision(storage)?;
    progress(BackupProgress {
        stage: BackupStage::Snapshot,
        done: 0,
        total: None,
    });
    let database = stage.path.join("otter.db");
    snapshot(storage, &database)?;
    super::backup::sanitize_snapshot(&database)?;
    progress(BackupProgress {
        stage: BackupStage::HashFiles,
        done: 0,
        total: None,
    });
    let library = storage.directory().join("library");
    let files = checksums(&library, Some(scope), token)?;
    let manifest = Manifest {
        app: "OtterPad".into(),
        format_version: 4,
        created_at: now()?,
        scope,
        database_checksum: Some(hash_file(&database, token)?),
        file_checksums: Some(files.clone()),
        data_format: Some("rust-v2".into()),
        device_name,
    };
    let manifest_bytes = serde_json::to_vec(&manifest)?;
    if files.len() + 2 > MAX_FILES || manifest_bytes.len() as u64 > MAX_MANIFEST {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "backup entry/manifest limit",
        ));
    }
    let output = stage.path.join("backup.zip");
    let mut zip = ZipWriter::new(File::create(&output)?);
    let options = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o600)
        .large_file(true);
    zip.start_file(format!("{ROOT}/manifest.json"), options)
        .map_err(zip_error)?;
    zip.write_all(&manifest_bytes)?;
    zip.start_file(format!("{ROOT}/db/otter.db"), options)
        .map_err(zip_error)?;
    copy_stream(&mut File::open(&database)?, &mut zip, token)?;
    for (index, (relative, expected)) in files.iter().enumerate() {
        check(token)?;
        let source = library.join(relative);
        zip.start_file(format!("{ROOT}/library/{relative}"), options)
            .map_err(zip_error)?;
        let mut input = File::open(source)?;
        let mut hash = Sha256::new();
        let mut buffer = [0u8; 64 * 1024];
        loop {
            check(token)?;
            let count = input.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            hash.update(&buffer[..count]);
            zip.write_all(&buffer[..count])?;
        }
        let actual = hash
            .finalize()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        if actual != *expected {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "library changed during backup",
            ));
        }
        progress(BackupProgress {
            stage: BackupStage::Pack,
            done: (index + 1) as u64,
            total: Some(files.len() as u64),
        });
    }
    zip.finish().map_err(zip_error)?.sync_all()?;
    progress(BackupProgress {
        stage: BackupStage::Validate,
        done: 0,
        total: None,
    });
    if revision != database_revision(storage)? || files != checksums(&library, Some(scope), token)?
    {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "data changed during backup",
        ));
    }
    check(token)?;
    // Source and target may be on different volumes; copy through a sibling temporary.
    atomic_copy(&output, path, token)?;
    Ok(manifest)
}

pub fn extract(
    path: &Path,
    parent: &Path,
    token: &CancellationToken,
    mut progress: impl FnMut(BackupProgress),
) -> Result<ExtractedBackup> {
    check(token)?;
    let stage = Stage::new(parent, "extract")?;
    let mut archive = ZipArchive::new(File::open(path)?).map_err(zip_error)?;
    if archive.len() > MAX_FILES {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "backup entry count limit",
        ));
    }
    let mut names = HashSet::new();
    let mut declared = 0u64;
    let mut actual = 0u64;
    let count = archive.len();
    for index in 0..count {
        check(token)?;
        let mut entry = archive.by_index(index).map_err(zip_error)?;
        let name = entry.name().map_err(zip_error)?.into_owned();
        safe_relative(name.trim_end_matches('/'))?;
        if !names.insert(name.to_lowercase()) || entry.is_symlink() {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "duplicate or linked backup entry",
            ));
        }
        declared = declared
            .checked_add(entry.size())
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "backup size overflow"))?;
        if declared > MAX_BYTES {
            return Err(OtterError::new(ErrorCode::InvalidData, "backup size limit"));
        }
        let Some(relative) = name.strip_prefix(&format!("{ROOT}/")) else {
            continue;
        };
        if relative.is_empty() || entry.is_dir() {
            continue;
        }
        let allowed = relative == "manifest.json"
            || relative == "db/otter.db"
            || relative.starts_with("library/");
        if !allowed {
            continue;
        }
        if relative == "manifest.json" && entry.size() > MAX_MANIFEST {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "backup manifest size limit",
            ));
        }
        let target = stage.path.join(relative);
        fs::create_dir_all(target.parent().unwrap())?;
        let mut output = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(target)?;
        let mut buffer = [0u8; 64 * 1024];
        let mut expanded = 0u64;
        loop {
            check(token)?;
            let count = entry.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            expanded += count as u64;
            if relative == "manifest.json" && expanded > MAX_MANIFEST {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "backup manifest size limit",
                ));
            }
            actual = actual
                .checked_add(count as u64)
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "backup size overflow"))?;
            if actual > MAX_BYTES {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "backup expanded size limit",
                ));
            }
            output.write_all(&buffer[..count])?;
        }
        output.sync_all()?;
        progress(BackupProgress {
            stage: BackupStage::Extract,
            done: (index + 1) as u64,
            total: Some(count as u64),
        });
    }
    let manifest: Manifest = serde_json::from_slice(&fs::read(stage.path.join("manifest.json"))?)?;
    if manifest.app != "OtterPad"
        || !matches!(manifest.format_version, 3 | 4)
        || (manifest.format_version == 4 && manifest.data_format.as_deref() != Some("rust-v2"))
    {
        return Err(OtterError::new(ErrorCode::Unsupported, "backup format"));
    }
    if manifest.format_version == 4
        && (manifest.database_checksum.is_none() || manifest.file_checksums.is_none())
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "backup checksums missing",
        ));
    }
    progress(BackupProgress {
        stage: BackupStage::Validate,
        done: 0,
        total: None,
    });
    if let Some(expected) = &manifest.database_checksum
        && hash_file(&stage.path.join("db/otter.db"), token)? != *expected
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "backup database checksum mismatch",
        ));
    }
    if let Some(expected) = &manifest.file_checksums
        && checksums(&stage.path.join("library"), None, token)? != *expected
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "backup library checksum mismatch",
        ));
    }
    if !stage.path.join("db/otter.db").is_file() {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "backup database missing",
        ));
    }
    Ok(ExtractedBackup { stage, manifest })
}

pub fn include(relative: &str, scope: BackupScope) -> bool {
    let parts: Vec<_> = relative.split('/').collect();
    if parts.iter().any(|p| p.starts_with('.'))
        || parts.last().is_some_and(|n| n.starts_with(".reader.html"))
    {
        return false;
    }
    if scope == BackupScope::Full {
        return true;
    }
    if parts.len() < 2 {
        return true;
    }
    !["ocr", "figures", "summary"].contains(&parts[1])
        && ![
            "source.pdf",
            "document.json",
            "structure.json",
            "ocr-current.json",
            "mineru.exports.zip",
            "extract.md",
        ]
        .contains(&parts[1])
        && !parts[1].starts_with("extract.")
}

mod io;
use io::*;
pub(crate) use io::{atomic_copy, checksums, copy_stream, hash_file, safe_relative};
