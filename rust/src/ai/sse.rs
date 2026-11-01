use crate::error::{ErrorCode, OtterError, Result};

#[derive(Debug)]
pub(crate) struct SseEvent {
    pub event: String,
    pub data: String,
}

/// Decode lines before UTF-8 so a network chunk may split either a scalar or CRLF.
#[derive(Default)]
pub(crate) struct Decoder {
    line: Vec<u8>,
    data: String,
    event: String,
    after_cr: bool,
    started: bool,
    event_bytes: usize,
}

impl Decoder {
    const LIMIT: usize = 1024 * 1024;

    pub fn push(&mut self, bytes: &[u8]) -> Result<Vec<SseEvent>> {
        let mut out = Vec::new();
        for byte in bytes {
            if self.after_cr {
                self.after_cr = false;
                if *byte == b'\n' {
                    continue;
                }
            }
            if matches!(byte, b'\r' | b'\n') {
                self.end_line(&mut out)?;
                self.after_cr = *byte == b'\r';
            } else {
                self.line.push(*byte);
                if self.line.len() + self.event_bytes > Self::LIMIT {
                    return Err(OtterError::new(
                        ErrorCode::InvalidData,
                        "SSE event exceeds limit",
                    ));
                }
            }
        }
        Ok(out)
    }

    fn end_line(&mut self, out: &mut Vec<SseEvent>) -> Result<()> {
        let bytes = std::mem::take(&mut self.line);
        let mut line = std::str::from_utf8(&bytes)
            .map_err(|_| OtterError::new(ErrorCode::InvalidData, "SSE UTF-8"))?;
        if !self.started {
            self.started = true;
            line = line.trim_start_matches('\u{feff}');
        }
        if line.is_empty() {
            if !self.data.is_empty() {
                self.data.pop();
                out.push(SseEvent {
                    event: std::mem::take(&mut self.event),
                    data: std::mem::take(&mut self.data),
                });
            }
            self.event.clear();
            self.event_bytes = 0;
        } else if !line.starts_with(':') {
            let (field, value) = line.split_once(':').unwrap_or((line, ""));
            let value = value.strip_prefix(' ').unwrap_or(value);
            match field {
                "event" => self.event = value.into(),
                "data" => {
                    self.data.push_str(value);
                    self.data.push('\n');
                }
                _ => {}
            }
            self.event_bytes += line.len();
        }
        Ok(())
    }

    pub fn finish(&self) -> Result<()> {
        // An unterminated event must never turn a truncated transport into success.
        if !self.line.is_empty() || !self.data.is_empty() {
            return Err(OtterError::new(
                ErrorCode::IncompleteResponse,
                "unterminated SSE event",
            ));
        }
        Ok(())
    }
}
