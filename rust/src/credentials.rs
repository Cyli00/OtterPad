use std::{collections::HashMap, sync::RwLock};

use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
};

/// Values enter from the system vault and remain in memory. Never derive Debug/Serialize here.
pub struct CredentialInput {
    pub key: String,
    pub value: String,
}
#[derive(Default)]
pub struct Credentials(RwLock<HashMap<String, String>>);

impl Credentials {
    pub fn inject(&self, entries: Vec<CredentialInput>) -> Result<()> {
        for entry in &entries {
            let known = [
                "doc_extract_api_key",
                "doc_extract_api_key_mineru",
                "backup_webdav_password",
                "backup_s3_secret_access_key",
                "zotero_api_key",
                "tavily_api_key",
                "exa_search_api_key",
                "brave_search_api_key",
            ]
            .contains(&entry.key.as_str());
            let agent = entry
                .key
                .strip_prefix("agent_api_key_")
                .is_some_and(|id| files::component(id).is_ok());
            if !known && !agent {
                return Err(OtterError::new(
                    ErrorCode::InvalidArgument,
                    "unknown vault credential key",
                ));
            }
        }
        let mut values = self
            .0
            .write()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "credential memory lock"))?;
        for entry in entries {
            if entry.value.is_empty() {
                values.remove(&entry.key);
            } else {
                values.insert(entry.key, entry.value);
            }
        }
        Ok(())
    }

    pub fn get(&self, key: &str) -> Result<String> {
        self.optional(key)?.ok_or_else(|| {
            OtterError::new(ErrorCode::Authentication, "vault credential not injected")
        })
    }

    pub fn optional(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .0
            .read()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "credential memory lock"))?
            .get(key)
            .cloned())
    }

    pub fn clear(&self) -> Result<()> {
        self.0
            .write()
            .map_err(|_| OtterError::new(ErrorCode::Conflict, "credential memory lock"))?
            .clear();
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
