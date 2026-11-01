use crate::{error::Result, storage::Storage};
use serde_json::json;

pub struct ExtractionUsage {
    pub date: String,
    pub paddle: u64,
    pub mineru: u64,
}
pub fn today(storage: &Storage) -> Result<ExtractionUsage> {
    let date: String =
        storage
            .connection
            .query_row("SELECT date('now','localtime')", [], |row| row.get(0))?;
    let raw = storage.setting("doc_extract_usage")?.unwrap_or_default();
    let current = raw["date"].as_str() == Some(&date);
    Ok(ExtractionUsage {
        date,
        paddle: if current {
            raw["paddle"].as_u64().unwrap_or(0)
        } else {
            0
        },
        mineru: if current {
            raw["mineru"].as_u64().unwrap_or(0)
        } else {
            0
        },
    })
}
/// Called only after a complete generation was published, on the storage worker.
pub fn record(storage: &Storage, provider: super::Provider, pages: u64) -> Result<()> {
    let transaction = storage.connection.unchecked_transaction()?;
    let mut usage = today(storage)?;
    match provider {
        super::Provider::Paddleocr => usage.paddle = usage.paddle.saturating_add(pages),
        super::Provider::Mineru => usage.mineru = usage.mineru.saturating_add(pages),
    }
    storage.put_setting(
        "doc_extract_usage",
        &json!({"date":usage.date,"paddle":usage.paddle,"mineru":usage.mineru}),
    )?;
    transaction.commit()?;
    Ok(())
}
