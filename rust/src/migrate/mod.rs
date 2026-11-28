//! v0.1.x import is copy-only and commits a document and its marker together.
use std::{collections::BTreeMap, fs, path::Path};

use rusqlite::{Connection, OpenFlags, OptionalExtension, params};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use crate::{
    document::{Anchor, AnchorRange, DocumentModel, plain_text, revision, structure::Structure},
    error::{ErrorCode, OtterError, Result},
    files,
    storage::Storage,
    tasks,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrationProgress {
    pub done: usize,
    pub total: usize,
    pub document_id: Option<String>,
    pub complete: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrationFailure {
    pub document_id: String,
    pub code: ErrorCode,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrationReport {
    pub imported: usize,
    pub already_imported: usize,
    pub failures: Vec<MigrationFailure>,
    pub complete: bool,
}

pub fn run(
    storage: &mut Storage,
    legacy_root: &Path,
    token: &CancellationToken,
    mut progress: impl FnMut(MigrationProgress),
) -> Result<MigrationReport> {
    tasks::check(token)?;
    let path = legacy_root.join("db/otter.db");
    if !path.is_file() {
        return Err(OtterError::new(
            ErrorCode::NotFound,
            "legacy database missing",
        ));
    }
    let source = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    let version: i32 = source.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if !(1..=2).contains(&version) {
        return Err(OtterError::new(
            ErrorCode::UnsupportedDatabase,
            "unsupported legacy schema",
        ));
    }
    // Hold a consistent read snapshot, including WAL contents, for the whole run.
    source.execute_batch("BEGIN")?;
    if source.prepare("PRAGMA foreign_key_check")?.exists([])? {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "legacy foreign-key violation",
        ));
    }
    for table in [
        "documents",
        "highlights",
        "history",
        "favorites",
        "favorite_documents",
        "zotero_items",
        "settings",
        "meta",
    ] {
        let check: String =
            source.query_row(&format!("PRAGMA quick_check({table})"), [], |r| r.get(0))?;
        if check != "ok" {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "legacy table integrity check failed",
            ));
        }
    }
    let mut statement = source.prepare("SELECT id FROM documents ORDER BY addedAt,id")?;
    let ids = statement
        .query_map([], |r| r.get::<_, String>(0))?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    drop(statement);
    import_globals(storage, &source)?;
    let mut report = MigrationReport {
        imported: 0,
        already_imported: 0,
        failures: vec![],
        complete: false,
    };
    progress(MigrationProgress {
        done: 0,
        total: ids.len(),
        document_id: None,
        complete: false,
    });
    for (index, id) in ids.iter().enumerate() {
        tasks::check(token)?;
        if marked(&storage.connection, &format!("migration:v1:document:{id}"))? {
            report.already_imported += 1;
        } else {
            match import_document(storage, &source, legacy_root, id, version, token) {
                Ok(()) => report.imported += 1,
                Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                Err(error) => report.failures.push(MigrationFailure {
                    document_id: id.clone(),
                    code: error.code,
                }),
            }
        }
        progress(MigrationProgress {
            done: index + 1,
            total: ids.len(),
            document_id: Some(id.clone()),
            complete: false,
        });
    }
    tasks::check(token)?;
    if report.failures.is_empty() {
        // Relations without a document id are library-level sync metadata.
        let mut rows =
            source.prepare("SELECT zoteroKey,version FROM zotero_items WHERE docId IS NULL")?;
        for row in rows.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))? {
            let (key, version) = row?;
            storage.connection.execute("INSERT INTO zotero_items(zoteroKey,docId,version) VALUES (?1,NULL,?2) ON CONFLICT(zoteroKey) DO NOTHING",params![key,version])?;
        }
        storage.connection.execute("INSERT INTO meta(metaKey,value) VALUES ('migration:v1:complete','1') ON CONFLICT(metaKey) DO UPDATE SET value='1'",[])?;
        report.complete = true;
    }
    progress(MigrationProgress {
        done: ids.len(),
        total: ids.len(),
        document_id: None,
        complete: report.complete,
    });
    Ok(report)
}

fn marked(connection: &Connection, key: &str) -> Result<bool> {
    Ok(connection.query_row(
        "SELECT EXISTS(SELECT 1 FROM meta WHERE metaKey=?1 AND value='1')",
        [key],
        |r| r.get(0),
    )?)
}

fn import_globals(storage: &mut Storage, source: &Connection) -> Result<()> {
    let transaction = storage.connection.transaction()?;
    let mut favorites = source.prepare("SELECT id,emoji,name,createdAt FROM favorites")?;
    for row in favorites.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, i64>(3)?,
        ))
    })? {
        let (id, emoji, name, created) = row?;
        transaction.execute(
            "INSERT INTO favorites VALUES (?1,?2,?3,?4) ON CONFLICT(id) DO NOTHING",
            params![id, emoji, name, created],
        )?;
    }
    let mut settings = source.prepare("SELECT settingKey,value FROM settings")?;
    for row in settings.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (key, value) = row?;
        if known_setting(&key) {
            // SettingsStore also accepted old non-JSON strings. Preserve their value.
            let value = serde_json::from_str::<Value>(&value).unwrap_or(Value::String(value));
            transaction.execute(
                "INSERT INTO settings VALUES (?1,?2) ON CONFLICT(settingKey) DO NOTHING",
                params![key, serde_json::to_string(&value)?],
            )?;
        }
    }
    let mut meta = source.prepare("SELECT metaKey,value FROM meta")?;
    for row in meta.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (key, value) = row?;
        if !key.starts_with("migration:") {
            transaction.execute(
                "INSERT INTO meta VALUES (?1,?2) ON CONFLICT(metaKey) DO NOTHING",
                params![key, value],
            )?;
        }
    }
    transaction.commit()?;
    Ok(())
}

fn import_document(
    storage: &mut Storage,
    source: &Connection,
    root: &Path,
    id: &str,
    version: i32,
    token: &CancellationToken,
) -> Result<()> {
    files::component(id)?;
    let exists: bool = storage.connection.query_row(
        "SELECT EXISTS(SELECT 1 FROM documents WHERE id=?1)",
        [id],
        |r| r.get(0),
    )?;
    if exists {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "v2 document already exists without migration marker",
        ));
    }
    let library = storage.directory().join("library");
    let stage = library.join(format!(".migrate-{id}"));
    let target = library.join(id);
    let marker = json!({"document_id":id,"version":1});
    for directory in [&stage, &target] {
        if directory.exists() {
            if fs::symlink_metadata(directory)?.file_type().is_symlink() {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "migration destination symlink",
                ));
            }
            if !directory.join(".migration-origin").exists()
                && fs::read_dir(directory)?.next().is_none()
            {
                continue;
            }
            let previous: Value =
                serde_json::from_slice(&fs::read(directory.join(".migration-origin"))?)?;
            if previous != marker {
                return Err(OtterError::new(
                    ErrorCode::Conflict,
                    "migration directory belongs to another operation",
                ));
            }
        }
    }
    if stage.exists() {
        fs::remove_dir_all(&stage)?;
    }
    fs::create_dir_all(&stage)?;
    files::write_json(&stage.join(".migration-origin"), &marker)?;
    let old_directory = root.join("library").join(id);
    if old_directory.exists() {
        copy_document(&old_directory, &stage, token)?;
    }
    let model = if stage.join("extract.json").is_file() {
        let structure = Structure::parse(&fs::read_to_string(stage.join("extract.json"))?)?;
        let model = DocumentModel::from_structure(&structure);
        files::write_json(&stage.join("structure.json"), &structure)?;
        model
    } else if stage.join("extract.raw.md").is_file() {
        DocumentModel::from_markdown(&fs::read_to_string(stage.join("extract.raw.md"))?)
    } else {
        DocumentModel {
            version: 1,
            blocks: vec![],
            figures: vec![],
        }
    };
    files::write_json(&stage.join("document.json"), &model)?;
    if old_directory.join("translations.json").is_file() {
        let old: Value =
            serde_json::from_slice(&fs::read(old_directory.join("translations.json"))?)?;
        let markdown = fs::read_to_string(stage.join("extract.raw.md")).unwrap_or_default();
        files::write_json(
            &stage.join("translations.json"),
            &map_translations(&old, &model, &markdown),
        )?;
    }
    tasks::check(token)?;
    if target.exists() {
        // A previous process published files but never committed its SQL. Keep
        // that recoverable generation until this document transaction succeeds.
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| OtterError::new(ErrorCode::Io, "system clock before epoch"))?
            .as_nanos();
        let stale = library.join(format!(".migrate-previous-{id}-{nonce}"));
        fs::rename(&target, &stale)?;
    }
    fs::rename(&stage, &target)?;
    tasks::check(token)?;
    let transaction = storage.connection.transaction()?;
    let values=source.query_row("SELECT id,title,authors,journal,year,doi,keywords,contentHash,addedAt FROM documents WHERE id=?1",[id],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?,r.get::<_,Option<String>>(3)?,r.get::<_,Option<String>>(4)?,r.get::<_,Option<String>>(5)?,r.get::<_,String>(6)?,r.get::<_,Option<String>>(7)?,r.get::<_,i64>(8)?)))?;
    // Validate JSON before importing malformed metadata into a typed v2 record.
    serde_json::from_str::<Vec<String>>(&values.2)?;
    serde_json::from_str::<Vec<String>>(&values.6)?;
    transaction.execute(
        "INSERT INTO documents VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
        params![
            values.0, values.1, values.2, values.3, values.4, values.5, values.6, values.7,
            values.8
        ],
    )?;
    let query = format!(
        "SELECT id,content,note,color,groupId,{},createdAt FROM highlights WHERE docId=?1",
        if version >= 2 { "anchor" } else { "NULL" }
    );
    let mut highlights = source.prepare(&query)?;
    for row in highlights.query_map([id], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, Option<String>>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, Option<String>>(4)?,
            r.get::<_, Option<String>>(5)?,
            r.get::<_, i64>(6)?,
        ))
    })? {
        let (highlight, content, note, color, group, old_anchor, created) = row?;
        let anchor = relocate(old_anchor.as_deref(), &content, &model);
        transaction.execute(
            "INSERT INTO highlights VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
            params![
                highlight,
                id,
                content,
                note,
                color,
                group,
                serde_json::to_string(&anchor)?,
                created
            ],
        )?;
    }
    let old_markdown = fs::read_to_string(old_directory.join("extract.md")).unwrap_or_default();
    if let Some((opened, progress, old_anchor)) = source
        .query_row(
            "SELECT openedAt,progress,anchorBlock FROM history WHERE docId=?1",
            [id],
            |r| {
                Ok((
                    r.get::<_, i64>(0)?,
                    r.get::<_, f64>(1)?,
                    r.get::<_, Option<i64>>(2)?,
                ))
            },
        )
        .optional()?
    {
        let anchor = old_anchor.filter(|v| *v >= 0).and_then(|index| {
            DocumentModel::from_markdown(&old_markdown)
                .blocks
                .get(index as usize)
                .and_then(|b| unique_block(&model, &plain_text(&b.markdown)))
                .map(|b| b.id.clone())
        });
        transaction.execute(
            "INSERT INTO history VALUES (?1,?2,?3,?4)",
            params![id, opened, progress, anchor],
        )?;
    }
    let mut relations =
        source.prepare("SELECT favoriteId FROM favorite_documents WHERE docId=?1")?;
    for favorite in relations.query_map([id], |r| r.get::<_, String>(0))? {
        transaction.execute(
            "INSERT INTO favorite_documents VALUES (?1,?2)",
            params![favorite?, id],
        )?;
    }
    let mut zotero = source.prepare("SELECT zoteroKey,version FROM zotero_items WHERE docId=?1")?;
    for row in zotero.query_map([id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))? {
        let (key, version) = row?;
        transaction.execute(
            "INSERT INTO zotero_items VALUES (?1,?2,?3)",
            params![key, id, version],
        )?;
    }
    tasks::check(token)?;
    transaction.execute(
        "INSERT INTO meta VALUES (?1,'1')",
        [format!("migration:v1:document:{id}")],
    )?;
    transaction.commit()?;
    // These directories are generated by this importer, never legacy content.
    for entry in fs::read_dir(&library)? {
        let entry = entry?;
        if entry
            .file_name()
            .to_string_lossy()
            .starts_with(&format!(".migrate-previous-{id}-"))
            && entry.file_type()?.is_dir()
            && fs::read(entry.path().join(".migration-origin"))
                .ok()
                .and_then(|s| serde_json::from_slice::<Value>(&s).ok())
                .as_ref()
                == Some(&marker)
        {
            let _ = fs::remove_dir_all(entry.path());
        }
    }
    Ok(())
}

fn known_setting(key: &str) -> bool {
    const KEYS: &str = "general_log_enabled general_log_level general_haptics_enabled general_cache_auto_cleanup general_auto_check_update general_http2_enabled general_ignored_update_version app_locale zotero_local_port zotero_local_directory hasSeenOnboarding nav_rail_extended theme_mode seed_color use_dynamic_color text_scale app_font proxy_mode proxy_host proxy_port reader_theme reader_font reader_font_size reader_desktop_horizontal_margin reader_desktop_vertical_margin reader_default_mode reader_pagination_mode reader_sidebar_width web_search_provider chat_stream_enabled chat_new_session_hint_dismissed mimo_search_plugin_hint_dismissed translation_config_target_language translation_config_temperature translation_config_display_style translation_config_ignore_sections image_generation_aspect_ratio image_generation_fidelity image_generation_max_reference_images auto_backup_interval auto_backup_scope backup_remote_type backup_webdav_server_url backup_webdav_username backup_webdav_remote_dir backup_webdav_file_name backup_s3_endpoint backup_s3_region backup_s3_bucket backup_s3_access_key_id backup_s3_object_key backup_s3_use_path_style last_backup_snapshot model_caps_last_fetched_at model_caps_etag model_caps_last_modified model_caps_version agent_api_provider_ids agent_api_last_instance agent_api_default_model_global agent_api_fast_model_global agent_api_image_model_global agent_api_caps_migration_v1 translation_config_system_prompt translation_config_user_prompt prompt_chat_system image_generation_prompt doc_extract_provider doc_extract_usage";
    const PREFIXES: [&str; 7] = [
        "agent_api_name_",
        "agent_api_protocol_",
        "agent_api_base_url_",
        "agent_api_models_",
        "agent_api_model_params_",
        "agent_api_model_caps_",
        "agent_api_model_tools_",
    ];
    const OCR_FIELDS: [&str; 20] = [
        "useChartRecognition",
        "useDocOrientationClassify",
        "useDocUnwarping",
        "useSealRecognition",
        "useOcrForImageBlock",
        "restructurePages",
        "layoutNms",
        "mergeTables",
        "layoutShapeMode",
        "repetitionPenalty",
        "temperature",
        "markdownIgnoreLabels",
        "mineruIsOcr",
        "mineruEnableFormula",
        "mineruEnableTable",
        "mineruLanguage",
        "mineruExtraFormats",
        "provider",
        "usage",
        "api_url",
    ];
    KEYS.split_whitespace().any(|k| k == key)
        || PREFIXES
            .iter()
            .any(|p| key.starts_with(p) && key.len() > p.len())
        || key
            .strip_prefix("doc_extract_")
            .is_some_and(|field| OCR_FIELDS.contains(&field))
}

mod assets;
pub use assets::legacy_hash;
use assets::*;
