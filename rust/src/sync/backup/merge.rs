use super::*;

pub(super) const TABLES: [(&str, &str); 6] = [
    (
        "documents",
        "id,title,authors,journal,year,doi,keywords,contentHash,addedAt",
    ),
    ("favorites", "id,emoji,name,createdAt"),
    (
        "highlights",
        "id,docId,content,note,color,groupId,anchor,createdAt",
    ),
    ("history", "docId,openedAt,progress,anchorBlock"),
    ("favorite_documents", "favoriteId,docId"),
    ("zotero_items", "zoteroKey,docId,version"),
];
pub(super) fn copy_table(
    source: &Storage,
    target: &Storage,
    table: &str,
    columns: &str,
) -> Result<()> {
    // Identifiers are private constants; all row values are bound parameters.
    let count = columns.split(',').count();
    let mut query = source
        .connection
        .prepare(&format!("SELECT {columns} FROM {table}"))?;
    let rows = query.query_map([], |r| {
        (0..count)
            .map(|i| r.get::<_, SqlValue>(i))
            .collect::<rusqlite::Result<Vec<_>>>()
    })?;
    let placeholders = (1..=count)
        .map(|i| format!("?{i}"))
        .collect::<Vec<_>>()
        .join(",");
    let mut insert = target.connection.prepare(&format!(
        "INSERT INTO {table}({columns}) VALUES ({placeholders})"
    ))?;
    for row in rows {
        insert.execute(rusqlite::params_from_iter(row?))?;
    }
    Ok(())
}
pub(super) fn overwrite_library(source: &Storage, target: &mut Storage) -> Result<()> {
    target
        .connection
        .execute_batch("DELETE FROM favorites;DELETE FROM documents;DELETE FROM zotero_items;")?;
    for (table, columns) in TABLES {
        copy_table(source, target, table, columns)?;
    }
    target.connection.execute("DELETE FROM meta WHERE metaKey IN ('zotero_library_version','zotero_user_id') OR substr(metaKey,1,13)='zotero_local:'", [])?;
    let mut query = source.connection.prepare("SELECT metaKey,value FROM meta WHERE metaKey IN ('zotero_library_version','zotero_user_id') OR substr(metaKey,1,13)='zotero_local:'")?;
    for row in query.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (key, value) = row?;
        target.connection.execute(
            "INSERT INTO meta(metaKey,value) VALUES (?1,?2)",
            params![key, value],
        )?;
    }
    Ok(())
}
pub(super) fn replace_meta(source: &Storage, target: &Storage) -> Result<()> {
    target.connection.execute("DELETE FROM meta", [])?;
    copy_table(source, target, "meta", "metaKey,value")
}

pub(super) fn local_setting(key: &str) -> bool {
    key.starts_with("proxy_")
        || key.starts_with("backup_webdav_")
        || key.starts_with("backup_s3_")
        || key == "backup_remote_type"
}
pub(super) fn copy_settings(source: &Storage, target: &Storage, merge: bool) -> Result<usize> {
    let mut query = source
        .connection
        .prepare("SELECT settingKey,value FROM settings")?;
    let mut added = 0;
    for row in query.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (key, value) = row?;
        if crate::credentials::is_secret_setting(&key) || (merge && local_setting(&key)) {
            continue;
        }
        added += target.connection.execute(
            "INSERT INTO settings VALUES (?1,?2) ON CONFLICT(settingKey) DO NOTHING",
            params![key, value],
        )?;
    }
    Ok(added)
}

pub(super) fn merge_library(
    source: &Storage,
    target: &mut Storage,
    report: &mut MergeReport,
    token: &CancellationToken,
) -> Result<()> {
    let mut documents = target.documents(u32::MAX, 0)?;
    for incoming in source.documents(u32::MAX, 0)? {
        check(token)?;
        let same_id = documents.iter().position(|d| d.id == incoming.id);
        let existing = same_id.or_else(|| {
            documents.iter().position(|d| {
                let hash = incoming
                    .content_hash
                    .as_ref()
                    .is_some_and(|h| Some(h) == d.content_hash.as_ref());
                let doi = incoming
                    .doi
                    .as_ref()
                    .map(|s| s.trim().to_lowercase())
                    .filter(|s| !s.is_empty())
                    .is_some_and(|id| {
                        d.doi
                            .as_ref()
                            .is_some_and(|s| s.trim().to_lowercase() == id)
                    });
                let title = key(&d.title);
                let matching_title = !title.is_empty() && title == key(&incoming.title);
                let year = incoming.year.as_deref().is_some_and(|y| {
                    !key(y).is_empty() && Some(key(y)) == d.year.as_deref().map(key)
                });
                let author = incoming.authors.first().is_some_and(|a| {
                    !key(a).is_empty() && Some(key(a)) == d.authors.first().map(|s| key(s))
                });
                hash || doi || (matching_title && (year || author))
            })
        });
        if let Some(index) = existing {
            let current = &mut documents[index];
            report
                .document_ids
                .insert(incoming.id.clone(), current.id.clone());
            if same_id.is_some() {
                let blank = |v: &Option<String>| v.as_ref().is_none_or(|s| s.trim().is_empty());
                if current.authors.is_empty() {
                    current.authors = incoming.authors.clone();
                }
                if current.keywords.is_empty() {
                    current.keywords = incoming.keywords.clone();
                }
                if blank(&current.journal) {
                    current.journal = incoming.journal.clone();
                }
                if blank(&current.year) {
                    current.year = incoming.year.clone();
                }
                if blank(&current.doi) {
                    current.doi = incoming.doi.clone();
                }
                // The selected file is checked and fingerprinted after merging assets.
                target.put_document(current)?;
            }
        } else {
            target.put_document(&incoming)?;
            report
                .document_ids
                .insert(incoming.id.clone(), incoming.id.clone());
            documents.push(incoming);
            report.documents_added += 1;
        }
    }
    let mut highlight_ids: HashSet<String> = {
        let mut q = target.connection.prepare("SELECT id FROM highlights")?;
        q.query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?
    };
    for document in source.documents(u32::MAX, 0)? {
        for mut highlight in library::highlights(source, &document.id)? {
            let Some(id) = report.document_ids.get(&highlight.document_id) else {
                report.skipped_orphans += 1;
                continue;
            };
            if !highlight_ids.insert(highlight.id.clone()) {
                continue;
            }
            highlight.document_id = id.clone();
            library::put_highlight(target, &highlight)?;
            report.highlights_added += 1;
        }
    }
    let live_favorites: HashMap<_, _> = library::favorites(target)?
        .into_iter()
        .map(|f| (f.id.clone(), f))
        .collect();
    for favorite in library::favorites(source)? {
        let mut merged = live_favorites
            .get(&favorite.id)
            .cloned()
            .unwrap_or(Favorite {
                document_ids: Vec::new(),
                ..favorite.clone()
            });
        for doc in favorite.document_ids {
            if let Some(id) = report.document_ids.get(&doc) {
                if !merged.document_ids.contains(id) {
                    merged.document_ids.push(id.clone());
                }
            } else {
                report.skipped_orphans += 1;
            }
        }
        library::put_favorite(target, &merged)?;
    }
    let mut history: HashMap<_, _> = library::history(target, u32::MAX, 0)?
        .into_iter()
        .map(|h| (h.document_id.clone(), h))
        .collect();
    for mut entry in library::history(source, u32::MAX, 0)? {
        let Some(id) = report.document_ids.get(&entry.document_id) else {
            report.skipped_orphans += 1;
            continue;
        };
        entry.document_id = id.clone();
        let newer = history.get(id).is_none_or(|old| {
            entry.opened_at > old.opened_at
                || (entry.opened_at == old.opened_at && entry.progress > old.progress)
        });
        if newer {
            library::record_history(target, &entry)?;
            history.insert(id.clone(), entry);
        }
    }
    target.connection.execute("DELETE FROM history WHERE docId NOT IN (SELECT docId FROM history ORDER BY openedAt DESC,docId LIMIT 500)",[])?;
    for (backup_id, live_id) in &report.document_ids {
        let from = source
            .directory()
            .join("library")
            .join(files::component(backup_id)?);
        let to = target
            .directory()
            .join("library")
            .join(files::component(live_id)?);
        let assets = archive::checksums(&from, Some(BackupScope::Full), token)?;
        for (name, hash) in assets {
            check(token)?;
            let path = to.join(&name);
            if !path.exists() {
                let one = BTreeMap::from([(name, hash)]);
                report.files_copied += copy_checked(&from, &to, &one, token)?;
            } else if name == "translations.json" {
                merge_translations(&from.join(name), &path)?;
            }
        }
    }
    Ok(())
}

pub(super) fn merge_translations(source: &Path, target: &Path) -> Result<()> {
    type Layers = BTreeMap<String, BTreeMap<String, String>>;
    let incoming: Layers = serde_json::from_slice(&fs::read(source)?)?;
    let mut local: Layers = serde_json::from_slice(&fs::read(target)?)?;
    for (language, values) in incoming {
        let layer = local.entry(language).or_default();
        for (hash, text) in values {
            layer.entry(hash).or_insert(text);
        }
    }
    files::write_json(target, &local)
}

pub(super) fn merge_zotero(
    source: &Storage,
    target: &Storage,
    mapping: &BTreeMap<String, String>,
    skipped: &mut usize,
) -> Result<()> {
    let account = |db: &Storage| -> Result<Option<String>> {
        Ok(db
            .connection
            .query_row(
                "SELECT value FROM meta WHERE metaKey='zotero_user_id'",
                [],
                |r| r.get(0),
            )
            .optional()?)
    };
    let source_account = account(source)?;
    let target_account = account(target)?;
    let same_account =
        source_account.is_none() || target_account.is_none() || source_account == target_account;
    let mut query = source
        .connection
        .prepare("SELECT zoteroKey,docId,version FROM zotero_items")?;
    for row in query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, Option<String>>(1)?,
            r.get::<_, i64>(2)?,
        ))
    })? {
        let (key, document, version) = row?;
        if !same_account {
            *skipped += 1;
            continue;
        }
        let document = if let Some(document) = document {
            let Some(id) = mapping.get(&document) else {
                *skipped += 1;
                continue;
            };
            Some(id.clone())
        } else {
            None
        };
        target.connection.execute(
            "INSERT INTO zotero_items VALUES (?1,?2,?3) ON CONFLICT(zoteroKey) DO NOTHING",
            params![key, document, version],
        )?;
    }
    let cursor = |db: &Storage| -> Result<i64> {
        Ok(db
            .connection
            .query_row(
                "SELECT value FROM meta WHERE metaKey='zotero_library_version'",
                [],
                |r| r.get::<_, String>(0),
            )
            .optional()?
            .and_then(|s| s.parse().ok())
            .unwrap_or(0))
    };
    if same_account {
        let version = cursor(source)?.max(cursor(target)?);
        target.connection.execute("INSERT INTO meta VALUES ('zotero_library_version',?1) ON CONFLICT(metaKey) DO UPDATE SET value=excluded.value",[version.to_string()])?;
        if target_account.is_none()
            && let Some(account) = source_account
        {
            target
                .connection
                .execute("INSERT INTO meta VALUES ('zotero_user_id',?1)", [account])?;
        }
    }
    let mut query = source
        .connection
        .prepare("SELECT metaKey,value FROM meta WHERE substr(metaKey,1,13)='zotero_local:'")?;
    for row in query.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (key, value) = row?;
        let mut record: serde_json::Value = serde_json::from_str(&value)?;
        let document = record["documentId"].as_str().ok_or_else(|| {
            OtterError::new(ErrorCode::InvalidData, "Zotero local record document ID")
        })?;
        let Some(id) = mapping.get(document) else {
            *skipped += 1;
            continue;
        };
        record["documentId"] = serde_json::json!(id);
        target.connection.execute(
            "INSERT INTO meta(metaKey,value) VALUES (?1,?2) ON CONFLICT(metaKey) DO NOTHING",
            params![key, serde_json::to_string(&record)?],
        )?;
    }
    Ok(())
}

pub(super) fn key(text: &str) -> String {
    text.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}
