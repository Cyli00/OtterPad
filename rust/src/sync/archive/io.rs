use super::*;

pub(crate) fn safe_relative(value: &str) -> Result<()> {
    if value.is_empty()
        || value.contains(['\\', ':'])
        || value.starts_with('/')
        || value.split('/').any(|part| files::component(part).is_err())
    {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "unsafe backup path",
        ));
    }
    Ok(())
}

pub(crate) fn checksums(
    root: &Path,
    scope: Option<BackupScope>,
    token: &CancellationToken,
) -> Result<BTreeMap<String, String>> {
    let mut result = BTreeMap::new();
    fn walk(
        root: &Path,
        directory: &Path,
        scope: Option<BackupScope>,
        token: &CancellationToken,
        result: &mut BTreeMap<String, String>,
    ) -> Result<()> {
        for entry in fs::read_dir(directory)? {
            check(token)?;
            let entry = entry?;
            let ty = entry.file_type()?;
            if ty.is_symlink() {
                return Err(OtterError::new(
                    ErrorCode::InvalidData,
                    "linked library file",
                ));
            }
            let path = entry.path();
            let relative = path
                .strip_prefix(root)
                .unwrap()
                .components()
                .map(|s| {
                    s.as_os_str().to_str().ok_or_else(|| {
                        OtterError::new(ErrorCode::InvalidData, "library filename UTF-8")
                    })
                })
                .collect::<Result<Vec<_>>>()?
                .join("/");
            safe_relative(&relative)?;
            if scope.is_some_and(|scope| !include(&relative, scope)) {
                continue;
            }
            if ty.is_dir() {
                walk(root, &path, scope, token, result)?;
            } else if ty.is_file() {
                result.insert(relative, hash_file(&path, token)?);
            }
        }
        Ok(())
    }
    if root.is_dir() {
        walk(root, root, scope, token, &mut result)?;
    }
    Ok(result)
}

pub(crate) fn hash_file(path: &Path, token: &CancellationToken) -> Result<String> {
    let mut file = File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0; 64 * 1024];
    loop {
        check(token)?;
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
    }
    Ok(hash.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

pub(crate) fn copy_stream(
    source: &mut impl Read,
    target: &mut impl Write,
    token: &CancellationToken,
) -> Result<()> {
    let mut buffer = [0; 64 * 1024];
    loop {
        check(token)?;
        let count = source.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        target.write_all(&buffer[..count])?;
    }
    Ok(())
}

pub(crate) fn atomic_copy(source: &Path, target: &Path, token: &CancellationToken) -> Result<()> {
    let parent = target
        .parent()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "copy target parent"))?;
    let stage = Stage::new(parent, "copy")?;
    let path = stage.path.join("data");
    let mut output = File::create(&path)?;
    copy_stream(&mut File::open(source)?, &mut output, token)?;
    output.sync_all()?;
    drop(output);
    check(token)?;
    fs::rename(path, target)?;
    #[cfg(unix)]
    File::open(parent)?.sync_all()?;
    Ok(())
}

pub(super) fn zip_error(_: zip::result::ZipError) -> OtterError {
    OtterError::new(ErrorCode::InvalidData, "backup ZIP")
}
