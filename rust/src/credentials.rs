use std::{collections::HashMap, path::PathBuf, sync::RwLock};

use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
};

/// 凭据键值。只在注入和读取接口里出现；不要派生 Debug，避免值进日志。
pub struct CredentialInput {
    pub key: String,
    pub value: String,
}

/// 凭据：内存中一份，[`Credentials::open`] 打开时同时写回独立文件。
/// 文件在数据根（与 `v2/` 并列），恢复备份替换 `v2/` 时不受影响，也不进入备份包。
#[derive(Default)]
pub struct Credentials {
    values: RwLock<HashMap<String, String>>,
    file: Option<PathBuf>,
}

fn known(key: &str) -> bool {
    [
        "doc_extract_api_key",
        "doc_extract_api_key_mineru",
        "backup_webdav_password",
        "backup_s3_secret_access_key",
        "zotero_api_key",
        "tavily_api_key",
        "exa_search_api_key",
        "brave_search_api_key",
    ]
    .contains(&key)
        || key
            .strip_prefix("agent_api_key_")
            .is_some_and(|id| files::component(id).is_ok())
}

fn lock_error() -> OtterError {
    OtterError::new(ErrorCode::Conflict, "credential memory lock")
}

impl Credentials {
    /// 从 [path] 载入，文件不存在视为空。无法解析的文件改名为 `<name>.invalid` 保留，
    /// 以空凭据启动：凭据文件损坏不应让整个文献库打不开。
    pub fn open(path: PathBuf) -> Result<Self> {
        let values = match std::fs::read(&path) {
            Ok(bytes) => match serde_json::from_slice::<HashMap<String, String>>(&bytes) {
                Ok(values) => values
                    .into_iter()
                    .filter(|(key, value)| known(key) && !value.is_empty())
                    .collect(),
                Err(_) => {
                    std::fs::rename(&path, path.with_extension("json.invalid"))?;
                    HashMap::new()
                }
            },
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => HashMap::new(),
            Err(error) => return Err(error.into()),
        };
        Ok(Self {
            values: RwLock::new(values),
            file: Some(path),
        })
    }

    /// 写入或删除（空值）凭据；有文件时在同一把写锁内写回，并发写入不会互相覆盖。
    pub fn inject(&self, entries: Vec<CredentialInput>) -> Result<()> {
        if entries.iter().any(|e| !known(&e.key)) {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "unknown vault credential key",
            ));
        }
        let mut values = self.values.write().map_err(|_| lock_error())?;
        let mut next = values.clone();
        for entry in entries {
            if entry.value.is_empty() {
                next.remove(&entry.key);
            } else {
                next.insert(entry.key, entry.value);
            }
        }
        if let Some(file) = &self.file {
            let sorted: std::collections::BTreeMap<_, _> = next.iter().collect();
            files::atomic_write_private(file, &serde_json::to_vec_pretty(&sorted)?)?;
        }
        *values = next;
        Ok(())
    }

    /// 全部已存凭据，按键排序；供设置页回显。
    pub fn entries(&self) -> Result<Vec<CredentialInput>> {
        let values = self.values.read().map_err(|_| lock_error())?;
        let mut entries: Vec<_> = values
            .iter()
            .map(|(key, value)| CredentialInput {
                key: key.clone(),
                value: value.clone(),
            })
            .collect();
        entries.sort_by(|a, b| a.key.cmp(&b.key));
        Ok(entries)
    }

    pub fn get(&self, key: &str) -> Result<String> {
        self.optional(key)?.ok_or_else(|| {
            OtterError::new(ErrorCode::Authentication, "vault credential not injected")
        })
    }

    pub fn optional(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .values
            .read()
            .map_err(|_| lock_error())?
            .get(key)
            .cloned())
    }

    /// 只清空内存（关闭运行时），不删除文件。
    pub fn clear(&self) -> Result<()> {
        self.values.write().map_err(|_| lock_error())?.clear();
        Ok(())
    }
}

pub fn is_secret_setting(key: &str) -> bool {
    let key = key.to_ascii_lowercase();
    key.starts_with("agent_api_key_")
        || key.starts_with("doc_extract_api_key")
        || key.ends_with("_api_key")
        || key.ends_with("_password")
        || key.ends_with("_secret_access_key")
        || matches!(
            key.as_str(),
            "api_key"
                | "agent_api_key"
                | "password"
                | "access_token"
                | "refresh_token"
                | "client_secret"
        )
}
