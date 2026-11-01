use crate::{
    error::{ErrorCode, OtterError, Result},
    storage::Storage,
    tasks::check,
};
use std::{fs, path::Path};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum StorageGroup {
    Papers,
    Chat,
    Cache,
    Logs,
    Database,
    Recovery,
}
pub struct StorageUsage {
    pub group: StorageGroup,
    pub bytes: u64,
    pub files: u64,
}
pub struct StorageReport {
    pub bytes: u64,
    pub files: u64,
    pub groups: Vec<StorageUsage>,
}

fn classify(relative: &str) -> StorageGroup {
    let parts: Vec<_> = relative.split('/').collect();
    if relative.starts_with("logs/") {
        StorageGroup::Logs
    } else if relative.starts_with("cache/")
        || parts.iter().any(|name| name.starts_with(".reader.html"))
    {
        StorageGroup::Cache
    } else if parts
        .first()
        .is_some_and(|name| name.starts_with("otter.db"))
    {
        StorageGroup::Database
    } else if parts.first() == Some(&"library")
        && parts.get(1).is_some_and(|name| !name.starts_with('.'))
    {
        if parts.get(2) == Some(&"chats") {
            StorageGroup::Chat
        } else {
            StorageGroup::Papers
        }
    } else {
        StorageGroup::Recovery
    }
}
fn visit(
    root: &Path,
    directory: &Path,
    token: &CancellationToken,
    callback: &mut impl FnMut(&Path, &str, u64) -> Result<()>,
) -> Result<()> {
    if !directory.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(directory)? {
        check(token)?;
        let entry = entry?;
        let kind = entry.file_type()?;
        if kind.is_dir() {
            visit(root, &entry.path(), token, callback)?;
        } else if kind.is_file() {
            let path = entry.path();
            let relative = path
                .strip_prefix(root)
                .unwrap()
                .to_string_lossy()
                .replace('\\', "/");
            callback(&path, &relative, entry.metadata()?.len())?;
        }
    }
    Ok(())
}
pub fn report(storage: &Storage, token: &CancellationToken) -> Result<StorageReport> {
    let mut groups: Vec<_> = [
        StorageGroup::Papers,
        StorageGroup::Chat,
        StorageGroup::Cache,
        StorageGroup::Logs,
        StorageGroup::Database,
        StorageGroup::Recovery,
    ]
    .into_iter()
    .map(|group| StorageUsage {
        group,
        bytes: 0,
        files: 0,
    })
    .collect();
    visit(
        storage.directory(),
        storage.directory(),
        token,
        &mut |_, relative, bytes| {
            let group = groups
                .iter_mut()
                .find(|group| group.group == classify(relative))
                .unwrap();
            group.bytes += bytes;
            group.files += 1;
            Ok(())
        },
    )?;
    Ok(StorageReport {
        bytes: groups.iter().map(|g| g.bytes).sum(),
        files: groups.iter().map(|g| g.files).sum(),
        groups,
    })
}
/// The runtime excludes all active operations and closes PDF handles first.
/// Recovery files are reported separately and never treated as disposable cache.
pub fn clear(storage: &Storage, groups: &[StorageGroup], token: &CancellationToken) -> Result<()> {
    if groups.contains(&StorageGroup::Recovery) {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "recovery data is not a cache group",
        ));
    }
    visit(
        storage.directory(),
        storage.directory(),
        token,
        &mut |path, relative, _| {
            let group = classify(relative);
            if groups.contains(&group)
                && !matches!(group, StorageGroup::Database | StorageGroup::Recovery)
            {
                fs::remove_file(path)?;
            }
            Ok(())
        },
    )?;
    if groups.contains(&StorageGroup::Papers) {
        storage.connection.execute("DELETE FROM documents", [])?;
    }
    if groups.contains(&StorageGroup::Database) || groups.contains(&StorageGroup::Papers) {
        storage
            .connection
            .execute_batch("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")?;
    }
    Ok(())
}
