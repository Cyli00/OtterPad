pub mod fetch;
pub mod identifier;
mod import_recovery;
pub mod metadata;
mod replacement;
pub use import_recovery::recover_imports;
pub use replacement::{recover_replacements, replace_pdf};

use std::{
    fs,
    io::{Read, Write},
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
};

use rusqlite::{OptionalExtension, params};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
    storage::{Document, Storage},
    tasks,
};

static FILE_ID: AtomicU64 = AtomicU64::new(0);
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Favorite {
    pub id: String,
    pub emoji: String,
    pub name: String,
    pub document_ids: Vec<String>,
    pub created_at: i64,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct History {
    pub document_id: String,
    pub opened_at: i64,
    pub progress: f64,
    pub anchor_block: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Highlight {
    pub id: String,
    pub document_id: String,
    pub content: String,
    pub note: Option<String>,
    pub color: String,
    pub group_id: Option<String>,
    pub anchor: Option<Value>,
    pub created_at: i64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportResult {
    pub document: Document,
    pub duplicate: bool,
}

pub fn document_directory(storage: &Storage, id: &str) -> Result<std::path::PathBuf> {
    files::component(id)?;
    Ok(storage.directory().join("library").join(id))
}

/// Fingerprint and copied bytes come from the same read, never two races with
/// a mutable source file. Existing documents and user files are preserved.
pub fn import_pdf(
    storage: &Storage,
    source: &Path,
    mut document: Document,
    token: &CancellationToken,
) -> Result<ImportResult> {
    tasks::check(token)?;
    let stage = storage.directory().join("library").join(format!(
        ".import-{}-{}",
        std::process::id(),
        FILE_ID.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir(&stage)?;
    let mut published = None;
    let result = (|| {
        let mut source = fs::File::open(source)?;
        let mut output = fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(stage.join("source.pdf"))?;
        let mut hash = Sha256::new();
        let mut buffer = [0; 64 * 1024];
        let mut first = true;
        loop {
            tasks::check(token)?;
            let count = source.read(&mut buffer)?;
            if count == 0 {
                if first {
                    return Err(OtterError::new(ErrorCode::InvalidData, "empty PDF"));
                }
                break;
            }
            if first {
                if !buffer[..count].starts_with(b"%PDF-") {
                    return Err(OtterError::new(
                        ErrorCode::InvalidData,
                        "invalid PDF header",
                    ));
                }
                first = false;
            }
            hash.update(&buffer[..count]);
            output.write_all(&buffer[..count])?;
        }
        output.sync_all()?;
        drop(output);
        let hash = hash.finalize();
        let fingerprint = hash[..12]
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        let existing: Option<String> = storage
            .connection
            .query_row(
                "SELECT id FROM documents WHERE contentHash=?1",
                [&fingerprint],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(id) = existing {
            return Ok(ImportResult {
                document: storage.document(&id)?.ok_or_else(|| {
                    OtterError::new(ErrorCode::Database, "duplicate metadata missing")
                })?,
                duplicate: true,
            });
        }
        if document.id.is_empty() {
            document.id = format!("doc_{fingerprint}");
        }
        files::component(&document.id)?;
        if storage
            .document(&document.id)?
            .is_some_and(|d| d.content_hash.is_some())
        {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "document already has a PDF",
            ));
        }
        let directory = document_directory(storage, &document.id)?;
        fs::create_dir_all(&directory)?;
        if fs::symlink_metadata(&directory)?.file_type().is_symlink() {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "document directory symlink",
            ));
        }
        let target = directory.join("source.pdf");
        if target.exists() {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "document PDF already exists",
            ));
        }
        tasks::check(token)?;
        document.content_hash = Some(fingerprint);
        import_recovery::prepare(storage, &stage, &document)?;
        // Hard-link publication refuses an existing target on every platform.
        fs::hard_link(stage.join("source.pdf"), &target)?;
        published = Some(target);
        import_recovery::sync_directory(&directory)?;
        storage.put_document(&document)?;
        Ok(ImportResult {
            document,
            duplicate: false,
        })
    })();
    // A surrounding Zotero transaction can still roll back after this returns.
    // Keep its journal until startup can observe the committed SQLite state.
    let rollback_failed =
        result.is_err() && published.is_some_and(|path| fs::remove_file(path).is_err());
    if !rollback_failed
        && (result.is_err()
            || storage.connection.is_autocommit()
            || !stage.join("journal.json").exists())
    {
        let _ = fs::remove_dir_all(stage);
    }
    result
}

/// Files are staged in v2/.trash until the database delete commits. The journal
/// rolls back an interrupted delete and retries cleanup of committed deletes.
pub fn delete_document(storage: &Storage, id: &str) -> Result<bool> {
    files::component(id)?;
    if storage.document(id)?.is_none() {
        return Ok(false);
    }
    let directory = document_directory(storage, id)?;
    let trash = storage.directory().join(".trash").join(format!(
        "{id}-{}-{}",
        std::process::id(),
        FILE_ID.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir_all(&trash)?;
    files::write_json(&trash.join("journal.json"), &json!({"document_id":id}))?;
    if directory.exists() {
        fs::rename(&directory, trash.join("files"))?;
    }
    match storage.delete_document(id) {
        Ok(deleted) => {
            let _ = fs::remove_dir_all(trash);
            Ok(deleted)
        }
        Err(error) => {
            if trash.join("files").exists() {
                fs::rename(trash.join("files"), &directory)?;
            }
            Err(error)
        }
    }
}

pub fn recover_deletions(storage: &Storage) -> Result<()> {
    let trash = storage.directory().join(".trash");
    if !trash.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(trash)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() || !entry.path().join("journal.json").is_file() {
            continue;
        }
        let value: Value = serde_json::from_slice(&fs::read(entry.path().join("journal.json"))?)?;
        let id = value["document_id"]
            .as_str()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "invalid delete journal"))?;
        let target = document_directory(storage, id)?;
        if storage.document(id)?.is_some()
            && !target.exists()
            && entry.path().join("files").exists()
        {
            fs::rename(entry.path().join("files"), target)?;
        }
        if storage.document(id)?.is_none() || !entry.path().join("files").exists() {
            fs::remove_dir_all(entry.path())?;
        }
    }
    Ok(())
}

pub fn put_favorite(storage: &mut Storage, favorite: &Favorite) -> Result<()> {
    files::component(&favorite.id)?;
    let tx = storage.connection.transaction()?;
    tx.execute("INSERT INTO favorites VALUES (?1,?2,?3,?4) ON CONFLICT(id) DO UPDATE SET emoji=excluded.emoji,name=excluded.name,createdAt=excluded.createdAt",params![favorite.id,favorite.emoji,favorite.name,favorite.created_at])?;
    tx.execute(
        "DELETE FROM favorite_documents WHERE favoriteId=?1",
        [&favorite.id],
    )?;
    for id in &favorite.document_ids {
        tx.execute(
            "INSERT INTO favorite_documents VALUES (?1,?2) ON CONFLICT DO NOTHING",
            params![favorite.id, id],
        )?;
    }
    tx.commit()?;
    Ok(())
}

pub fn favorites(storage: &Storage) -> Result<Vec<Favorite>> {
    let mut statement = storage.connection.prepare(
        "SELECT id,emoji,name,createdAt FROM favorites ORDER BY id='_default_' DESC,createdAt,id",
    )?;
    let rows = statement.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, i64>(3)?,
        ))
    })?;
    let mut result = Vec::new();
    for row in rows {
        let (id, emoji, name, created_at) = row?;
        let mut links = storage
            .connection
            .prepare("SELECT docId FROM favorite_documents WHERE favoriteId=?1 ORDER BY docId")?;
        let document_ids = links
            .query_map([&id], |r| r.get(0))?
            .collect::<std::result::Result<_, _>>()?;
        result.push(Favorite {
            id,
            emoji,
            name,
            document_ids,
            created_at,
        });
    }
    Ok(result)
}
pub fn delete_favorite(storage: &Storage, id: &str) -> Result<bool> {
    if id == "_default_" {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "default favorite cannot be deleted",
        ));
    }
    Ok(storage
        .connection
        .execute("DELETE FROM favorites WHERE id=?1", [id])?
        != 0)
}
pub fn favorite_document(
    storage: &Storage,
    favorite: &str,
    document: &str,
    add: bool,
) -> Result<()> {
    if add {
        storage.connection.execute(
            "INSERT INTO favorite_documents VALUES (?1,?2) ON CONFLICT DO NOTHING",
            params![favorite, document],
        )?;
    } else {
        storage.connection.execute(
            "DELETE FROM favorite_documents WHERE favoriteId=?1 AND docId=?2",
            params![favorite, document],
        )?;
    }
    Ok(())
}
pub fn record_history(storage: &Storage, entry: &History) -> Result<()> {
    if !entry.progress.is_finite() || !(0.0..=1.0).contains(&entry.progress) {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "invalid reading progress",
        ));
    }
    storage.connection.execute("INSERT INTO history VALUES (?1,?2,?3,?4) ON CONFLICT(docId) DO UPDATE SET openedAt=excluded.openedAt,progress=excluded.progress,anchorBlock=excluded.anchorBlock",params![entry.document_id,entry.opened_at,entry.progress,entry.anchor_block])?;
    Ok(())
}
pub fn history(storage: &Storage, limit: u32, offset: u32) -> Result<Vec<History>> {
    let mut statement=storage.connection.prepare("SELECT docId,openedAt,progress,anchorBlock FROM history ORDER BY openedAt DESC,docId LIMIT ?1 OFFSET ?2")?;
    Ok(statement
        .query_map(params![limit, offset], |r| {
            Ok(History {
                document_id: r.get(0)?,
                opened_at: r.get(1)?,
                progress: r.get(2)?,
                anchor_block: r.get(3)?,
            })
        })?
        .collect::<std::result::Result<_, _>>()?)
}
pub fn clear_history(storage: &Storage, document: Option<&str>) -> Result<()> {
    if let Some(id) = document {
        storage
            .connection
            .execute("DELETE FROM history WHERE docId=?1", [id])?;
    } else {
        storage.connection.execute("DELETE FROM history", [])?;
    }
    Ok(())
}

pub fn put_highlight(storage: &Storage, highlight: &Highlight) -> Result<()> {
    files::component(&highlight.id)?;
    let changed=storage.connection.execute("INSERT INTO highlights VALUES (?1,?2,?3,?4,?5,?6,?7,?8) ON CONFLICT(id) DO UPDATE SET content=excluded.content,note=excluded.note,color=excluded.color,groupId=excluded.groupId,anchor=excluded.anchor WHERE highlights.docId=excluded.docId",params![highlight.id,highlight.document_id,highlight.content,highlight.note,highlight.color,highlight.group_id,highlight.anchor.as_ref().map(serde_json::to_string).transpose()?,highlight.created_at])?;
    if changed == 0 {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "highlight id belongs to another document",
        ));
    }
    Ok(())
}
pub fn highlights(storage: &Storage, document: &str) -> Result<Vec<Highlight>> {
    let mut statement=storage.connection.prepare("SELECT id,docId,content,note,color,groupId,anchor,createdAt FROM highlights WHERE docId=?1 ORDER BY createdAt,id")?;
    let mut rows = statement.query([document])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let anchor: Option<String> = row.get(6)?;
        result.push(Highlight {
            id: row.get(0)?,
            document_id: row.get(1)?,
            content: row.get(2)?,
            note: row.get(3)?,
            color: row.get(4)?,
            group_id: row.get(5)?,
            anchor: anchor.map(|s| serde_json::from_str(&s)).transpose()?,
            created_at: row.get(7)?,
        });
    }
    Ok(result)
}
pub fn delete_highlight(storage: &Storage, id: &str) -> Result<bool> {
    let row: Option<(String, Option<String>)> = storage
        .connection
        .query_row(
            "SELECT docId,groupId FROM highlights WHERE id=?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    let Some((doc, group)) = row else {
        return Ok(false);
    };
    if let Some(group) = group {
        storage.connection.execute(
            "DELETE FROM highlights WHERE docId=?1 AND groupId=?2",
            params![doc, group],
        )?;
    } else {
        storage
            .connection
            .execute("DELETE FROM highlights WHERE id=?1", [id])?;
    }
    Ok(true)
}
