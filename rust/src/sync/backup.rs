use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
};

use rusqlite::{Connection, OptionalExtension, params, types::Value as SqlValue};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::archive::{self, BackupProgress, BackupScope, BackupStage, Manifest, Stage};
use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
    library::{self, Favorite},
    migrate,
    storage::Storage,
    tasks::check,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RestoreScope {
    Full,
    LibraryOnly,
    SettingsOnly,
}
impl RestoreScope {
    fn library(self) -> bool {
        self != Self::SettingsOnly
    }
    fn settings(self) -> bool {
        self != Self::LibraryOnly
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RestoreMode {
    Overwrite,
    Merge,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MergeReport {
    pub documents_added: usize,
    pub highlights_added: usize,
    pub files_copied: usize,
    pub settings_added: usize,
    pub skipped_orphans: usize,
    pub document_ids: BTreeMap<String, String>,
}

pub struct PreparedRestore {
    stage: Stage,
    root: PathBuf,
    revision: (i64, i64),
    files: BTreeMap<String, String>,
    pub manifest: Manifest,
    pub report: MergeReport,
    /// 备份包里加密的凭据；恢复范围不含设置时为 None。
    pub credentials: Option<Vec<u8>>,
}

/// Preparation never changes the live database or library. Publish only after releasing PDF/log handles.
pub fn prepare(
    storage: &Storage,
    archive_path: &Path,
    scope: RestoreScope,
    mode: RestoreMode,
    token: &CancellationToken,
    mut progress: impl FnMut(BackupProgress),
) -> Result<PreparedRestore> {
    check(token)?;
    let root = storage
        .directory()
        .parent()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "restore root"))?
        .to_path_buf();
    let revision = archive::database_revision(storage)?;
    let baseline = archive::checksums(
        &storage.directory().join("library"),
        Some(BackupScope::Full),
        token,
    )?;
    let extracted = archive::extract(archive_path, &root, token, &mut progress)?;
    let manifest = extracted.manifest.clone();
    let sealed = extracted.directory().join(archive::CREDENTIALS);
    let credentials = if scope.settings() && sealed.is_file() {
        Some(fs::read(sealed)?)
    } else {
        None
    };
    let source_stage = Stage::new(&root, "restore-source")?;
    let mut skipped_orphans = 0;
    if manifest.format_version == 3 {
        if mode == RestoreMode::Merge {
            skipped_orphans = remove_legacy_orphans(&extracted.directory().join("db/otter.db"))?;
        }
        let mut normalized = Storage::open(&source_stage.path)?;
        let report = migrate::run(&mut normalized, extracted.directory(), token, |_| {})?;
        if !report.complete {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "legacy backup migration incomplete",
            ));
        }
        drop(normalized);
    } else {
        let target = source_stage.path.join("v2");
        fs::create_dir_all(&target)?;
        archive::atomic_copy(
            &extracted.directory().join("db/otter.db"),
            &target.join("otter.db"),
            token,
        )?;
        let library = extracted.directory().join("library");
        if library.is_dir() {
            fs::rename(library, target.join("library"))?;
        }
    }
    let source = Storage::open(&source_stage.path)?;
    validate(&source)?;
    let stage = Stage::new(&root, "restore")?;
    let directory = stage.path.join("v2");
    fs::create_dir_all(&directory)?;
    archive::snapshot(storage, &directory.join("otter.db"))?;
    let mut target = Storage::open(&stage.path)?;
    progress(BackupProgress {
        stage: BackupStage::Prepare,
        done: 0,
        total: None,
    });
    let mut report = MergeReport {
        skipped_orphans,
        ..Default::default()
    };
    // A prepared replacement owns all its files; failed/cancelled preparation can be discarded wholesale.
    copy_checked(
        &storage.directory().join("library"),
        &target.directory().join("library"),
        &baseline,
        token,
    )?;
    match mode {
        RestoreMode::Overwrite => {
            if scope.library() {
                overwrite_library(&source, &mut target)?;
                let library = target.directory().join("library");
                fs::remove_dir_all(&library)?;
                fs::create_dir_all(&library)?;
                let source_files = archive::checksums(
                    &source.directory().join("library"),
                    Some(BackupScope::Full),
                    token,
                )?;
                report.files_copied = copy_checked(
                    &source.directory().join("library"),
                    &library,
                    &source_files,
                    token,
                )?;
                if manifest.scope == BackupScope::DataOnly {
                    let retained: HashSet<_> = target
                        .documents(u32::MAX, 0)?
                        .into_iter()
                        .map(|d| d.id)
                        .collect();
                    let heavy = baseline
                        .iter()
                        .filter(|(name, _)| {
                            !archive::include(name, BackupScope::DataOnly)
                                && name
                                    .split('/')
                                    .next()
                                    .is_some_and(|id| retained.contains(id))
                        })
                        .map(|(k, v)| (k.clone(), v.clone()))
                        .collect();
                    copy_checked(
                        &storage.directory().join("library"),
                        &library,
                        &heavy,
                        token,
                    )?;
                }
                if scope == RestoreScope::Full {
                    replace_meta(&source, &target)?;
                }
            }
            if scope.settings() {
                target.connection.execute("DELETE FROM settings", [])?;
                report.settings_added = copy_settings(&source, &target, false)?;
            }
        }
        RestoreMode::Merge => {
            if scope.library() {
                merge_library(&source, &mut target, &mut report, token)?;
            }
            if scope.settings() {
                report.settings_added = copy_settings(&source, &target, true)?;
            }
            if scope.library() {
                merge_zotero(
                    &source,
                    &target,
                    &report.document_ids,
                    &mut report.skipped_orphans,
                )?;
            }
        }
    }
    if scope.library() {
        repair_files(&target, token)?;
    }
    // Restoring a v2 namespace must never trigger automatic re-import from a local v1 directory.
    if scope.library() {
        target.connection.execute("INSERT INTO meta VALUES ('migration:v1:complete','1') ON CONFLICT(metaKey) DO UPDATE SET value='1'",[])?;
    }
    validate(&target)?;
    target
        .connection
        .execute_batch("PRAGMA wal_checkpoint(TRUNCATE)")?;
    drop(target);
    drop(source);
    sync_directories(&directory)?;
    check(token)?;
    if revision != archive::database_revision(storage)?
        || baseline
            != archive::checksums(
                &storage.directory().join("library"),
                Some(BackupScope::Full),
                token,
            )?
    {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "live data changed during restore preparation",
        ));
    }
    Ok(PreparedRestore {
        stage,
        root,
        revision,
        files: baseline,
        manifest,
        report,
        credentials,
    })
}

#[derive(Serialize, Deserialize)]
struct Checkpoint {
    stage: String,
    previous: String,
    #[serde(default)]
    committed: bool,
}
const MARKER: &str = ".restore-pending.json";

impl PreparedRestore {
    pub fn commit(
        self,
        storage: &mut Option<Storage>,
        token: &CancellationToken,
        mut progress: impl FnMut(BackupProgress),
    ) -> Result<MergeReport> {
        check(token)?;
        let live = storage
            .as_ref()
            .ok_or_else(|| OtterError::new(ErrorCode::Conflict, "storage closed"))?;
        if live.directory().parent() != Some(self.root.as_path())
            || self.revision != archive::database_revision(live)?
            || self.files
                != archive::checksums(
                    &live.directory().join("library"),
                    Some(BackupScope::Full),
                    token,
                )?
        {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "live data changed before restore publication",
            ));
        }
        let marker = self.root.join(MARKER);
        if marker.exists() {
            return Err(OtterError::new(ErrorCode::Conflict, "pending restore"));
        }
        let stage = self
            .stage
            .path
            .file_name()
            .unwrap()
            .to_str()
            .unwrap()
            .to_owned();
        let checkpoint = Checkpoint {
            previous: format!("{stage}.previous"),
            stage,
            committed: false,
        };
        let previous = self.root.join(&checkpoint.previous);
        if previous.exists() {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "restore previous directory exists",
            ));
        }
        check(token)?;
        files::write_json(&marker, &checkpoint)?;
        // Finish or roll back this short publication section even if cancellation arrives mid-rename.
        drop(storage.take());
        let result = (|| {
            progress(BackupProgress {
                stage: BackupStage::Publish,
                done: 0,
                total: None,
            });
            fs::rename(self.root.join("v2"), &previous)?;
            sync_directory(&self.root)?;
            fs::rename(self.stage.path.join("v2"), self.root.join("v2"))?;
            sync_directory(&self.root)?;
            let reopened = Storage::open(&self.root)?;
            validate(&reopened)?;
            files::write_json(
                &marker,
                &Checkpoint {
                    stage: checkpoint.stage.clone(),
                    previous: checkpoint.previous.clone(),
                    committed: true,
                },
            )?;
            let _ = fs::remove_file(&marker);
            let _ = sync_directory(&self.root);
            Ok::<_, OtterError>(reopened)
        })();
        match result {
            Ok(reopened) => {
                *storage = Some(reopened);
                let _ = fs::remove_dir_all(previous);
                Ok(self.report)
            }
            Err(error) => {
                recover(&self.root)?;
                *storage = Some(Storage::open(&self.root)?);
                Err(error)
            }
        }
    }
}

/// Call before opening any live SQLite/PDF handles. Uncommitted published data is retained for recovery.
pub fn recover(root: &Path) -> Result<()> {
    let marker = root.join(MARKER);
    if !marker.is_file() {
        return Ok(());
    }
    let state: Checkpoint = serde_json::from_slice(&fs::read(&marker)?)?;
    files::component(&state.stage)?;
    files::component(&state.previous)?;
    if !state.stage.starts_with(".restore-")
        || state.previous != format!("{}.previous", state.stage)
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "restore checkpoint paths",
        ));
    }
    let previous = root.join(&state.previous);
    if state.committed {
        if !root.join("v2/otter.db").is_file() {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "committed restore database missing",
            ));
        }
        fs::remove_file(&marker)?;
        sync_directory(root)?;
        let _ = fs::remove_dir_all(previous);
        let _ = fs::remove_dir_all(root.join(state.stage));
        return Ok(());
    }
    if previous.is_dir() {
        let live = root.join("v2");
        if live.exists() {
            let retained = root.join(format!("{}.uncommitted", state.stage));
            if retained.exists() {
                return Err(OtterError::new(
                    ErrorCode::Conflict,
                    "uncommitted restore directory exists",
                ));
            }
            fs::rename(live, retained)?;
        }
        fs::rename(previous, root.join("v2"))?;
        sync_directory(root)?;
    }
    if !root.join("v2/otter.db").is_file() {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "restore recovery database missing",
        ));
    }
    fs::remove_file(marker)?;
    sync_directory(root)?;
    let staged = root.join(state.stage);
    if staged.is_dir() {
        let _ = fs::remove_dir_all(staged);
    }
    Ok(())
}

fn repair_files(storage: &Storage, token: &CancellationToken) -> Result<()> {
    for mut document in storage.documents(u32::MAX, 0)? {
        files::component(&document.id)?;
        let directory = storage.directory().join("library").join(&document.id);
        fs::create_dir_all(&directory)?;
        let path = directory.join("source.pdf");
        if path.is_file() {
            let hash = archive::hash_file(&path, token)?[..24].to_owned();
            if document.content_hash.as_deref() != Some(&hash) {
                document.content_hash = Some(hash);
                storage.put_document(&document)?;
            }
        } else if document.content_hash.take().is_some() {
            storage.put_document(&document)?;
        }
    }
    Ok(())
}

pub(crate) fn sanitize_snapshot(path: &Path) -> Result<()> {
    let connection = Connection::open(path)?;
    // DELETE alone leaves values recoverable in SQLite pages. The initial VACUUM
    // removes historical deleted content; secure_delete erases the live secrets.
    connection.pragma_update(None, "secure_delete", "ON")?;
    let keys: Vec<String> = {
        let mut query = connection.prepare("SELECT settingKey FROM settings")?;
        query
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?
    };
    for key in keys {
        if crate::credentials::is_secret_setting(&key) {
            connection.execute("DELETE FROM settings WHERE settingKey=?1", [key])?;
        }
    }
    Ok(())
}

mod merge;
use merge::*;
mod file_ops;
use file_ops::*;
