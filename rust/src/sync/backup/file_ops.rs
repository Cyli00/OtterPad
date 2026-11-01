use super::*;

pub(super) fn validate(storage: &Storage) -> Result<()> {
    for document in storage.documents(u32::MAX, 0)? {
        files::component(&document.id)?;
    }
    let result: String = storage
        .connection
        .query_row("PRAGMA quick_check", [], |r| r.get(0))?;
    if result != "ok"
        || storage
            .connection
            .prepare("PRAGMA foreign_key_check")?
            .exists([])?
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "backup database integrity",
        ));
    }
    Ok(())
}
pub(super) fn sync_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    File::open(path)?.sync_all()?;
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}
pub(super) fn sync_directories(root: &Path) -> Result<()> {
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            sync_directories(&entry.path())?;
        }
    }
    sync_directory(root)
}

pub(super) fn copy_checked(
    source: &Path,
    target: &Path,
    files: &BTreeMap<String, String>,
    token: &CancellationToken,
) -> Result<usize> {
    let mut copied = 0;
    for (name, expected) in files {
        check(token)?;
        archive::safe_relative(name)?;
        let path = target.join(name);
        fs::create_dir_all(path.parent().unwrap())?;
        let mut input = File::open(source.join(name))?;
        let mut output = File::create(&path)?;
        let mut hash = Sha256::new();
        let mut buffer = [0u8; 64 * 1024];
        loop {
            check(token)?;
            let count = input.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            hash.update(&buffer[..count]);
            output.write_all(&buffer[..count])?;
        }
        output.sync_all()?;
        let actual = hash
            .finalize()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        if actual != *expected {
            return Err(OtterError::new(
                ErrorCode::Conflict,
                "file changed during restore copy",
            ));
        }
        copied += 1;
    }
    Ok(copied)
}

pub(super) fn remove_legacy_orphans(path: &Path) -> Result<usize> {
    let mut db = Connection::open(path)?;
    let tx = db.transaction()?;
    let mut removed = 0;
    for sql in [
        "DELETE FROM highlights WHERE docId NOT IN (SELECT id FROM documents)",
        "DELETE FROM history WHERE docId NOT IN (SELECT id FROM documents)",
        "DELETE FROM favorite_documents WHERE docId NOT IN (SELECT id FROM documents) OR favoriteId NOT IN (SELECT id FROM favorites)",
        "DELETE FROM zotero_items WHERE docId IS NOT NULL AND docId NOT IN (SELECT id FROM documents)",
    ] {
        removed += tx.execute(sql, [])?;
    }
    tx.commit()?;
    Ok(removed)
}
