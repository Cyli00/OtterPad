use super::*;

pub(super) static PATTERNS: LazyLock<Vec<Pattern>> = LazyLock::new(|| {
    let config: Value = serde_json::from_str(include_str!(
        "../../../../assets/config/caption_patterns.json"
    ))
    .expect("caption pattern configuration");
    let mut result = Vec::new();
    for kind in ["figure", "table", "other"] {
        let mut prefixes = BTreeSet::new();
        for node in config.as_object().into_iter().flatten().map(|(_, n)| n) {
            for p in node[kind]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
            {
                prefixes.insert(p.to_owned());
            }
        }
        for p in config["supplementary"]["standalone"][kind]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
        {
            prefixes.insert(p.to_owned());
        }
        for (language, modifiers) in config["supplementary"]["modifiers"]
            .as_object()
            .into_iter()
            .flatten()
        {
            for modifier in modifiers
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
            {
                for base in config[language][kind]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                {
                    prefixes.insert(format!("{modifier} {base}"));
                    if ["zh", "zh-Hant", "ja", "ko"].contains(&language.as_str()) {
                        prefixes.insert(format!("{modifier}{base}"));
                    }
                }
            }
        }
        let mut prefixes: Vec<_> = prefixes.into_iter().collect();
        prefixes.sort_by_key(|p| std::cmp::Reverse(p.chars().count()));
        let branches = prefixes
            .iter()
            .map(|p| {
                p.split_whitespace()
                    .map(regex::escape)
                    .collect::<Vec<_>>()
                    .join(r"\s+")
            })
            .collect::<Vec<_>>()
            .join("|");
        let pattern = format!(
            "(?i)(?P<prefix>{branches})(?P<number>{}){}",
            config["number_pattern"].as_str().expect("number pattern"),
            config["suffix_pattern"].as_str().expect("suffix pattern")
        );
        result.push(Pattern {
            regex: Regex::new(&pattern).expect("valid caption regex"),
            kind: if kind == "other" { "chart" } else { kind }.into(),
        });
        for raw in config["number_first"].as_array().into_iter().flatten() {
            let bases = raw[kind]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .map(regex::escape)
                .collect::<Vec<_>>()
                .join("|");
            if bases.is_empty() {
                continue;
            }
            result.push(Pattern {
                regex: Regex::new(&format!(
                    "(?i){}\\s+(?:{bases}){}",
                    raw["number_pattern"]
                        .as_str()
                        .expect("number-first pattern"),
                    config["suffix_pattern"].as_str().expect("suffix pattern")
                ))
                .expect("valid number-first regex"),
                kind: if kind == "other" { "chart" } else { kind }.into(),
            });
        }
    }
    result
});
pub(super) static SUBLABEL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)^(?:\([a-z](?:\s*(?:,|and|&)\s*[a-z])*\)|[a-z](?:\s*(?:,|and|&)\s*[a-z])*[).:;-]?)$",
    )
    .unwrap()
});
pub(super) static NOTE_LEAD: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^(?:\([a-z](?:\s*(?:,|and|&)\s*[a-z])*\)|[a-z](?:\s*(?:,|and|&)\s*[a-z])*[).:;-])\s+\S").unwrap()
});
pub(super) fn normalized(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}
pub(super) fn joined<'a>(parts: impl IntoIterator<Item = &'a str>) -> String {
    let mut unique = Vec::new();
    for part in parts {
        let part = normalized(part);
        if !part.is_empty() && !unique.contains(&part) {
            unique.push(part);
        }
    }
    unique.join(" ")
}
pub(crate) fn sublabel(b: &LayoutBlock) -> bool {
    let text = normalized(&b.block_content);
    text.encode_utf16().count() <= 30 && SUBLABEL.is_match(&text)
}
pub(crate) fn usable(text: &str) -> bool {
    let text = normalized(text);
    !text.is_empty() && !SUBLABEL.is_match(&text)
}
/// Same supplementary classifier as the old figure service, for reference-image priority.
pub fn supplementary_caption(text: &str) -> bool {
    static SUPPLEMENTARY: LazyLock<Regex> = LazyLock::new(|| {
        let config: Value = serde_json::from_str(include_str!(
            "../../../../assets/config/caption_patterns.json"
        ))
        .unwrap();
        let mut normal = BTreeSet::new();
        let mut supplementary = BTreeSet::new();
        for kind in ["figure", "table", "other"] {
            for node in config.as_object().unwrap().values() {
                for value in node[kind]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                {
                    normal.insert(value.to_owned());
                }
            }
            for value in config["supplementary"]["standalone"][kind]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
            {
                supplementary.insert(value.to_owned());
            }
            for (language, modifiers) in config["supplementary"]["modifiers"].as_object().unwrap() {
                for modifier in modifiers
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                {
                    for base in config[language][kind]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(Value::as_str)
                    {
                        supplementary.insert(format!("{modifier} {base}"));
                        if ["zh", "zh-Hant", "ja", "ko"].contains(&language.as_str()) {
                            supplementary.insert(format!("{modifier}{base}"));
                        }
                    }
                }
            }
        }
        let alternatives = |values: BTreeSet<String>| {
            let mut values: Vec<_> = values.into_iter().collect();
            values.sort_by_key(|s| std::cmp::Reverse(s.chars().count()));
            values
                .iter()
                .map(|s| {
                    s.split_whitespace()
                        .map(regex::escape)
                        .collect::<Vec<_>>()
                        .join(r"\s+")
                })
                .collect::<Vec<_>>()
                .join("|")
        };
        let mut branches = vec![
            format!(
                "(?:{}){}",
                alternatives(supplementary),
                config["number_pattern"].as_str().unwrap()
            ),
            format!(
                "(?:{}){}",
                alternatives(normal),
                config["supplementary_number_pattern"].as_str().unwrap()
            ),
        ];
        for raw in config["number_first"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|r| r["supplementary"] == true)
        {
            let labels: [&str; 3] = ["figure", "table", "other"];
            let names = labels
                .iter()
                .flat_map(|kind| raw[kind].as_array().into_iter().flatten())
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect();
            branches.push(format!(
                "{}\\s+(?:{})",
                raw["number_pattern"].as_str().unwrap(),
                alternatives(names)
            ));
        }
        Regex::new(&format!(
            "(?i)^(?:{}){}",
            branches.join("|"),
            config["suffix_pattern"].as_str().unwrap()
        ))
        .unwrap()
    });
    let normalized = normalized(text);
    SUPPLEMENTARY.is_match(normalized.trim_start_matches(['#', '*', '_', ' ']))
}
