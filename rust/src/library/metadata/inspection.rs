use super::*;

pub struct LocalInspection {
    pub document: crate::storage::Document,
    pub identifier: Option<Identifier>,
    pub warnings: Vec<crate::error::ErrorCode>,
}
pub fn inspect_local(
    pdf: &mut crate::pdf::PdfService,
    path: &std::path::Path,
    directory: &std::path::Path,
    original: &crate::storage::Document,
    token: &tokio_util::sync::CancellationToken,
) -> crate::error::Result<LocalInspection> {
    use crate::{error::ErrorCode, tasks::check};
    check(token)?;
    let info = pdf.open(path, None, token)?;
    let result = (|| {
        let mut warnings = Vec::new();
        // The managed file name is an implementation detail, never a title.
        let filename = if path.file_name().is_some_and(|name| name == "source.pdf") {
            parse_text(&original.title)
        } else {
            parse_filename(&path.to_string_lossy())
        };
        let mut combined = filename.merge(from_properties(&pdf.metadata(info.handle)?));
        match xmp_from_pdf(path, token) {
            Ok(xmp) => combined = combined.merge(xmp),
            Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
            Err(error) => warnings.push(error.code),
        }
        let mut document = original.clone();
        combined.apply(&mut document);
        let split = parse_text(&document.title);
        if let Some(title) = split.title
            && !split.authors.is_empty()
        {
            document.title = title;
            if document.authors.is_empty() {
                document.authors = split.authors;
            }
        }
        let structure = crate::document::extraction_directory(directory)?.join("structure.json");
        if structure.is_file() {
            match std::fs::read(structure)
                .map_err(crate::error::OtterError::from)
                .and_then(|bytes| {
                    serde_json::from_slice::<crate::document::structure::Structure>(&bytes)
                        .map_err(Into::into)
                }) {
                Ok(structure) => {
                    if let Some(page) = structure.pages.first() {
                        combined = combined.merge(from_first_page(&page.blocks));
                        combined.apply(&mut document);
                    }
                }
                Err(error) => warnings.push(error.code),
            }
        }
        let mut text = String::new();
        for page in info.pages.iter().take(2) {
            match pdf.characters(info.handle, page.index, token) {
                Ok(characters) => {
                    text.extend(characters.into_iter().map(|c| c.text));
                    text.push(' ');
                }
                Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                Err(error) => warnings.push(error.code),
            }
        }
        if is_chinese(&document.title) || is_chinese(&text) {
            combined = combined.merge(from_chinese_text(&text, Some(&document.title)));
            combined.apply(&mut document);
        }
        let identifier = combined
            .doi
            .as_deref()
            .map(identifier::parse)
            .or_else(|| identifier_from_text(&text));
        check(token)?;
        Ok(LocalInspection {
            document,
            identifier,
            warnings,
        })
    })();
    pdf.close(info.handle)?;
    result
}
pub fn complete(document: &crate::storage::Document) -> bool {
    plausible_title(&document.title)
        && normalize(&document.title).to_lowercase() != normalize(&document.id).to_lowercase()
        && !document.authors.is_empty()
        && clean(document.year.as_deref()).is_some()
        && (clean(document.journal.as_deref()).is_some()
            || clean(document.doi.as_deref()).is_some())
}
pub fn needs_repair(document: &crate::storage::Document) -> bool {
    document.content_hash.is_some()
        && (!complete(document)
            || {
                let split = parse_text(&document.title);
                split.title.is_some() && !split.authors.is_empty()
            }
            || document.authors.iter().any(|name| non_person_name(name)))
}
pub fn same_core(a: &crate::storage::Document, b: &crate::storage::Document) -> bool {
    clean(Some(&a.title)) == clean(Some(&b.title))
        && a.authors
            .iter()
            .map(|s| clean(Some(s)))
            .eq(b.authors.iter().map(|s| clean(Some(s))))
        && clean(a.journal.as_deref()) == clean(b.journal.as_deref())
        && clean(a.year.as_deref()) == clean(b.year.as_deref())
        && clean(a.doi.as_deref()) == clean(b.doi.as_deref())
}

pub(super) fn normalized(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}
pub fn duplicate(a: &crate::storage::Document, b: &crate::storage::Document) -> bool {
    if let (Some(a), Some(b)) = (
        a.doi.as_deref().filter(|s| !s.trim().is_empty()),
        b.doi.as_deref().filter(|s| !s.trim().is_empty()),
    ) {
        return a.eq_ignore_ascii_case(b);
    }
    if normalized(&a.title).is_empty() || normalized(&a.title) != normalized(&b.title) {
        return false;
    }
    let year = a
        .year
        .as_deref()
        .filter(|s| !s.trim().is_empty())
        .is_some_and(|a| {
            b.year
                .as_deref()
                .is_some_and(|b| normalized(a) == normalized(b))
        });
    let author = a
        .authors
        .first()
        .filter(|s| !s.trim().is_empty())
        .is_some_and(|a| {
            b.authors
                .first()
                .is_some_and(|b| normalized(a) == normalized(b))
        });
    year || author
}
