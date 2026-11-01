use super::document_directory;
use crate::{
    error::{ErrorCode, OtterError, Result},
    files,
    storage::{Document, Storage},
    sync::archive::{self, Stage},
    tasks::check,
};
use serde::{Deserialize, Serialize};
use std::{fs, path::Path};
use tokio_util::sync::CancellationToken;

#[derive(Serialize, Deserialize)]
struct Checkpoint {
    version: u32,
    document_id: String,
    stage: String,
    previous: String,
    new_hash: String,
    had_directory: bool,
}

/// The caller closes reader handles and excludes other document writers first.
/// User files survive; only artifacts derived from a changed PDF are invalidated.
pub fn replace_pdf(
    storage: &Storage,
    source: &Path,
    expected: &Document,
    token: &CancellationToken,
) -> Result<Document> {
    check(token)?;
    if storage.document(&expected.id)?.as_ref() != Some(expected) {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "document changed before PDF replacement",
        ));
    }
    let stage = Stage::new(storage.directory(), "pdf-replace")?;
    let prepared = stage.path.join("document");
    fs::create_dir(&prepared)?;
    archive::atomic_copy(source, &prepared.join("source.pdf"), token)?;
    use std::io::Read;
    let mut header = [0; 5];
    let count = std::fs::File::open(prepared.join("source.pdf"))?.read(&mut header)?;
    if count != 5 || &header != b"%PDF-" {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "replacement is not PDF",
        ));
    }
    let hash = archive::hash_file(&prepared.join("source.pdf"), token)?[..24].to_owned();
    let target = document_directory(storage, &expected.id)?;
    if target.join("source.pdf").is_file()
        && archive::hash_file(&target.join("source.pdf"), token)?[..24] == hash
    {
        let mut unchanged = expected.clone();
        unchanged.content_hash = Some(hash);
        let transaction = storage.connection.unchecked_transaction()?;
        if storage.document(&expected.id)?.as_ref() != Some(expected) {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "document changed during PDF preparation",
            ));
        }
        if &unchanged != expected {
            storage.put_document(&unchanged)?;
        }
        transaction.commit()?;
        return Ok(unchanged);
    }
    let current_files = archive::checksums(&target, None, token)?;
    for name in current_files.keys().filter(|name| !derived(name)) {
        let destination = prepared.join(name);
        fs::create_dir_all(destination.parent().unwrap())?;
        archive::atomic_copy(&target.join(name), &destination, token)?;
    }
    let mut document = expected.clone();
    document.content_hash = Some(hash.clone());
    let transaction = storage.connection.unchecked_transaction()?;
    if storage.document(&expected.id)?.as_ref() != Some(expected) {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "document changed during PDF preparation",
        ));
    }
    // Constraint checks happen before moving files. The transaction remains open
    // until the directory publication finishes, so readers never see half a swap.
    storage.put_document(&document)?;
    let name = stage.path.file_name().unwrap().to_str().unwrap().to_owned();
    let checkpoint = Checkpoint {
        version: 1,
        document_id: expected.id.clone(),
        previous: format!("{name}.previous"),
        stage: name,
        new_hash: hash,
        had_directory: target.is_dir(),
    };
    let marker = marker(storage, &expected.id)?;
    if marker.exists() {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "PDF replacement pending",
        ));
    }
    check(token)?;
    sync_tree(&prepared)?;
    files::write_json(&marker, &checkpoint)?;
    let result = (|| -> Result<()> {
        if checkpoint.had_directory {
            fs::rename(&target, storage.directory().join(&checkpoint.previous))?;
        }
        fs::rename(&prepared, &target)?;
        sync(storage.directory())?;
        sync(target.parent().unwrap())?;
        transaction.commit()?;
        Ok(())
    })();
    if let Err(error) = result {
        // A failed SQLite commit drops/rolls back its transaction before recovery.
        recover_one(storage, &marker)?;
        return Err(error);
    }
    recover_one(storage, &marker)?;
    Ok(document)
}

pub fn recover_replacements(storage: &Storage) -> Result<()> {
    for entry in fs::read_dir(storage.directory())? {
        let entry = entry?;
        if entry.file_type()?.is_file()
            && entry
                .file_name()
                .to_str()
                .is_some_and(|s| s.starts_with(".pdf-replace-") && s.ends_with(".json"))
        {
            recover_one(storage, &entry.path())?;
        }
    }
    Ok(())
}
fn recover_one(storage: &Storage, marker: &Path) -> Result<()> {
    let checkpoint: Checkpoint = serde_json::from_slice(&fs::read(marker)?)?;
    files::component(&checkpoint.document_id)?;
    files::component(&checkpoint.stage)?;
    files::component(&checkpoint.previous)?;
    if checkpoint.version != 1
        || !checkpoint.stage.starts_with(".pdf-replace-")
        || checkpoint.previous != format!("{}.previous", checkpoint.stage)
        || checkpoint.new_hash.len() != 24
        || !checkpoint.new_hash.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "PDF replacement checkpoint",
        ));
    }
    let target = document_directory(storage, &checkpoint.document_id)?;
    let previous = storage.directory().join(&checkpoint.previous);
    let stage = storage.directory().join(&checkpoint.stage);
    let committed = storage
        .document(&checkpoint.document_id)?
        .is_some_and(|d| d.content_hash.as_deref() == Some(&checkpoint.new_hash));
    if committed {
        if !target.join("source.pdf").is_file()
            || archive::hash_file(&target.join("source.pdf"), &CancellationToken::new())?[..24]
                != checkpoint.new_hash
        {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "committed PDF replacement missing or changed",
            ));
        }
        if previous.exists() && fs::remove_dir_all(&previous).is_err() {
            return Ok(());
        }
    } else if previous.exists() {
        if target.exists() {
            quarantine(storage, &checkpoint, &target)?;
        }
        fs::rename(previous, &target)?;
    } else if !checkpoint.had_directory && !stage.join("document").exists() && target.exists() {
        quarantine(storage, &checkpoint, &target)?;
    }
    // Before publication the stage has only copies; the previous directory always
    // lives outside this stage so an interrupted cleanup cannot erase the old PDF.
    if stage.exists() {
        fs::remove_dir_all(stage)?;
    }
    sync(target.parent().unwrap())?;
    fs::remove_file(marker)?;
    sync(storage.directory())
}
fn quarantine(storage: &Storage, checkpoint: &Checkpoint, target: &Path) -> Result<()> {
    let path = storage
        .directory()
        .join(format!("{}.uncommitted", checkpoint.stage));
    if path.exists() {
        return Err(OtterError::new(
            ErrorCode::Conflict,
            "uncommitted PDF recovery exists",
        ));
    }
    fs::rename(target, path)?;
    Ok(())
}
fn marker(storage: &Storage, id: &str) -> Result<std::path::PathBuf> {
    Ok(storage
        .directory()
        .join(format!(".pdf-replace-{}.json", files::component(id)?)))
}
fn derived(name: &str) -> bool {
    let first = name.split('/').next().unwrap_or("");
    [
        "source.pdf",
        "ocr",
        "figures",
        "summary",
        "translations.json",
        "document.json",
        "structure.json",
        "ocr-current.json",
        "mineru.exports.zip",
        "extract.md",
        "extract.json",
    ]
    .contains(&first)
        || first.starts_with("extract.")
        || first.starts_with(".reader.html")
}
fn sync(directory: &Path) -> Result<()> {
    #[cfg(unix)]
    std::fs::File::open(directory)?.sync_all()?;
    #[cfg(not(unix))]
    let _ = directory;
    Ok(())
}
fn sync_tree(directory: &Path) -> Result<()> {
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            sync_tree(&entry.path())?;
        }
    }
    sync(directory)
}
