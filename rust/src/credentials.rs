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

/// 备份凭据的加密口令；本身也是凭据，自动备份据此加密，不需要每次询问。
pub const BACKUP_PASSWORD_KEY: &str = "backup_credentials_password";

fn known(key: &str) -> bool {
    [
        BACKUP_PASSWORD_KEY,
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

    /// 设置了备份口令时返回待加密的快照（口令与全部凭据）；加密在调用方的工作线程里做。
    pub fn backup_snapshot(&self) -> Result<Option<BackupSecrets>> {
        let values = self.values.read().map_err(|_| lock_error())?;
        Ok(values
            .get(BACKUP_PASSWORD_KEY)
            .map(|password| BackupSecrets {
                password: password.clone(),
                values: values.iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
            }))
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

/// 备份包里的 `credentials.enc`：PBKDF2-HMAC-SHA256 派生密钥，AES-256-GCM 加密凭据 JSON。
pub struct BackupSecrets {
    password: String,
    values: std::collections::BTreeMap<String, String>,
}

const SEAL_VERSION: u32 = 1;
const SEAL_ITERATIONS: u32 = 600_000;
const SEAL_AAD: &[u8] = b"otterpad-backup-credentials-v1";

#[derive(serde::Serialize, serde::Deserialize)]
struct Sealed {
    version: u32,
    kdf: String,
    iterations: u32,
    salt: String,
    nonce: String,
    ciphertext: String,
}

fn crypto_error(detail: &'static str) -> OtterError {
    OtterError::new(ErrorCode::Conflict, detail)
}

fn derive_key(
    password: &str,
    salt: &[u8],
    iterations: u32,
) -> Result<aws_lc_rs::aead::LessSafeKey> {
    use aws_lc_rs::{aead, pbkdf2};
    let iterations = std::num::NonZeroU32::new(iterations)
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "credential kdf iterations"))?;
    let mut key = [0u8; 32];
    pbkdf2::derive(
        pbkdf2::PBKDF2_HMAC_SHA256,
        iterations,
        salt,
        password.as_bytes(),
        &mut key,
    );
    let key = aead::UnboundKey::new(&aead::AES_256_GCM, &key)
        .map_err(|_| crypto_error("credential key"))?;
    Ok(aead::LessSafeKey::new(key))
}

impl BackupSecrets {
    pub fn seal(&self) -> Result<Vec<u8>> {
        use aws_lc_rs::{
            aead::{Aad, NONCE_LEN, Nonce},
            rand::{SecureRandom, SystemRandom},
        };
        use base64::Engine;
        let random = SystemRandom::new();
        let mut salt = [0u8; 16];
        let mut nonce = [0u8; NONCE_LEN];
        random
            .fill(&mut salt)
            .and_then(|_| random.fill(&mut nonce))
            .map_err(|_| crypto_error("credential random"))?;
        let mut data = serde_json::to_vec(&self.values)?;
        derive_key(&self.password, &salt, SEAL_ITERATIONS)?
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce),
                Aad::from(SEAL_AAD),
                &mut data,
            )
            .map_err(|_| crypto_error("credential seal"))?;
        let b64 = base64::engine::general_purpose::STANDARD;
        Ok(serde_json::to_vec(&Sealed {
            version: SEAL_VERSION,
            kdf: "pbkdf2-hmac-sha256".into(),
            iterations: SEAL_ITERATIONS,
            salt: b64.encode(salt),
            nonce: b64.encode(nonce),
            ciphertext: b64.encode(data),
        })?)
    }
}

/// 解开备份包里的凭据。口令错误或内容被改动返回 `Authentication`；
/// 迭代次数限制在 10 万到 1000 万之间，构造的备份包不能让解密无限耗时。
pub fn unseal(bytes: &[u8], password: &str) -> Result<Vec<CredentialInput>> {
    use aws_lc_rs::aead::{Aad, NONCE_LEN, Nonce};
    use base64::Engine;
    let invalid = || OtterError::new(ErrorCode::InvalidData, "backup credentials format");
    let sealed: Sealed = serde_json::from_slice(bytes).map_err(|_| invalid())?;
    if sealed.version != SEAL_VERSION
        || sealed.kdf != "pbkdf2-hmac-sha256"
        || !(100_000..=10_000_000).contains(&sealed.iterations)
    {
        return Err(OtterError::new(
            ErrorCode::Unsupported,
            "backup credentials format",
        ));
    }
    let b64 = base64::engine::general_purpose::STANDARD;
    let salt = b64.decode(&sealed.salt).map_err(|_| invalid())?;
    let nonce: [u8; NONCE_LEN] = b64
        .decode(&sealed.nonce)
        .map_err(|_| invalid())?
        .try_into()
        .map_err(|_| invalid())?;
    let mut data = b64.decode(&sealed.ciphertext).map_err(|_| invalid())?;
    let plain = derive_key(password, &salt, sealed.iterations)?
        .open_in_place(
            Nonce::assume_unique_for_key(nonce),
            Aad::from(SEAL_AAD),
            &mut data,
        )
        .map_err(|_| OtterError::new(ErrorCode::Authentication, "backup credential password"))?;
    let values: std::collections::BTreeMap<String, String> =
        serde_json::from_slice(plain).map_err(|_| invalid())?;
    Ok(values
        .into_iter()
        .filter(|(key, value)| known(key) && !value.is_empty())
        .map(|(key, value)| CredentialInput { key, value })
        .collect())
}
