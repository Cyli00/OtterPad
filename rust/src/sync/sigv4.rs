use std::collections::BTreeMap;

use hmac::{Hmac, KeyInit, Mac};
use reqwest::{
    Method, Url,
    header::{HeaderMap, HeaderName, HeaderValue},
};
use sha2::{Digest, Sha256};
use time::OffsetDateTime;

use crate::error::{ErrorCode, OtterError, Result};

pub fn hash(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn encode(text: &str, slash: bool) -> String {
    let mut out = String::new();
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || b"-_.~".contains(&byte) || (slash && byte == b'/') {
            out.push(byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

fn hmac(key: &[u8], data: &str) -> Vec<u8> {
    let mut mac = Hmac::<Sha256>::new_from_slice(key).expect("HMAC accepts every key length");
    mac.update(data.as_bytes());
    mac.finalize().into_bytes().to_vec()
}

/// Signing credentials never enter a serializable configuration or an error detail.
pub struct Credentials {
    pub access_key: String,
    pub secret_key: String,
}

#[allow(clippy::too_many_arguments)]
pub fn sign(
    method: &Method,
    url: &Url,
    canonical_path: &str,
    query: &[(String, String)],
    payload_hash: &str,
    region: &str,
    credentials: &Credentials,
    time: OffsetDateTime,
    extra: &BTreeMap<String, String>,
) -> Result<HeaderMap> {
    let date = format!(
        "{:04}{:02}{:02}",
        time.year(),
        u8::from(time.month()),
        time.day()
    );
    let amz_date = format!(
        "{date}T{:02}{:02}{:02}Z",
        time.hour(),
        time.minute(),
        time.second()
    );
    let host = url
        .host_str()
        .ok_or_else(|| OtterError::new(ErrorCode::InvalidArgument, "S3 host"))?;
    let host = match url.port() {
        Some(port) => format!("{host}:{port}"),
        None => host.into(),
    };
    let mut headers = BTreeMap::from([
        ("host".to_owned(), host),
        ("x-amz-content-sha256".into(), payload_hash.into()),
        ("x-amz-date".into(), amz_date.clone()),
    ]);
    for (name, value) in extra {
        headers.insert(
            name.to_ascii_lowercase(),
            value.split_whitespace().collect::<Vec<_>>().join(" "),
        );
    }
    let signed = headers.keys().cloned().collect::<Vec<_>>().join(";");
    let canonical_headers = headers
        .iter()
        .map(|(name, value)| format!("{name}:{value}\n"))
        .collect::<String>();
    let mut query: Vec<_> = query
        .iter()
        .map(|(name, value)| (encode(name, false), encode(value, false)))
        .collect();
    query.sort();
    let query = query
        .iter()
        .map(|(name, value)| format!("{name}={value}"))
        .collect::<Vec<_>>()
        .join("&");
    let canonical = format!(
        "{}\n{canonical_path}\n{query}\n{canonical_headers}\n{signed}\n{payload_hash}",
        method.as_str()
    );
    let scope = format!("{date}/{region}/s3/aws4_request");
    let to_sign = format!(
        "AWS4-HMAC-SHA256\n{amz_date}\n{scope}\n{}",
        hash(canonical.as_bytes())
    );
    let date_key = hmac(format!("AWS4{}", credentials.secret_key).as_bytes(), &date);
    let region_key = hmac(&date_key, region);
    let service_key = hmac(&region_key, "s3");
    let signing_key = hmac(&service_key, "aws4_request");
    let signature = hex(&hmac(&signing_key, &to_sign));
    headers.insert(
        "authorization".into(),
        format!(
            "AWS4-HMAC-SHA256 Credential={}/{scope}, SignedHeaders={signed}, Signature={signature}",
            credentials.access_key
        ),
    );
    let mut result = HeaderMap::new();
    for (name, value) in headers {
        let name = HeaderName::from_bytes(name.as_bytes())
            .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "S3 header name"))?;
        let mut value = HeaderValue::from_str(&value)
            .map_err(|_| OtterError::new(ErrorCode::InvalidArgument, "S3 header value"))?;
        if name == "authorization" {
            value.set_sensitive(true);
        }
        result.insert(name, value);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn aws_published_get_object_signature_matches_exactly() {
        // Public AWS documentation vector, not account credentials:
        // https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sig-v4-header-based-auth.html
        let credentials = Credentials {
            access_key: ["AKIAIOSFODNN7", "EXAMPLE"].concat(),
            secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY".into(),
        };
        let time = OffsetDateTime::from_unix_timestamp(1369353600).unwrap();
        let headers = sign(
            &Method::GET,
            &Url::parse("https://examplebucket.s3.amazonaws.com/test.txt").unwrap(),
            "/test.txt",
            &[],
            &hash(b""),
            "us-east-1",
            &credentials,
            time,
            &BTreeMap::from([("range".into(), "bytes=0-9".into())]),
        )
        .unwrap();
        assert!(headers["authorization"].to_str().unwrap().ends_with(
            "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
        ));
    }
}
