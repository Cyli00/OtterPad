use super::*;

pub fn mineru_package(bytes: &[u8], page_sizes: &[Vec<f64>]) -> Result<OcrOutput> {
    let mut markdown = None;
    let mut layout = None;
    let mut v2 = None;
    let mut assets = BTreeMap::new();
    for (name, content) in super::chunks::read_zip(bytes)? {
        match name.as_str() {
            "full.md" => {
                markdown = Some(String::from_utf8(content).map_err(|_| {
                    OtterError::new(ErrorCode::InvalidData, "invalid OCR Markdown UTF-8")
                })?)
            }
            n if n.ends_with("_content_list_v2.json") => {
                v2 = Some(serde_json::from_slice::<Value>(&content)?)
            }
            n if n == "layout.json" || n.ends_with("_middle.json") => {
                let value: Value = serde_json::from_slice(&content)?;
                if value["pdf_info"].is_array() {
                    layout = Some(value);
                }
            }
            n if n.starts_with("images/") => {
                assets.insert(name, content);
            }
            _ => {}
        }
    }
    let raw_markdown =
        markdown.ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "missing full.md"))?;
    let (raw, structure) = if let Some(raw) = layout {
        let structure = Structure::from_mineru_layout(&raw)?;
        (raw, structure)
    } else if let Some(raw) = v2 {
        let structure = Structure::from_mineru_v2(
            raw.as_array()
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "invalid v2 pages"))?,
            page_sizes,
        )?;
        (raw, structure)
    } else {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "missing MinerU structure",
        ));
    };
    let model = DocumentModel::from_structure(&structure);
    Ok(OcrOutput {
        provider: Provider::Mineru,
        raw,
        raw_markdown,
        structure,
        model,
        assets,
        export_zip: Some(bytes.to_vec()),
    })
}

/// Multi-file publication commits one pointer last; cancellation preserves the
/// previously selected extraction and never exposes a half-written generation.
pub fn publish(directory: &Path, output: &OcrOutput, token: &CancellationToken) -> Result<String> {
    tasks::check(token)?;
    let mut hash = sha2::Sha256::new();
    use sha2::Digest;
    fn part(hash: &mut sha2::Sha256, value: &impl Serialize) -> Result<()> {
        let bytes = serde_json::to_vec(value)?;
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(bytes);
        Ok(())
    }
    part(&mut hash, &output.provider)?;
    part(&mut hash, &output.raw)?;
    part(&mut hash, &output.structure)?;
    part(&mut hash, &output.model)?;
    hash.update((output.raw_markdown.len() as u64).to_le_bytes());
    hash.update(output.raw_markdown.as_bytes());
    hash.update((output.assets.len() as u64).to_le_bytes());
    for (name, bytes) in &output.assets {
        tasks::check(token)?;
        hash.update((name.len() as u64).to_le_bytes());
        hash.update(name.as_bytes());
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(bytes);
    }
    if let Some(bytes) = &output.export_zip {
        hash.update([1]);
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(bytes);
    } else {
        hash.update([0]);
    }
    let identity = hash
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    let generation = directory.join("ocr").join(&identity);
    std::fs::create_dir_all(&generation)?;
    files::write_json(
        &generation.join(format!("extract.{}.json", output.provider.key())),
        &output.raw,
    )?;
    files::atomic_write(
        &generation.join("extract.raw.md"),
        output.raw_markdown.as_bytes(),
    )?;
    files::write_json(&generation.join("structure.json"), &output.structure)?;
    files::write_json(&generation.join("document.json"), &output.model)?;
    for (name, bytes) in &output.assets {
        tasks::check(token)?;
        safe_relative(name)?;
        files::atomic_write(&generation.join(name), bytes)?;
    }
    if let Some(zip) = &output.export_zip {
        files::atomic_write(&generation.join("mineru.exports.zip"), zip)?;
    }
    tasks::check(token)?;
    files::write_json(
        &directory.join("ocr-current.json"),
        &json!({"generation":identity,"provider":output.provider}),
    )?;
    Ok(identity)
}
