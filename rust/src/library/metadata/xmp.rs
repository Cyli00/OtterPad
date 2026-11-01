use super::*;

pub fn xmp_from_pdf(
    path: &std::path::Path,
    token: &tokio_util::sync::CancellationToken,
) -> crate::error::Result<Metadata> {
    use crate::error::{ErrorCode, OtterError};
    use std::io::Read;
    const START: &[u8] = b"<x:xmpmeta";
    const END: &[u8] = b"</x:xmpmeta>";
    let mut file = std::fs::File::open(path)?;
    let mut buffer = [0; 64 * 1024];
    let mut packet = Vec::new();
    let mut found = false;
    loop {
        crate::tasks::check(token)?;
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        packet.extend_from_slice(&buffer[..count]);
        if !found {
            if let Some(start) = packet
                .windows(START.len())
                .position(|w| w.eq_ignore_ascii_case(START))
            {
                packet.drain(..start);
                found = true;
            } else {
                let keep = packet.len().saturating_sub(START.len() - 1);
                packet.drain(..keep);
                continue;
            }
        }
        if let Some(end) = packet
            .windows(END.len())
            .position(|w| w.eq_ignore_ascii_case(END))
        {
            packet.truncate(end + END.len());
            return Ok(from_xmp(&String::from_utf8_lossy(&packet)));
        }
        if packet.len() > 16 * 1024 * 1024 {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "PDF XMP size limit",
            ));
        }
    }
    Ok(Metadata::default())
}
pub fn from_xmp(xml: &str) -> Metadata {
    let Ok(document) = roxmltree::Document::parse(xml) else {
        return Metadata {
            year: extract_year(xml),
            doi: extract_doi(xml),
            ..Default::default()
        };
    };
    let first = |name: &str| {
        document
            .descendants()
            .find(|n| n.is_element() && n.tag_name().name() == name)
    };
    let text = |name: &str| first(name).and_then(|n| clean(Some(&xml_text(n))));
    let list = |name: &str| {
        first(name)
            .into_iter()
            .flat_map(|n| n.descendants())
            .filter(|n| n.is_element() && n.tag_name().name() == "li")
            .filter_map(|n| clean(Some(&xml_text(n))))
            .collect::<Vec<_>>()
    };
    let title = list("title")
        .into_iter()
        .next()
        .filter(|s| plausible_title(s));
    let parsed = title.as_deref().map(parse_text).unwrap_or_default();
    let journal = text("publicationName")
        .or_else(|| text("source"))
        .filter(|s| extract_doi(s).is_none());
    let year = text("publicationDate")
        .or_else(|| text("coverDate"))
        .or_else(|| text("date"))
        .as_deref()
        .and_then(extract_year);
    let doi = text("doi")
        .or_else(|| text("identifier"))
        .as_deref()
        .and_then(extract_doi);
    Metadata {
        title,
        ..Default::default()
    }
    .merge(parsed)
    .merge(Metadata {
        authors: list("creator"),
        journal,
        year,
        doi,
        ..Default::default()
    })
}
pub(super) fn xml_text(node: roxmltree::Node<'_, '_>) -> String {
    node.descendants()
        .filter(|n| n.is_text())
        .filter_map(|n| n.text())
        .collect()
}
