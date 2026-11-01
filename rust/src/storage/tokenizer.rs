//! FTS5 tokenizer registered on each connection, with no loadable C extension.
use std::{
    ffi::{c_char, c_int, c_void},
    panic::{AssertUnwindSafe, catch_unwind},
    ptr, slice, str,
    sync::LazyLock,
};

use jieba_rs::Jieba;
use pinyin::ToPinyinMulti;
use rusqlite::{Connection, ffi};

use crate::error::{ErrorCode, OtterError, Result};

static JIEBA: LazyLock<Jieba> = LazyLock::new(Jieba::new);
// SQLite treats this pointer as opaque; no per-instance state is allocated.
static TOKENIZER_ID: u8 = 0;

pub(super) fn register(connection: &Connection) -> Result<()> {
    let mut api: *mut ffi::fts5_api = ptr::null_mut();
    // SAFETY: the connection is exclusively used during registration. The SQL,
    // pointer-type tag, and output slot live through sqlite3_step; the statement
    // is finalized on every path after successful preparation (SQLite FTS5 API).
    unsafe {
        let mut statement = ptr::null_mut();
        check(ffi::sqlite3_prepare_v2(
            connection.handle(),
            c"SELECT fts5(?1)".as_ptr(),
            -1,
            &mut statement,
            ptr::null_mut(),
        ))?;
        let bound = ffi::sqlite3_bind_pointer(
            statement,
            1,
            ptr::from_mut(&mut api).cast(),
            c"fts5_api_ptr".as_ptr(),
            None,
        );
        let stepped = if bound == ffi::SQLITE_OK {
            ffi::sqlite3_step(statement)
        } else {
            bound
        };
        let finalized = ffi::sqlite3_finalize(statement);
        if stepped != ffi::SQLITE_ROW {
            check(stepped)?;
        }
        check(finalized)?;
        if api.is_null() {
            return Err(OtterError::new(ErrorCode::Database, "FTS5 API unavailable"));
        }
        let create = (*api).xCreateTokenizer.ok_or_else(|| {
            OtterError::new(ErrorCode::Database, "FTS5 tokenizer API unavailable")
        })?;
        let mut tokenizer = ffi::fts5_tokenizer {
            xCreate: Some(create_tokenizer),
            xDelete: Some(delete_tokenizer),
            xTokenize: Some(tokenize),
        };
        // SQLite copies the function-pointer table; callbacks and state are static.
        check(create(
            api,
            c"otter_jieba".as_ptr(),
            ptr::null_mut(),
            &mut tokenizer,
            None,
        ))?;
    }
    Ok(())
}

fn check(code: c_int) -> Result<()> {
    if code == ffi::SQLITE_OK {
        return Ok(());
    }
    Err(rusqlite::Error::SqliteFailure(ffi::Error::new(code), None).into())
}

unsafe extern "C" fn create_tokenizer(
    _context: *mut c_void,
    _arguments: *mut *const c_char,
    count: c_int,
    output: *mut *mut ffi::Fts5Tokenizer,
) -> c_int {
    if count != 0 || output.is_null() {
        return ffi::SQLITE_ERROR;
    }
    // SAFETY: SQLite supplies a writable tokenizer output slot. The static
    // sentinel outlives all connections and is never dereferenced as a tokenizer.
    unsafe {
        *output = ptr::from_ref(&TOKENIZER_ID).cast_mut().cast();
    }
    ffi::SQLITE_OK
}

unsafe extern "C" fn delete_tokenizer(_tokenizer: *mut ffi::Fts5Tokenizer) {}

type Emit = unsafe extern "C" fn(*mut c_void, c_int, *const c_char, c_int, c_int, c_int) -> c_int;

unsafe extern "C" fn tokenize(
    _tokenizer: *mut ffi::Fts5Tokenizer,
    context: *mut c_void,
    flags: c_int,
    text: *const c_char,
    length: c_int,
    emit: Option<Emit>,
) -> c_int {
    if length < 0 {
        return ffi::SQLITE_ERROR;
    }
    if length == 0 {
        return ffi::SQLITE_OK;
    }
    let Some(emit) = emit else {
        return ffi::SQLITE_ERROR;
    };
    if text.is_null() {
        return ffi::SQLITE_ERROR;
    }
    // A Rust panic must never unwind through SQLite's C stack.
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: SQLite owns a readable buffer of exactly length bytes for the
        // duration of this callback. An invalid UTF-8 input is rejected.
        let bytes = unsafe { slice::from_raw_parts(text.cast::<u8>(), length as usize) };
        let Ok(text) = str::from_utf8(bytes) else {
            return ffi::SQLITE_ERROR;
        };
        for token in JIEBA.cut(text, false) {
            if !token.word.chars().any(char::is_alphanumeric) {
                continue;
            }
            let mut terms = vec![(token.word.to_owned(), token.byte_start, token.byte_end)];
            // Index compound-word parts as synonyms at the same position. Query
            // segmentation uses whole words, so compound queries remain selective.
            if flags & ffi::FTS5_TOKENIZE_QUERY == 0 {
                for part in JIEBA.cut_for_search(token.word, false) {
                    if part.word != token.word && part.word.chars().any(char::is_alphanumeric) {
                        terms.push((
                            part.word.to_owned(),
                            token.byte_start + part.byte_start,
                            token.byte_start + part.byte_end,
                        ));
                    }
                }
                // Index complete Chinese runs as well as Jieba words. This lets
                // an unspaced pinyin query cross a segmentation boundary.
                let mut run_end = token.byte_start;
                if text[..token.byte_start]
                    .chars()
                    .next_back()
                    .is_none_or(|ch| ch.to_pinyin_multi().is_none())
                {
                    for ch in text[token.byte_start..].chars() {
                        if ch.to_pinyin_multi().is_none() {
                            break;
                        }
                        run_end += ch.len_utf8();
                    }
                }
                let words = terms.clone();
                for (word, start, end) in words {
                    for spelling in spellings(&word) {
                        terms.push((spelling, start, end));
                    }
                }
                if run_end > token.byte_end {
                    for spelling in spellings(&text[token.byte_start..run_end]) {
                        terms.push((spelling, token.byte_start, run_end));
                    }
                }
            }
            for (index, (word, start, end)) in terms.into_iter().enumerate() {
                let normalized = word.to_lowercase();
                let Ok(size) = c_int::try_from(normalized.len()) else {
                    return ffi::SQLITE_TOOBIG;
                };
                // SAFETY: all byte offsets refer to SQLite's original buffer;
                // normalized is alive until emit returns, and SQLite copies it.
                let result = unsafe {
                    emit(
                        context,
                        if index == 0 {
                            0
                        } else {
                            ffi::FTS5_TOKEN_COLOCATED
                        },
                        normalized.as_ptr().cast(),
                        size,
                        start as c_int,
                        end as c_int,
                    )
                };
                if result != ffi::SQLITE_OK {
                    return result;
                }
            }
        }
        ffi::SQLITE_OK
    }))
    .unwrap_or(ffi::SQLITE_ERROR)
}

pub(super) fn match_expression(query: &str) -> String {
    JIEBA
        .cut(query, false)
        .into_iter()
        .filter(|token| token.word.chars().any(char::is_alphanumeric))
        .map(|token| {
            let prefix =
                if token.word.len() >= 2 && token.word.bytes().all(|b| b.is_ascii_alphabetic()) {
                    "*"
                } else {
                    ""
                };
            format!("\"{}\"{prefix}", token.word.replace('"', "\"\""))
        })
        .collect::<Vec<_>>()
        .join(" AND ")
}

fn spellings(word: &str) -> Vec<String> {
    let mut variants = vec![(String::new(), String::new())];
    for ch in word.chars() {
        let Some(readings) = ch.to_pinyin_multi() else {
            return Vec::new();
        };
        let mut next = Vec::new();
        for (full, initials) in &variants {
            for reading in readings {
                next.push((
                    format!("{full}{}", reading.plain()),
                    format!("{initials}{}", reading.first_letter()),
                ));
                if next.len() == 64 {
                    break;
                }
            }
            if next.len() == 64 {
                break;
            }
        }
        variants = next;
    }
    let mut terms: Vec<_> = variants
        .into_iter()
        .flat_map(|(full, initials)| [full, initials])
        .filter(|s| !s.is_empty())
        .collect();
    terms.sort();
    terms.dedup();
    terms
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sqlite_highlight_uses_utf8_byte_offsets_and_invalid_input_rolls_back() {
        let connection = Connection::open_in_memory().unwrap();
        register(&connection).unwrap();
        connection
            .execute_batch(
                "CREATE VIRTUAL TABLE text_index USING fts5(body, tokenize='otter_jieba');
             INSERT INTO text_index VALUES ('🦦自然语言，RUST研究');",
            )
            .unwrap();
        let highlighted: String = connection.query_row(
            "SELECT highlight(text_index,0,'[',']') FROM text_index WHERE text_index MATCH 'rust'",
            [], |row| row.get(0)
        ).unwrap();
        assert_eq!(highlighted, "🦦自然语言，[RUST]研究");
        assert!(
            connection
                .execute("INSERT INTO text_index VALUES (CAST(x'ff' AS TEXT))", [])
                .is_err()
        );
        let count: i64 = connection
            .query_row("SELECT count(*) FROM text_index", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
        connection
            .execute(
                "INSERT INTO text_index(text_index) VALUES ('integrity-check')",
                [],
            )
            .unwrap();
    }
}
