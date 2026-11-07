//! 长 PDF 的页段拆分与合并。
//!
//! PaddleOCR 单任务最多 1000 页，MinerU 精准解析单文件最多 200 页。更长的
//! PDF 按页段提交，每段结果的页号都从 0 重新开始、图片也可能同名；按页号或
//! 文件名覆盖会让后一段盖掉前一段（720 页时只剩第 601 页以后）。这里按页段
//! 顺序拼接，并给冲突的图片改名。
use super::*;

pub const PADDLE_MAX_PAGES: usize = 1000;
pub const MINERU_MAX_PAGES: usize = 200;

/// 一个请求覆盖的页段（1-based，含首尾）。`whole` 时不传页段参数。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PageChunk {
    pub index: usize,
    pub start: usize,
    pub end: usize,
    pub whole: bool,
}

impl PageChunk {
    /// 请求参数里的页段，例如 `201-400`；整份文件时为 `None`。
    pub fn ranges(&self) -> Option<String> {
        (!self.whole).then(|| format!("{}-{}", self.start, self.end))
    }

    fn pages(&self) -> usize {
        if self.start > 0 && self.end >= self.start {
            self.end - self.start + 1
        } else {
            0
        }
    }
}

/// 页数未知、为 0 或不超过 `max` 时返回一个整份文件的页段。
pub fn plan(page_count: Option<usize>, max: usize) -> Vec<PageChunk> {
    let max = max.max(1);
    match page_count {
        Some(count) if count > max => (0..count.div_ceil(max))
            .map(|index| PageChunk {
                index,
                start: index * max + 1,
                end: ((index + 1) * max).min(count),
                whole: false,
            })
            .collect(),
        count => {
            let known = count.filter(|c| *c > 0);
            vec![PageChunk {
                index: 0,
                start: usize::from(known.is_some()),
                end: known.unwrap_or(0),
                whole: true,
            }]
        }
    }
}

/// 按列表顺序重写 Paddle 页的 `page_index`，并给与前面页面同名但 URL 不同的
/// 图片改名为 `p{页序}_{原名}`，同步改写该页 Markdown 的引用。
pub fn assemble_paddle_pages(pages: &mut [Value]) {
    let mut seen: BTreeMap<String, String> = BTreeMap::new();
    for (i, page) in pages.iter_mut().enumerate() {
        if !page.is_object() {
            continue;
        }
        page["page_index"] = json!(i);
        let Some(images) = page["markdown"]["images"].as_object().cloned() else {
            continue;
        };
        let mut text = page["markdown"]["text"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        let mut next = serde_json::Map::new();
        for (key, value) in images {
            let url = value
                .as_str()
                .map(str::to_owned)
                .unwrap_or_else(|| value.to_string());
            let mut key = key;
            if seen.get(&key).is_some_and(|known| *known != url) {
                let renamed = format!("p{i}_{key}");
                text = text.replace(&key, &renamed);
                key = renamed;
            }
            seen.insert(key.clone(), url.clone());
            next.insert(key, json!(url));
        }
        page["markdown"]["images"] = Value::Object(next);
        if page["markdown"]["text"].is_string() {
            page["markdown"]["text"] = json!(text);
        }
    }
}

/// 读出 ZIP 的全部文件条目，拒绝路径穿越、符号链接、重名与解压炸弹。
pub(super) fn read_zip(bytes: &[u8]) -> Result<Vec<(String, Vec<u8>)>> {
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes))
        .map_err(|_| OtterError::new(ErrorCode::InvalidData, "invalid MinerU ZIP"))?;
    if archive.len() > 100_000 {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "OCR ZIP entry limit",
        ));
    }
    let mut names = std::collections::HashSet::new();
    let mut total = 0u64;
    let mut entries = Vec::new();
    for index in 0..archive.len() {
        let file = archive
            .by_index(index)
            .map_err(|_| OtterError::new(ErrorCode::InvalidData, "invalid ZIP entry"))?;
        let name = file
            .name()
            .map_err(|_| OtterError::new(ErrorCode::InvalidData, "invalid ZIP name"))?
            .into_owned();
        safe_relative(name.trim_end_matches('/'))?;
        if !names.insert(name.to_lowercase()) {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "duplicate OCR ZIP entry",
            ));
        }
        if file.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000) {
            return Err(OtterError::new(ErrorCode::InvalidData, "ZIP symlink"));
        }
        total = total
            .checked_add(file.size())
            .filter(|t| *t <= 1024 * 1024 * 1024)
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "OCR ZIP too large"))?;
        if file.is_dir() {
            continue;
        }
        let mut content = Vec::new();
        let declared = file.size();
        file.take(declared + 1).read_to_end(&mut content)?;
        if content.len() as u64 != declared {
            return Err(OtterError::new(
                ErrorCode::InvalidData,
                "OCR ZIP entry size mismatch",
            ));
        }
        entries.push((name, content));
    }
    Ok(entries)
}

struct ChunkBody {
    chunk: PageChunk,
    markdown: String,
    layout: Option<Value>,
    v2: Option<Vec<Value>>,
    images: Vec<(String, Vec<u8>)>,
}

fn chunk_body(chunk: PageChunk, bytes: &[u8]) -> Result<ChunkBody> {
    let entries = read_zip(bytes)?;
    let label = chunk.ranges().unwrap_or_else(|| "all".into());
    let missing = |what: &str| {
        OtterError::new(
            ErrorCode::InvalidData,
            format!("MinerU range {label} missing {what}"),
        )
    };
    // 结果可能套一层目录；以最短路径的 full.md 所在目录为根。
    let root = entries
        .iter()
        .map(|(name, _)| name)
        .filter(|name| name.rsplit('/').next() == Some("full.md"))
        .min_by_key(|name| name.len())
        .map(|name| name[..name.len() - "full.md".len()].to_owned())
        .ok_or_else(|| missing("full.md"))?;
    let (mut markdown, mut layout, mut middle, mut v2) = (None, None, None, None);
    let mut images = Vec::new();
    for (name, content) in entries {
        let Some(rel) = name.strip_prefix(&root) else {
            continue;
        };
        let top_level = !rel.contains('/');
        if rel == "full.md" {
            markdown = Some(String::from_utf8(content).map_err(|_| {
                OtterError::new(ErrorCode::InvalidData, "invalid OCR Markdown UTF-8")
            })?);
        } else if rel == "layout.json" {
            layout = Some(serde_json::from_slice::<Value>(&content)?);
        } else if top_level && rel.ends_with("_middle.json") {
            middle = Some(serde_json::from_slice::<Value>(&content)?);
        } else if top_level && rel.ends_with("_content_list_v2.json") {
            v2 = serde_json::from_slice::<Value>(&content)?
                .as_array()
                .cloned();
        } else if rel.starts_with("images/") {
            images.push((rel.to_owned(), content));
        }
    }
    let layout = layout.or(middle).filter(|v| v["pdf_info"].is_array());
    if layout.is_none() && v2.is_none() {
        return Err(missing("structure"));
    }
    Ok(ChunkBody {
        chunk,
        markdown: markdown.ok_or_else(|| missing("full.md"))?,
        layout,
        v2,
        images,
    })
}

/// 把 MinerU 各页段的结果包按页段顺序合并为一个结果包。
///
/// 任一页段缺 Markdown 或结构化结果都报错，不把已成功的页段当成整篇文档。
pub fn merge_mineru_zips(mut parts: Vec<(PageChunk, Vec<u8>)>) -> Result<Vec<u8>> {
    if parts.is_empty() {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "no MinerU ranges to merge",
        ));
    }
    parts.sort_by_key(|(chunk, _)| chunk.index);
    if parts.windows(2).any(|w| w[0].0.index == w[1].0.index) {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "duplicate MinerU range",
        ));
    }
    let bodies = parts
        .iter()
        .map(|(chunk, bytes)| chunk_body(*chunk, bytes))
        .collect::<Result<Vec<_>>>()?;
    let some_layout = bodies.iter().any(|b| b.layout.is_some());
    if some_layout && !bodies.iter().all(|b| b.layout.is_some()) {
        return Err(OtterError::new(
            ErrorCode::InvalidData,
            "MinerU range missing layout",
        ));
    }
    let every_v2 = bodies.iter().all(|b| b.v2.is_some());

    let mut stored: BTreeMap<String, Vec<u8>> = BTreeMap::new();
    let mut markdown = String::new();
    let mut shell: Option<Value> = None;
    let mut layout_pages = Vec::new();
    let mut v2_pages = Vec::new();
    for body in bodies {
        let renames = store_images(&mut stored, body.images, body.chunk.index);
        let section = apply_renames(&body.markdown, &renames);
        if !markdown.is_empty() {
            markdown.push_str("\n\n");
        }
        markdown.push_str(section.trim_end());
        if let Some(layout) = body.layout {
            let pages = layout["pdf_info"].as_array().cloned().unwrap_or_default();
            if shell.is_none() {
                shell = Some(layout);
            }
            let global_start = if body.chunk.start > 0 {
                body.chunk.start - 1
            } else {
                layout_pages.len()
            };
            let span = match body.chunk.pages() {
                0 => pages.len(),
                n => n,
            };
            for (local, raw) in pages.into_iter().enumerate() {
                if !raw.is_object() {
                    continue;
                }
                let declared = raw["page_idx"].as_u64().map(|v| v as usize);
                let mut page = rewrite_json(raw, &renames);
                // 第一段的 page_idx 与全局页码重合；后面的段若也从 0 起，
                // 要加上该段在原文中的起点。
                page["page_idx"] = json!(match declared {
                    Some(d) if d >= global_start && d < global_start + span => d,
                    _ => global_start + local,
                });
                layout_pages.push(page);
            }
        }
        if every_v2 {
            v2_pages.extend(
                body.v2
                    .unwrap_or_default()
                    .into_iter()
                    .map(|p| rewrite_json(p, &renames)),
            );
        }
    }

    let mut writer = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let mut add = |name: &str, bytes: &[u8]| -> Result<()> {
        use std::io::Write;
        writer
            .start_file(name, zip::write::SimpleFileOptions::default())
            .and_then(|_| Ok(writer.write_all(bytes)?))
            .map_err(|_| OtterError::new(ErrorCode::Io, "write merged MinerU ZIP"))
    };
    add("full.md", markdown.as_bytes())?;
    if let Some(mut shell) = shell {
        shell["pdf_info"] = Value::Array(layout_pages);
        add("layout.json", &serde_json::to_vec(&shell)?)?;
    }
    if every_v2 {
        add(
            "merged_content_list_v2.json",
            &serde_json::to_vec(&v2_pages)?,
        )?;
    }
    for (name, bytes) in &stored {
        add(name, bytes)?;
    }
    Ok(writer
        .finish()
        .map_err(|_| OtterError::new(ErrorCode::Io, "finish merged MinerU ZIP"))?
        .into_inner())
}

/// 同名同内容的图片只存一份；同名不同内容的改名为 `images/c{页段}_{原名}`。
/// 返回需要改写的引用，既有 `images/x.jpg` 形式，也有 layout 里的裸文件名。
fn store_images(
    stored: &mut BTreeMap<String, Vec<u8>>,
    images: Vec<(String, Vec<u8>)>,
    chunk: usize,
) -> BTreeMap<String, String> {
    let mut renames = BTreeMap::new();
    for (path, bytes) in images {
        match stored.get(&path) {
            None => {
                stored.insert(path, bytes);
                continue;
            }
            Some(existing) if *existing == bytes => continue,
            Some(_) => {}
        }
        let base = path.rsplit('/').next().unwrap_or(&path).to_owned();
        let mut renamed = format!("images/c{chunk}_{base}");
        let mut n = 2;
        while stored.get(&renamed).is_some_and(|b| *b != bytes) {
            renamed = format!("images/c{chunk}_{n}_{base}");
            n += 1;
        }
        let renamed_base = renamed["images/".len()..].to_owned();
        stored.insert(renamed.clone(), bytes);
        renames.insert(path, renamed);
        renames.insert(base, renamed_base);
    }
    renames
}

fn apply_renames(input: &str, renames: &BTreeMap<String, String>) -> String {
    // 只改带 `images/` 前缀的完整路径，避免裸文件名误伤正文。
    let mut keys: Vec<_> = renames
        .keys()
        .filter(|k| k.starts_with("images/"))
        .collect();
    keys.sort_by_key(|k| std::cmp::Reverse(k.len()));
    let mut out = input.to_owned();
    for key in keys {
        out = out.replace(key.as_str(), &renames[key]);
    }
    out
}

fn rewrite_json(node: Value, renames: &BTreeMap<String, String>) -> Value {
    if renames.is_empty() {
        return node;
    }
    match node {
        Value::String(s) => Value::String(renames.get(&s).cloned().unwrap_or(s)),
        Value::Array(items) => Value::Array(
            items
                .into_iter()
                .map(|item| rewrite_json(item, renames))
                .collect(),
        ),
        Value::Object(map) => Value::Object(
            map.into_iter()
                .map(|(k, v)| (k, rewrite_json(v, renames)))
                .collect(),
        ),
        other => other,
    }
}

/// MinerU `data_id` 只允许 `[A-Za-z0-9_.-]`，最长 128。
pub fn data_id(document: &str, chunk: &PageChunk, chunks: usize) -> String {
    let raw = if chunks == 1 {
        document.to_owned()
    } else {
        format!("{document}_c{}", chunk.index)
    };
    let cleaned: String = raw
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-') {
                c
            } else {
                '_'
            }
        })
        .collect();
    let skip = cleaned.len().saturating_sub(128);
    cleaned[skip..].to_owned()
}
