use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use time::{Date, OffsetDateTime, format_description::well_known::Rfc3339};

use crate::{
    error::{ErrorCode, Result},
    storage::Storage,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LogLevel {
    Info,
    Warning,
    Error,
}

/// Logs contain operation names and stable error codes, never payloads, credentials or URLs.
pub struct Logger {
    directory: PathBuf,
}
impl Logger {
    pub fn new(directory: PathBuf) -> Self {
        Self { directory }
    }
    pub fn record(
        &self,
        storage: &Storage,
        operation: &'static str,
        level: LogLevel,
        code: Option<ErrorCode>,
    ) -> Result<()> {
        if storage
            .setting("general_log_enabled")?
            .and_then(|v| v.as_bool())
            == Some(false)
        {
            return Ok(());
        }
        let minimum = match storage
            .setting("general_log_level")?
            .as_ref()
            .and_then(|v| v.as_str())
        {
            Some("info") => LogLevel::Info,
            Some("warning") => LogLevel::Warning,
            _ => LogLevel::Error,
        };
        if level < minimum {
            return Ok(());
        }
        let now = OffsetDateTime::now_utc();
        fs::create_dir_all(&self.directory)?;
        self.prune(now.date())?;
        let path = self.directory.join(format!("app_{}.log", now.date()));
        let mut file = OpenOptions::new().append(true).create(true).open(&path)?;
        // Keep one bounded daily rollover alongside the current log.
        if file.metadata()?.len() > 8 * 1024 * 1024 {
            drop(file);
            fs::rename(&path, path.with_extension("previous.log"))?;
            file = OpenOptions::new().append(true).create(true).open(path)?;
        }
        let timestamp = now
            .format(&Rfc3339)
            .unwrap_or_else(|_| now.unix_timestamp().to_string());
        writeln!(
            file,
            "{timestamp} [{level:?}] {operation} {}",
            code.map(|c| format!("{c:?}")).unwrap_or_default()
        )?;
        file.sync_data()?;
        Ok(())
    }
    fn prune(&self, today: Date) -> Result<()> {
        let format = time::format_description::parse_borrowed::<2>("[year]-[month]-[day]")
            .expect("fixed date format");
        for entry in fs::read_dir(&self.directory)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                continue;
            }
            let name = entry.file_name();
            let name = name.to_string_lossy();
            let Some(date) = name
                .strip_prefix("app_")
                .and_then(|s| s.get(..10))
                .and_then(|s| Date::parse(s, &format).ok())
            else {
                continue;
            };
            if today - date >= time::Duration::days(7) {
                fs::remove_file(entry.path())?;
            }
        }
        Ok(())
    }
    pub fn files(&self) -> Result<Vec<PathBuf>> {
        let mut result = Vec::new();
        if self.directory.exists() {
            for entry in fs::read_dir(&self.directory)? {
                let entry = entry?;
                if entry.file_type()?.is_file() && is_log(&entry.path()) {
                    result.push(entry.path());
                }
            }
        }
        result.sort();
        Ok(result)
    }
    pub fn clear(&self) -> Result<()> {
        for path in self.files()? {
            fs::remove_file(path)?;
        }
        Ok(())
    }
}
fn is_log(path: &Path) -> bool {
    path.file_name()
        .and_then(|s| s.to_str())
        .is_some_and(|s| s.starts_with("app_") && s.ends_with(".log"))
}
