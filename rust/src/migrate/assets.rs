use super::*;

pub(super) fn copy_document(source: &Path, target: &Path, token: &CancellationToken) -> Result<()> {
    if fs::symlink_metadata(source)?.file_type().is_symlink() {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "legacy document symlink",
        ));
    }
    for entry in fs::read_dir(source)? {
        tasks::check(token)?;
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let ty = entry.file_type()?;
        if ty.is_symlink() {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "legacy asset symlink",
            ));
        }
        if ty.is_dir() && ["figures", "chats", "summary"].contains(&name.as_str()) {
            copy_tree(&entry.path(), &target.join(&name), token)?;
        } else if ty.is_file()
            && (name == "source.pdf"
                || name == "mineru.exports.zip"
                || name == "extract.json"
                || (name.starts_with("extract.")
                    && (name.ends_with(".json") || name.ends_with(".raw.md")))
                || name == "extract.raw.md")
        {
            copy_file(&entry.path(), &target.join(name))?;
        }
    }
    Ok(())
}
pub(super) fn copy_tree(source: &Path, target: &Path, token: &CancellationToken) -> Result<()> {
    fs::create_dir_all(target)?;
    for entry in fs::read_dir(source)? {
        tasks::check(token)?;
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_symlink() {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "legacy tree symlink",
            ));
        }
        let target = target.join(entry.file_name());
        if ty.is_dir() {
            copy_tree(&entry.path(), &target, token)?;
        } else if ty.is_file() {
            copy_file(&entry.path(), &target)?;
        }
    }
    Ok(())
}
pub(super) fn copy_file(source: &Path, target: &Path) -> Result<()> {
    fs::copy(source, target)?;
    fs::OpenOptions::new().write(true).open(target)?.flush()?;
    fs::File::open(target)?.sync_all()?;
    Ok(())
}

pub(super) fn relocate(raw: Option<&str>, content: &str, model: &DocumentModel) -> Value {
    let old = raw.and_then(|s| serde_json::from_str::<Value>(s).ok());
    let anchor = old
        .as_ref()
        .and_then(|v| serde_json::from_value::<Anchor>(v.clone()).ok());
    let requested = anchor.map(|a| a.ranges).unwrap_or_else(|| {
        vec![AnchorRange {
            block_id: String::new(),
            language: "source".into(),
            revision: String::new(),
            start: 0,
            end: 0,
            quote: content.into(),
            prefix: String::new(),
            suffix: String::new(),
        }]
    });
    let resolved: Vec<_> = requested.iter().filter_map(|r| model.resolve(r)).collect();
    let complete = resolved.len() == requested.len() && !requested.is_empty();
    json!({"version":2,"ranges":resolved,"located":complete,"legacy_anchor":old,"legacy_raw":if old.is_none(){raw}else{None}})
}

pub(super) fn unique_block<'a>(
    model: &'a DocumentModel,
    text: &str,
) -> Option<&'a crate::document::Block> {
    let mut matches = model
        .blocks
        .iter()
        .filter(|b| b.owner_id.is_none() && plain_text(&b.markdown) == text);
    let found = matches.next()?;
    if matches.next().is_some() {
        None
    } else {
        Some(found)
    }
}

pub fn legacy_hash(text: &str) -> String {
    let text = text.trim();
    let mut hash = 0u32;
    for unit in text.encode_utf16() {
        hash = hash.wrapping_add(u32::from(unit));
        hash = hash.wrapping_add(hash << 10);
        hash ^= hash >> 6;
    }
    hash = hash.wrapping_add(hash << 3);
    hash ^= hash >> 11;
    hash = hash.wrapping_add(hash << 15);
    hash &= 0x3fff_ffff;
    if hash == 0 {
        hash = 1;
    }
    format!("{}_{hash:x}", text.encode_utf16().count())
}

pub(super) fn map_translations(old: &Value, model: &DocumentModel, markdown: &str) -> Value {
    let mut hashes = BTreeMap::new();
    for block in &model.blocks {
        hashes.insert(
            legacy_hash(&block.markdown),
            revision(block.markdown.trim()),
        );
    }
    for block in DocumentModel::from_markdown(markdown).blocks {
        if let Some(target) = unique_block(model, &plain_text(&block.markdown)) {
            hashes.insert(
                legacy_hash(&block.markdown),
                revision(target.markdown.trim()),
            );
        }
    }
    let mut mapped = serde_json::Map::new();
    for (language, cache) in old.as_object().into_iter().flatten() {
        let mut values = serde_json::Map::new();
        for (hash, value) in cache.as_object().into_iter().flatten() {
            if let Some(target) = hashes.get(hash).filter(|_| value.is_string()) {
                values.insert(target.clone(), value.clone());
            }
        }
        mapped.insert(language.clone(), Value::Object(values));
    }
    Value::Object(mapped)
}
