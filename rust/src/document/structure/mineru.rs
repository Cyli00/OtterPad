use super::*;

impl Structure {
    pub fn from_mineru_layout(root: &Value) -> Result<Self> {
        let pages = root["pdf_info"]
            .as_array()
            .ok_or_else(|| OtterError::new(ErrorCode::InvalidData, "missing pdf_info"))?;
        let mut lines: BTreeMap<String, BTreeSet<i64>> = BTreeMap::new();
        fn index(block: &Value, page: i64, lines: &mut BTreeMap<String, BTreeSet<i64>>) {
            for line in block["lines"].as_array().into_iter().flatten() {
                lines.entry(line_key(line)).or_default().insert(page);
            }
            for block in block["blocks"].as_array().into_iter().flatten() {
                index(block, page, lines);
            }
        }
        for (i, page) in pages.iter().enumerate() {
            for block in page["preproc_blocks"].as_array().into_iter().flatten() {
                index(
                    block,
                    page["page_idx"].as_i64().unwrap_or(i as i64),
                    &mut lines,
                );
            }
        }
        let mut result = Self::default();
        for raw in pages.iter().filter(|p| p.is_object()) {
            let pi = raw["page_idx"]
                .as_i64()
                .unwrap_or(result.pages.len() as i64);
            let size = bbox(raw.get("page_size"), 2);
            let mut page = StructurePage {
                page_index: pi,
                blocks: vec![],
                markdown: String::new(),
                page_size: size.as_ref().map(|s| s.iter().map(|v| v * 2.0).collect()),
                images: BTreeMap::new(),
            };
            for block in raw["para_blocks"]
                .as_array()
                .into_iter()
                .flatten()
                .chain(raw["discarded_blocks"].as_array().into_iter().flatten())
                .filter(|b| b.is_object())
            {
                if let Some(children) = block["blocks"].as_array().filter(|c| !c.is_empty()) {
                    let parent = format!("mu_p{pi}_owner{}", page.blocks.len());
                    let kind = match block["type"].as_str() {
                        Some("table") => "table",
                        Some("chart") => "chart",
                        _ => "figure",
                    };
                    for child in children.iter().filter(|b| b.is_object()) {
                        append_mineru(
                            &mut page,
                            child,
                            Some(&parent),
                            Some(kind),
                            size.is_some(),
                            &lines,
                        );
                    }
                } else {
                    append_mineru(&mut page, block, None, None, size.is_some(), &lines);
                }
            }
            result.pages.push(page);
        }
        result.mineru_regions();
        Ok(result)
    }

    pub fn from_mineru_v2(pages: &[Value], sizes: &[Vec<f64>]) -> Result<Self> {
        if pages.iter().any(|p| {
            p.as_array().is_none_or(|b| {
                b.iter()
                    .any(|v| !v["type"].is_string() || !v["content"].is_object())
            })
        }) {
            return invalid("unsupported MinerU v2 schema");
        }
        let mut result = Self::default();
        for (pi, raw) in pages.iter().enumerate() {
            let size = sizes
                .get(pi)
                .filter(|s| s.len() == 2 && s.iter().all(|n| n.is_finite() && *n > 0.0));
            let mut page = StructurePage {
                page_index: pi as i64,
                blocks: vec![],
                markdown: String::new(),
                page_size: size.map(|s| s.iter().map(|v| v * 2.0).collect()),
                images: BTreeMap::new(),
            };
            for (order, raw) in raw.as_array().into_iter().flatten().enumerate() {
                let kind = raw["type"].as_str().unwrap_or_default();
                let content = &raw["content"];
                let visual = matches!(kind, "image" | "table" | "chart");
                let parent = format!("mu_p{pi}_v{order}");
                let label = if visual {
                    kind
                } else {
                    match kind {
                        "title" => {
                            if pi == 0 && content["level"] == 1 {
                                "doc_title"
                            } else {
                                "paragraph_title"
                            }
                        }
                        "paragraph" | "list" => "text",
                        _ => kind,
                    }
                };
                let coordinates = match (size, bbox(raw.get("bbox"), 4)) {
                    (Some(size), Some(b)) => vec![
                        b[0] * size[0] / 500.0,
                        b[1] * size[1] / 500.0,
                        b[2] * size[0] / 500.0,
                        b[3] * size[1] / 500.0,
                    ],
                    _ => vec![],
                };
                let mut block = empty_block(parent.clone(), label.into());
                block.raw_bbox = coordinates.iter().map(|v| json!(v)).collect();
                block.source_data =
                    json!({"provider":"mineru","page":pi,"order":order,"native":raw});
                block.parent_id = visual.then(|| parent.clone());
                block.source_image = optional_string(&content["image_source"], "path");
                block.block_order = Some(page.blocks.len() as i64);
                block.block_content = if kind == "table" {
                    string(content, "html")
                } else {
                    text(
                        &content[if kind == "list" {
                            "list_items".to_owned()
                        } else {
                            format!("{kind}_content")
                        }],
                    )
                };
                page.blocks.push(block);
                if visual {
                    let note = text(&content[format!("{kind}_footnote")]);
                    if !note.is_empty() {
                        let mut b = empty_block(format!("{parent}_note"), "vision_footnote".into());
                        b.block_content = note;
                        b.parent_id = Some(parent.clone());
                        b.source_data = json!({"provider":"mineru","page":pi,"native":content[format!("{kind}_footnote")]});
                        page.blocks.push(b);
                    }
                    let caption = text(&content[format!("{kind}_caption")]);
                    if !caption.trim().is_empty() {
                        let mut b = empty_block(format!("{parent}_cap"), "figure_title".into());
                        b.block_content = caption;
                        b.parent_id = Some(parent.clone());
                        b.caption_kind = Some(if kind == "image" { "figure" } else { kind }.into());
                        b.block_order = Some(page.blocks.len() as i64);
                        page.blocks.push(b);
                    }
                } else if let Some(fields) = content.as_object() {
                    for (field, value) in fields.iter().filter(|(k, _)| k.ends_with("_caption")) {
                        let caption = text(value);
                        if caption.trim().is_empty() {
                            continue;
                        }
                        let mut b = empty_block(format!("{parent}_{field}"), field.clone());
                        b.block_content = caption;
                        b.parent_id = Some(parent.clone());
                        b.source_data = json!({"provider":"mineru","native":value});
                        page.blocks.push(b);
                    }
                }
            }
            result.pages.push(page);
        }
        Ok(result)
    }
}

pub(super) fn empty_block(id: String, label: String) -> LayoutBlock {
    LayoutBlock {
        block_id: id,
        block_label: label,
        raw_bbox: vec![],
        block_content: String::new(),
        group_id: None,
        global_group_id: None,
        block_order: None,
        parent_id: None,
        source_image: None,
        caption_kind: None,
        text_regions: vec![],
        source_data: Value::Null,
    }
}
pub(super) fn text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Array(items) => items
            .iter()
            .map(text)
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join(" "),
        Value::Object(items) => [
            "content",
            "item_content",
            "list_content",
            "list_items",
            "children",
        ]
        .iter()
        .find_map(|k| items.get(*k).filter(|v| !v.is_null()))
        .map(text)
        .unwrap_or_default(),
        _ => String::new(),
    }
}
pub(super) fn line_key(line: &Value) -> String {
    json!([
        bbox(line.get("bbox"), 4),
        line["spans"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|s| s.is_object())
            .map(|s| json!([s["type"], s["content"], s["html"]]))
            .collect::<Vec<_>>()
    ])
    .to_string()
}
pub(super) fn append_mineru(
    page: &mut StructurePage,
    block: &Value,
    parent: Option<&str>,
    kind: Option<&str>,
    has_size: bool,
    lines: &BTreeMap<String, BTreeSet<i64>>,
) {
    let pi = page.page_index;
    let order = page.blocks.len();
    let type_ = block["type"].as_str().unwrap_or_default();
    let mut texts = Vec::new();
    let mut regions: Vec<TextRegion> = Vec::new();
    let mut source = None;
    for line in block["lines"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|l| l.is_object())
    {
        let mut parts = Vec::new();
        for span in line["spans"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|s| s.is_object())
        {
            if let Some(value) = span["content"].as_str().filter(|s| !s.is_empty()) {
                parts.push(
                    if span["type"] == "inline_equation" && !value.starts_with('$') {
                        format!("${value}$")
                    } else {
                        value.to_owned()
                    },
                );
            }
            if let Some(html) = span["html"].as_str().filter(|s| !s.is_empty()) {
                parts.push(html.to_owned());
            }
            if source.is_none() {
                source = optional_string(span, "image_path");
            }
        }
        if parts.is_empty() {
            continue;
        }
        let line_text = parts.join(" ");
        texts.push(line_text.clone());
        if let Some(box_) = bbox(line.get("bbox"), 4).filter(|_| has_size) {
            let cross = line["spans"]
                .as_array()
                .into_iter()
                .flatten()
                .any(|s| s["cross_page"] == true);
            let matches: Vec<_> = lines
                .get(&line_key(line))
                .into_iter()
                .flatten()
                .copied()
                .filter(|p| *p > pi)
                .collect();
            let region_page = if !cross {
                Some(pi)
            } else if matches.len() == 1 {
                Some(matches[0])
            } else {
                None
            };
            let Some(region_page) = region_page else {
                continue;
            };
            let b: Vec<_> = box_.iter().map(|v| v * 2.0).collect();
            let length = line_text.encode_utf16().count();
            if let Some(previous) = regions.last_mut().filter(|r| {
                r.page_index == region_page
                    && b[1] >= r.bbox[1]
                    && b[0] < r.bbox[2]
                    && b[2] > r.bbox[0]
                    && b[1] - r.bbox[3] < (b[3] - b[1]) * 3.0
            }) {
                previous.bbox = vec![
                    previous.bbox[0].min(b[0]),
                    previous.bbox[1],
                    previous.bbox[2].max(b[2]),
                    b[3],
                ];
                previous.source_length += length;
            } else {
                regions.push(TextRegion {
                    page_index: region_page,
                    bbox: b,
                    source_length: length,
                });
            }
        }
    }
    let label = match type_ {
        "image_body" => "image",
        "chart_body" => "chart",
        "table_body" => "table",
        "image_caption" | "chart_caption" | "table_caption" => "figure_title",
        "image_footnote" | "chart_footnote" | "table_footnote" => "vision_footnote",
        "title" => {
            if pi == 0 && page.blocks.is_empty() {
                "doc_title"
            } else {
                "paragraph_title"
            }
        }
        _ => type_,
    };
    let mut b = empty_block(format!("mu_p{pi}_b{order}"), label.into());
    b.block_content = texts.join(" ");
    b.raw_bbox = bbox(block.get("bbox"), 4)
        .filter(|_| has_size)
        .unwrap_or_default()
        .iter()
        .map(|v| json!(v * 2.0))
        .collect();
    b.source_data = json!({"provider":"mineru","page":pi,"order":order,"native":block});
    b.text_regions = regions;
    b.parent_id = parent.map(str::to_owned);
    b.source_image = source;
    b.caption_kind = if label == "figure_title" {
        kind.map(str::to_owned)
    } else {
        None
    };
    b.block_order = Some((order + 1) as i64);
    page.blocks.push(b);
}
