use super::*;

pub(super) fn validate_segments(value: &str) -> Result<()> {
    if value.contains('\\')
        || value
            .split('/')
            .filter(|s| !s.is_empty())
            .any(|s| files::component(s).is_err())
    {
        return Err(OtterError::new(
            ErrorCode::InvalidArgument,
            "remote directory/key",
        ));
    }
    Ok(())
}
pub(super) fn milliseconds(time: OffsetDateTime) -> i64 {
    (time.unix_timestamp_nanos() / 1_000_000) as i64
}
pub(super) fn child<'a, 'input>(node: roxmltree::Node<'a, 'input>, name: &str) -> Option<&'a str> {
    node.children()
        .find(|n| n.is_element() && n.tag_name().name() == name)
        .and_then(|n| n.text())
}
pub(super) fn xml(bytes: &[u8]) -> Result<roxmltree::Document<'_>> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "remote XML encoding"))?;
    roxmltree::Document::parse(text)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "remote XML"))
}
pub(super) fn decode(value: &str) -> Result<String> {
    let mut bytes = Vec::new();
    let raw = value.as_bytes();
    let mut index = 0;
    while index < raw.len() {
        if raw[index] == b'%' {
            let hex = raw
                .get(index + 1..index + 3)
                .and_then(|v| std::str::from_utf8(v).ok())
                .and_then(|s| u8::from_str_radix(s, 16).ok())
                .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "WebDAV escaped path"))?;
            bytes.push(hex);
            index += 3;
        } else {
            bytes.push(raw[index]);
            index += 1;
        }
    }
    String::from_utf8(bytes)
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "WebDAV filename UTF-8"))
}
