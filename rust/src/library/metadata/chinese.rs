use super::*;

const NON_NAMES: &[&str] = &[
    "文章编号",
    "基金项目",
    "中图分类",
    "文献标识",
    "收稿日期",
    "修回日期",
    "通讯作者",
    "第一作者",
    "作者简介",
    "引用格式",
    "网络出版",
    "网络首发",
    "参考文献",
    "摘要",
    "关键词",
];
pub fn non_person_name(name: &str) -> bool {
    NON_NAMES.contains(&name.trim())
}
pub fn is_chinese(text: &str) -> bool {
    text.chars()
        .filter(|c| matches!(*c,'\u{3400}'..='\u{4dbf}'|'\u{4e00}'..='\u{9fff}'))
        .take(3)
        .count()
        >= 3
}
pub fn from_chinese_text(text: &str, known_title: Option<&str>) -> Metadata {
    let compact = text
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect::<String>();
    let doi = extract_doi(text).map(|s| s.to_lowercase());
    let year = CN_YEAR
        .captures(text)
        .map(|c| c[1].to_owned())
        .or_else(|| ARTICLE_YEAR.captures(&compact).map(|c| c[1].to_owned()))
        .or_else(|| doi.as_deref().and_then(extract_year));
    let needle = known_title
        .map(|s| s.chars().filter(|c| !c.is_whitespace()).collect::<String>())
        .filter(|s| !s.is_empty());
    let location = needle.as_deref().and_then(|needle| {
        compact
            .find(needle)
            .map(|start| (start, start + needle.len()))
            .or_else(|| fuzzy_locate(&compact, needle))
    });
    let from = location.map(|(_, end)| end).unwrap_or(0);
    let region = &compact[from..];
    let end = AUTHOR_END
        .find(region)
        .map(|m| m.start())
        .unwrap_or_else(|| char_prefix(region, 60).len());
    let mut authors = names(&region[..end]);
    if authors.is_empty()
        && location.is_none()
        && let Some(sequence) = AUTHOR_SEQUENCE.find(char_prefix(&compact, 300))
    {
        authors = names(sequence.as_str());
        if authors.len() < 2 {
            authors.clear();
        }
    }
    let journal = location
        .filter(|(start, _)| *start > 0)
        .and_then(|(start, _)| {
            let header = VOLUME.replace_all(&compact[..start], "");
            let header = YEAR_MONTH.replace_all(&header, "");
            let header = ASCII_NOISE.replace_all(&header, "");
            JOURNAL.find(&header).map(|m| m.as_str().to_owned())
        });
    Metadata {
        authors,
        journal,
        year,
        doi,
        ..Default::default()
    }
}
pub(super) fn names(text: &str) -> Vec<String> {
    DELIMITER
        .split(text)
        .filter_map(|part| {
            let found = NAME.find(part)?;
            let name = found.as_str();
            let remainder = format!("{}{}", &part[..found.start()], &part[found.end()..]);
            (!non_person_name(name) && !HAN.is_match(&remainder)).then(|| name.to_owned())
        })
        .collect()
}
pub(super) fn fuzzy_locate(text: &str, needle: &str) -> Option<(usize, usize)> {
    let n = needle.chars().count();
    if n < 4 {
        return None;
    }
    let chars = text
        .char_indices()
        .map(|(byte, _)| byte)
        .chain(std::iter::once(text.len()))
        .collect::<Vec<_>>();
    let end = (chars.len() - 1).min(n * 6);
    let a = bigrams(needle);
    let mut best = None;
    let mut best_score = 0.0;
    let mut best_prefix = 0;
    for start in 0..=end.checked_sub(n)? {
        let window = &text[chars[start]..chars[start + n]];
        let b = bigrams(window);
        let intersection = a
            .iter()
            .map(|(key, count)| (*count).min(*b.get(key).unwrap_or(&0)))
            .sum::<usize>();
        let score = intersection as f64 / (n - 1) as f64;
        // Shifted windows can tie on bigrams. Prefer the matching title opening
        // so the last title character cannot become part of the first author.
        let prefix = window
            .chars()
            .zip(needle.chars())
            .take_while(|(a, b)| a == b)
            .count();
        if score > best_score || (score == best_score && prefix > best_prefix) {
            best_score = score;
            best_prefix = prefix;
            best = Some((chars[start], chars[start + n]));
        }
    }
    (best_score >= 0.7).then_some(best).flatten()
}
pub(super) fn bigrams(text: &str) -> HashMap<[char; 2], usize> {
    let mut result = HashMap::new();
    for pair in text.chars().collect::<Vec<_>>().windows(2) {
        *result.entry([pair[0], pair[1]]).or_default() += 1;
    }
    result
}
pub(super) fn char_prefix(text: &str, count: usize) -> &str {
    text.char_indices()
        .nth(count)
        .map(|(end, _)| &text[..end])
        .unwrap_or(text)
}
