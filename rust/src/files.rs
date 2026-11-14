use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Component, Path},
    sync::atomic::{AtomicU64, Ordering},
};

use crate::error::{ErrorCode, OtterError, Result};

static TEMP_ID: AtomicU64 = AtomicU64::new(0);

pub fn component(value: &str) -> Result<&str> {
    let mut components = Path::new(value).components();
    if value.contains(['/', '\\', ':'])
        || !matches!(components.next(), Some(Component::Normal(_)))
        || components.next().is_some()
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "invalid path component",
        ));
    }
    Ok(value)
}

/// Writes beside the destination, fsyncs, then atomically replaces it.
pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    write_replacing(path, bytes, false)
}

/// 同 [`atomic_write`]，但 Unix 上临时文件一创建就只有属主可读写（0600），凭据不会短暂以 0644 落盘。
pub fn atomic_write_private(path: &Path, bytes: &[u8]) -> Result<()> {
    write_replacing(path, bytes, true)
}

fn write_replacing(path: &Path, bytes: &[u8], private: bool) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "missing parent directory"))?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".otter-{}-{}.tmp",
        std::process::id(),
        TEMP_ID.fetch_add(1, Ordering::Relaxed)
    ));
    let mut created = false;
    let result = (|| {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        if private {
            std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
        }
        #[cfg(not(unix))]
        let _ = private;
        let mut file = options.open(&temporary)?;
        created = true;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)?;
        #[cfg(unix)]
        fs::File::open(parent)?.sync_all()?;
        Ok(())
    })();
    if created && temporary.exists() {
        let _ = fs::remove_file(temporary);
    }
    result
}

pub fn write_json(path: &Path, value: &impl serde::Serialize) -> Result<()> {
    atomic_write(path, &serde_json::to_vec(value)?)
}
