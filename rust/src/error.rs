use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    InvalidArgument,
    InvalidData,
    Io,
    Database,
    Conflict,
    UnsupportedDatabase,
    Cancelled,
    Network,
    Authentication,
    RateLimited,
    QuotaExceeded,
    Remote,
    NotFound,
    Unsupported,
    Pdf,
    LayoutOverflow,
    Refused,
    IncompleteResponse,
    ToolLimit,
}

/// `detail` is diagnostic data. Only `code` may be mapped to UI text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OtterError {
    pub code: ErrorCode,
    pub detail: String,
}

impl OtterError {
    pub(crate) fn new(code: ErrorCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }
}

impl fmt::Display for OtterError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self.code)
    }
}

impl std::error::Error for OtterError {}

impl From<std::io::Error> for OtterError {
    fn from(error: std::io::Error) -> Self {
        Self::new(ErrorCode::Io, error.to_string())
    }
}

impl From<rusqlite::Error> for OtterError {
    fn from(error: rusqlite::Error) -> Self {
        let code = match &error {
            rusqlite::Error::SqliteFailure(failure, _)
                if failure.code == rusqlite::ErrorCode::ConstraintViolation =>
            {
                ErrorCode::Conflict
            }
            _ => ErrorCode::Database,
        };
        Self::new(code, error.to_string())
    }
}

impl From<serde_json::Error> for OtterError {
    fn from(error: serde_json::Error) -> Self {
        // Do not include JSON values, which may contain private data.
        Self::new(ErrorCode::InvalidData, format!("{:?}", error.classify()))
    }
}

pub type Result<T> = std::result::Result<T, OtterError>;

impl From<reqwest::Error> for OtterError {
    fn from(error: reqwest::Error) -> Self {
        // URLs can contain signed credentials; bodies and headers are never logged.
        Self::new(ErrorCode::Network, error.without_url().to_string())
    }
}
