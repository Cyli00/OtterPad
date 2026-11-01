use regex::Regex;
use std::sync::LazyLock;

use crate::error::{ErrorCode, OtterError, Result};

pub struct Protected {
    pub masked: String,
    spans: Vec<String>,
}

static PLACEHOLDER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\[\[\s*m(\d+)\s*\]\]").unwrap());

impl Protected {
    pub fn mask(text: &str) -> Self {
        // Code and backslash-delimited math take precedence over dollar delimiters.
        let expression = Regex::new(r"\[\[\s*m\d+\s*\]\]|`[^`\n⟪⟫]+`|\\\((?:[^\\⟪⟫]|\\[^)⟪⟫])+?\\\)|\\\[(?:[^\\⟪⟫]|\\[^\]⟪⟫])+?\\\]|\$[^$\n⟪⟫]*\$").unwrap();
        let mut spans = Vec::new();
        let mut masked = String::new();
        let mut cursor = 0;
        let mut scan = 0;
        while let Some(matched) = expression.find_at(text, scan) {
            scan = matched.end();
            let value = matched.as_str();
            if value.starts_with('$') {
                let inner = &value[1..value.len() - 1];
                if inner.starts_with(char::is_whitespace)
                    || inner.ends_with(char::is_whitespace)
                    || text[matched.end()..].starts_with(|c: char| c.is_ascii_digit())
                {
                    scan = matched.start() + 1;
                    continue;
                }
            }
            masked.push_str(&text[cursor..matched.start()]);
            masked.push_str(&format!("[[m{}]]", spans.len()));
            spans.push(value.into());
            cursor = matched.end();
        }
        masked.push_str(&text[cursor..]);
        Self { masked, spans }
    }

    pub fn is_empty(&self) -> bool {
        self.spans.is_empty()
    }

    pub fn restore(&self, text: &str, complete: bool) -> Result<String> {
        let mut counts = vec![0; self.spans.len()];
        let mut unknown = false;
        let result = PLACEHOLDER
            .replace_all(text, |captures: &regex::Captures<'_>| {
                if let Ok(index) = captures[1].parse::<usize>()
                    && let Some(span) = self.spans.get(index)
                {
                    counts[index] += 1;
                    span.clone()
                } else {
                    unknown = true;
                    captures[0].into()
                }
            })
            .into_owned();
        if complete && (unknown || counts.iter().any(|n| *n != 1)) {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "translation protected span changed",
            ));
        }
        Ok(result)
    }
}
