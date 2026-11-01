pub(crate) mod models;
mod tokenizer;

pub use models::Document;

use std::{
    path::{Path, PathBuf},
    time::Duration,
};

use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use serde_json::Value;

use crate::error::{ErrorCode, OtterError, Result};

const APPLICATION_ID: i32 = 0x4f54_5032; // OTP2; rejects legacy/foreign databases.
const SCHEMA_VERSION: i32 = 1;

pub(crate) fn repair_snapshot_index(path: &Path) -> Result<()> {
    let mut connection = Connection::open(path)?;
    tokenizer::register(&connection)?;
    let transaction = connection.transaction()?;
    // VACUUM can renumber ordinary rowids independently of the standalone FTS table.
    transaction.execute("DELETE FROM documents_fts", [])?;
    transaction.execute(
        "INSERT INTO documents_fts(rowid,id,title,authors,journal,keywords)
         SELECT rowid,id,title,authors,journal,keywords FROM documents",
        [],
    )?;
    transaction.commit()?;
    Ok(())
}

pub struct Storage {
    pub(crate) connection: Connection,
    directory: PathBuf,
}

impl Storage {
    /// `root` is <AppSupport>/OtterPad, never its legacy db/ subdirectory.
    pub fn open(root: impl AsRef<Path>) -> Result<Self> {
        let directory = root.as_ref().join("v2");
        std::fs::create_dir_all(&directory)?;
        let mut connection = Connection::open(directory.join("otter.db"))?;
        connection.busy_timeout(Duration::from_secs(5))?;
        tokenizer::register(&connection)?;
        // Reject unsupported files before changing journal mode or schema.
        initialize(&mut connection)?;
        connection.pragma_update(None, "foreign_keys", "ON")?;
        connection.pragma_update(None, "journal_mode", "WAL")?;
        connection.pragma_update(None, "synchronous", "FULL")?;
        std::fs::create_dir_all(directory.join("library"))?;
        std::fs::create_dir_all(directory.join("logs"))?;
        Ok(Self {
            connection,
            directory,
        })
    }

    pub fn directory(&self) -> &Path {
        &self.directory
    }

    pub fn put_document(&self, document: &Document) -> Result<()> {
        crate::files::component(&document.id)?;
        if document.id.is_empty() {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "empty document id",
            ));
        }
        // UPSERT, not REPLACE: metadata edits must not cascade-delete user notes.
        self.connection.execute(
            "INSERT INTO documents
                (id, title, authors, journal, year, doi, keywords, contentHash, addedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
                title=excluded.title, authors=excluded.authors, journal=excluded.journal,
                year=excluded.year, doi=excluded.doi, keywords=excluded.keywords,
                contentHash=excluded.contentHash, addedAt=excluded.addedAt",
            params![
                document.id,
                document.title,
                serde_json::to_string(&document.authors)?,
                document.journal,
                document.year,
                document.doi,
                serde_json::to_string(&document.keywords)?,
                document.content_hash,
                document.added_at,
            ],
        )?;
        Ok(())
    }

    pub fn document(&self, id: &str) -> Result<Option<Document>> {
        let mut statement = self.connection.prepare(
            "SELECT id, title, authors, journal, year, doi, keywords, contentHash, addedAt
             FROM documents WHERE id=?1",
        )?;
        let mut rows = statement.query([id])?;
        rows.next()?.map(read_document).transpose()
    }

    /// Newest first, with stable ordering when multiple imports share a timestamp.
    pub fn documents(&self, limit: u32, offset: u32) -> Result<Vec<Document>> {
        let mut statement = self.connection.prepare(
            "SELECT id, title, authors, journal, year, doi, keywords, contentHash, addedAt
             FROM documents ORDER BY addedAt DESC, id LIMIT ?1 OFFSET ?2",
        )?;
        let mut rows = statement.query(params![limit, offset])?;
        let mut documents = Vec::new();
        while let Some(row) = rows.next()? {
            documents.push(read_document(row)?);
        }
        Ok(documents)
    }

    pub fn delete_document(&self, id: &str) -> Result<bool> {
        Ok(self
            .connection
            .execute("DELETE FROM documents WHERE id=?1", [id])?
            != 0)
    }

    /// Plain text query; FTS operators supplied by users are never executed.
    pub fn search_documents(&self, query: &str, limit: u32) -> Result<Vec<Document>> {
        let query = query.trim();
        let expression = tokenizer::match_expression(query);
        if expression.is_empty() || limit == 0 {
            return Ok(Vec::new());
        }
        let mut statement = self.connection.prepare(
            "SELECT d.id, d.title, d.authors, d.journal, d.year, d.doi,
                    d.keywords, d.contentHash, d.addedAt
             FROM documents_fts f JOIN documents d ON d.rowid=f.rowid
             WHERE documents_fts MATCH ?1
             ORDER BY bm25(documents_fts), d.addedAt DESC, d.id LIMIT ?2",
        )?;
        let mut documents = Vec::new();
        if !expression.is_empty() {
            let mut rows = statement.query(params![expression, limit])?;
            while let Some(row) = rows.next()? {
                documents.push(read_document(row)?);
            }
        }
        // DOI/year and arbitrary substrings are part of the old library search
        // contract. Keep FTS hits first, then merge all-field LIKE matches.
        if documents.len() < limit as usize {
            let mut seen: std::collections::HashSet<_> =
                documents.iter().map(|d| d.id.clone()).collect();
            let mut statement = self.connection.prepare(
                "SELECT id,title,authors,journal,year,doi,keywords,contentHash,addedAt FROM documents
                 WHERE title LIKE ?1 OR authors LIKE ?1 OR journal LIKE ?1 OR keywords LIKE ?1 OR doi LIKE ?1 OR year LIKE ?1
                 ORDER BY addedAt DESC,id LIMIT ?2",
            )?;
            let mut rows = statement.query(params![format!("%{query}%"), limit])?;
            while let Some(row) = rows.next()? {
                let document = read_document(row)?;
                if seen.insert(document.id.clone()) {
                    documents.push(document);
                }
                if documents.len() == limit as usize {
                    break;
                }
            }
        }
        Ok(documents)
    }

    pub fn setting(&self, key: &str) -> Result<Option<Value>> {
        let value: Option<String> = self
            .connection
            .query_row(
                "SELECT value FROM settings WHERE settingKey=?1",
                [key],
                |row| row.get(0),
            )
            .optional()?;
        value
            .map(|value| serde_json::from_str(&value).map_err(Into::into))
            .transpose()
    }

    /// Credentials belong to the system vault and must never be passed here.
    pub fn put_setting(&self, key: &str, value: &Value) -> Result<()> {
        if crate::credentials::is_secret_setting(key) {
            return Err(OtterError::new(
                ErrorCode::InvalidArgument,
                "credentials belong in the system vault",
            ));
        }
        self.connection.execute(
            "INSERT INTO settings(settingKey,value) VALUES (?1,?2)
             ON CONFLICT(settingKey) DO UPDATE SET value=excluded.value",
            params![key, serde_json::to_string(value)?],
        )?;
        Ok(())
    }

    pub fn delete_setting(&self, key: &str) -> Result<()> {
        self.connection
            .execute("DELETE FROM settings WHERE settingKey=?1", [key])?;
        Ok(())
    }
}

fn initialize(connection: &mut Connection) -> Result<()> {
    let transaction = connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let version: i32 = transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
    let application: i32 =
        transaction.pragma_query_value(None, "application_id", |row| row.get(0))?;
    if version > SCHEMA_VERSION
        || (application != 0 && application != APPLICATION_ID)
        || (version != 0 && application != APPLICATION_ID)
    {
        return Err(OtterError::new(
            ErrorCode::UnsupportedDatabase,
            "unsupported database identity/version",
        ));
    }
    if version == 0 {
        let count: i64 = transaction.query_row(
            "SELECT count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'",
            [],
            |row| row.get(0),
        )?;
        if count != 0 {
            return Err(OtterError::new(
                ErrorCode::UnsupportedDatabase,
                "unversioned nonempty database",
            ));
        }
        transaction.execute_batch(include_str!("schema.sql"))?;
        transaction.pragma_update(None, "application_id", APPLICATION_ID)?;
        transaction.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    }
    let index_version: Option<String> = transaction
        .query_row(
            "SELECT value FROM meta WHERE metaKey='fts:tokenizer_revision'",
            [],
            |r| r.get(0),
        )
        .optional()?;
    if index_version.as_deref() != Some("2") {
        transaction.execute("DELETE FROM documents_fts", [])?;
        transaction.execute("INSERT INTO documents_fts(rowid,id,title,authors,journal,keywords) SELECT rowid,id,title,authors,journal,keywords FROM documents", [])?;
        transaction.execute("INSERT INTO meta(metaKey,value) VALUES ('fts:tokenizer_revision','2') ON CONFLICT(metaKey) DO UPDATE SET value=excluded.value", [])?;
    }
    transaction.commit()?;
    Ok(())
}

fn read_document(row: &rusqlite::Row<'_>) -> Result<Document> {
    Ok(Document {
        id: row.get(0)?,
        title: row.get(1)?,
        authors: serde_json::from_str(&row.get::<_, String>(2)?)?,
        journal: row.get(3)?,
        year: row.get(4)?,
        doi: row.get(5)?,
        keywords: serde_json::from_str(&row.get::<_, String>(6)?)?,
        content_hash: row.get(7)?,
        added_at: row.get(8)?,
    })
}
