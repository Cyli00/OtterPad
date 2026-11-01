use std::{collections::HashSet, path::Path};

use rusqlite::{OptionalExtension, params};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::{
    CloudLibrary, FetchProgress, LocalLibrary, ZoteroClient, invalid, local_candidates,
    local_source, to_document,
};
use crate::{
    error::{ErrorCode, OtterError, Result},
    library,
    storage::{Document, Storage},
    tasks::check,
};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImportReport {
    pub added: u64,
    pub updated: u64,
    pub copied: u64,
    pub missing: u64,
    pub kept: u64,
    pub failed_keys: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalSelection {
    pub item_key: String,
    pub attachment_key: Option<String>,
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalRecord {
    document_id: String,
    metadata: Value,
    attachment_key: Option<String>,
}

pub fn library_version(storage: &Storage) -> Result<u64> {
    meta(storage, "zotero_library_version")?
        .map(|s| s.parse().map_err(|_| invalid("Zotero stored version")))
        .transpose()
        .map(|n| n.unwrap_or(0))
}
pub fn cloud_since(storage: &Storage, user_id: u64, full: bool) -> Result<u64> {
    let stored = meta(storage, "zotero_user_id")?;
    if full
        || stored
            .as_deref()
            .is_some_and(|id| id != user_id.to_string())
    {
        Ok(0)
    } else {
        library_version(storage)
    }
}

/// One-way cloud import retains the 0.1.x policy: known items are never overwritten.
/// The cursor commits with all item mappings, so a failed/cancelled run can be repeated.
pub fn import_cloud(
    storage: &Storage,
    library: &CloudLibrary,
    full: bool,
    token: &CancellationToken,
    mut progress: impl FnMut(FetchProgress),
) -> Result<ImportReport> {
    check(token)?;
    let transaction = storage.connection.unchecked_transaction()?;
    let account = meta(storage, "zotero_user_id")?;
    if full
        || account
            .as_deref()
            .is_some_and(|id| id != library.user_id.to_string())
    {
        storage.connection.execute("DELETE FROM zotero_items", [])?;
    } else if library.version < library_version(storage)? {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "Zotero stale fetched library",
        ));
    }
    let added_at = now_ms();
    let mut report = ImportReport::default();
    let mut documents = storage.documents(u32::MAX, 0)?;
    let mut seen = HashSet::new();
    for (index, item) in library.items.iter().enumerate() {
        check(token)?;
        let key = item["key"]
            .as_str()
            .ok_or_else(|| invalid("Zotero item key"))?;
        super::validate_key(key)?;
        if !seen.insert(key) {
            return Err(invalid("duplicate Zotero item"));
        }
        let version = item["version"]
            .as_u64()
            .ok_or_else(|| invalid("Zotero item version"))?;
        let version = i64::try_from(version).map_err(|_| invalid("Zotero item version range"))?;
        let known: bool = storage.connection.query_row(
            "SELECT EXISTS(SELECT 1 FROM zotero_items WHERE zoteroKey=?1)",
            [key],
            |r| r.get(0),
        )?;
        if !known && let Some(mut document) = to_document(item, added_at) {
            let id = if let Some(existing) = documents
                .iter()
                .find(|d| crate::library::metadata::duplicate(d, &document))
            {
                existing.id.clone()
            } else {
                document.id = unique_id(storage, &format!("cloud:{}:{key}", library.user_id))?;
                storage.put_document(&document)?;
                let id = document.id.clone();
                documents.push(document);
                report.added += 1;
                id
            };
            storage.connection.execute(
                "INSERT INTO zotero_items(zoteroKey,docId,version) VALUES (?1,?2,?3)",
                params![key, id, version],
            )?;
        }
        progress(FetchProgress {
            fetched: (index + 1) as u64,
            total: Some(library.items.len() as u64),
        });
    }
    check(token)?;
    put_meta(
        storage,
        "zotero_library_version",
        &library.version.to_string(),
    )?;
    put_meta(storage, "zotero_user_id", &library.user_id.to_string())?;
    transaction.commit()?;
    Ok(report)
}

/// Metadata commits before attachment copies. Interrupted batches retain completed work.
pub async fn import_local(
    storage: &Storage,
    client: &ZoteroClient,
    library: &LocalLibrary,
    directory: Option<&Path>,
    selections: &[LocalSelection],
    token: &CancellationToken,
    mut progress: impl FnMut(FetchProgress),
) -> Result<ImportReport> {
    let source = local_source(library, directory)?;
    let candidates = local_candidates(&library.items, now_ms());
    let mut seen = HashSet::new();
    for selection in selections {
        let candidate = candidates
            .iter()
            .find(|c| c.key == selection.item_key)
            .ok_or_else(|| invalid("Zotero selection not in fetched library"))?;
        if !seen.insert(&selection.item_key)
            || selection
                .attachment_key
                .as_deref()
                .is_some_and(|key| !candidate.attachments.iter().any(|a| a.key == key))
        {
            return Err(invalid("invalid Zotero attachment selection"));
        }
    }
    client.verify_local(library, token).await?;
    let mut report = ImportReport::default();
    let mut jobs = Vec::new();
    for (index, selection) in selections.iter().enumerate() {
        check(token)?;
        let candidate = candidates
            .iter()
            .find(|c| c.key == selection.item_key)
            .unwrap();
        let result = (|| -> Result<(Document, String, LocalRecord)> {
            let transaction = storage.connection.unchecked_transaction()?;
            let record_key = local_record_key(&source, &candidate.key);
            let previous: Option<LocalRecord> = meta(storage, &record_key)?
                .map(|s| serde_json::from_str(&s))
                .transpose()?;
            let current = previous
                .as_ref()
                .map(|record| storage.document(&record.document_id))
                .transpose()?
                .flatten();
            let has_record = current.is_some();
            let mut document = match current {
                Some(current) => current,
                None => {
                    let documents = storage.documents(u32::MAX, 0)?;
                    if let Some(existing) = documents
                        .into_iter()
                        .find(|d| crate::library::metadata::duplicate(d, &candidate.document))
                    {
                        existing
                    } else {
                        let mut document = candidate.document.clone();
                        document.id = unique_id(storage, &format!("{source}:{}", candidate.key))?;
                        document
                    }
                }
            };
            let added = storage.document(&document.id)?.is_none();
            let before = document.clone();
            merge_source(
                &mut document,
                &candidate.document,
                if has_record {
                    previous.as_ref().map(|r| &r.metadata)
                } else {
                    None
                },
            )?;
            storage.put_document(&document)?;
            let record = LocalRecord {
                document_id: document.id.clone(),
                metadata: serde_json::to_value(&candidate.document)?,
                attachment_key: if has_record {
                    previous.and_then(|r| r.attachment_key)
                } else {
                    None
                },
            };
            put_meta(storage, &record_key, &serde_json::to_string(&record)?)?;
            transaction.commit()?;
            if added {
                report.added += 1;
            } else if document != before {
                report.updated += 1;
            }
            Ok((document, record_key, record))
        })();
        match result {
            Ok(job) => jobs.push((selection, job)),
            Err(_) => report.failed_keys.push(selection.item_key.clone()),
        }
        progress(FetchProgress {
            fetched: (index + 1) as u64,
            total: Some(selections.len() as u64),
        });
    }
    for (selection, (document, record_key, mut record)) in jobs {
        check(token)?;
        let Some(attachment) = &selection.attachment_key else {
            continue;
        };
        if library::document_directory(storage, &document.id)?
            .join("source.pdf")
            .is_file()
        {
            report.kept += 1;
            continue;
        }
        let path = match client.attachment_path(library, attachment, token).await {
            Ok(Some(path)) if path.is_file() => path,
            Ok(_) => {
                report.missing += 1;
                continue;
            }
            Err(error)
                if matches!(
                    error.code,
                    ErrorCode::Conflict
                        | ErrorCode::Cancelled
                        | ErrorCode::Network
                        | ErrorCode::Authentication
                ) =>
            {
                return Err(error);
            }
            Err(_) => {
                report.failed_keys.push(selection.item_key.clone());
                continue;
            }
        };
        match library::import_pdf(storage, &path, document.clone(), token) {
            Ok(result) if result.document.id == document.id && !result.duplicate => {
                report.copied += 1;
                record.attachment_key = Some(attachment.clone());
                put_meta(storage, &record_key, &serde_json::to_string(&record)?)?;
            }
            Ok(_) => report.kept += 1,
            Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
            Err(_) => report.failed_keys.push(selection.item_key.clone()),
        }
    }
    Ok(report)
}

fn local_record_key(source: &str, key: &str) -> String {
    let hash = Sha256::digest(source.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    format!("zotero_local:{hash}:{key}")
}
fn unique_id(storage: &Storage, source: &str) -> Result<String> {
    let hash = Sha256::digest(source.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    for suffix in 0u64.. {
        let id = format!("zotero_{}_{suffix}", &hash[..24]);
        if storage.document(&id)?.is_none() {
            return Ok(id);
        }
    }
    unreachable!()
}
fn merge_source(
    current: &mut Document,
    incoming: &Document,
    previous: Option<&Value>,
) -> Result<()> {
    let mut values = serde_json::to_value(&*current)?;
    let incoming = serde_json::to_value(incoming)?;
    for key in ["title", "authors", "journal", "year", "doi", "keywords"] {
        let value = &values[key];
        let update = match previous {
            Some(previous) => value == &previous[key],
            None => {
                value.is_null()
                    || value.as_str() == Some("")
                    || value.as_array().is_some_and(Vec::is_empty)
            }
        };
        if update {
            values[key] = incoming[key].clone();
        }
    }
    *current = serde_json::from_value(values)?;
    Ok(())
}
fn now_ms() -> i64 {
    (time::OffsetDateTime::now_utc().unix_timestamp_nanos() / 1_000_000) as i64
}
fn meta(storage: &Storage, key: &str) -> Result<Option<String>> {
    Ok(storage
        .connection
        .query_row("SELECT value FROM meta WHERE metaKey=?1", [key], |r| {
            r.get(0)
        })
        .optional()?)
}
fn put_meta(storage: &Storage, key: &str, value: &str) -> Result<()> {
    storage.connection.execute("INSERT INTO meta(metaKey,value) VALUES (?1,?2) ON CONFLICT(metaKey) DO UPDATE SET value=excluded.value",params![key,value])?;
    Ok(())
}
