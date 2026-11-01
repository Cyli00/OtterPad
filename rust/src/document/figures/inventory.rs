use super::*;

pub(super) fn caption_kind(text: &str) -> String {
    caption_matches(&normalized(text))
        .first()
        .filter(|m| m.0 == 0)
        .map(|m| m.2.clone())
        .unwrap_or_else(|| "figure".into())
}

pub(super) fn normalize_inventory(pages: &mut [StructurePage], captions: &mut Vec<Caption>) {
    let mut repeated_titles = BTreeMap::<String, usize>::new();
    for page in pages.iter() {
        let titles: BTreeSet<_> = page
            .blocks
            .iter()
            .filter(|b| b.block_label == "paragraph_title")
            .map(|b| b.block_content.clone())
            .collect();
        for title in titles {
            *repeated_titles.entry(title).or_default() += 1;
        }
    }
    // Join an unfinished page-tail caption with a caption-labelled continuation
    // on the next physical page, retaining both original source references.
    let mut consumed = BTreeSet::new();
    for p in 0..pages.len().saturating_sub(1) {
        if pages[p + 1].page_index != pages[p].page_index + 1 {
            continue;
        }
        let content = |b: &&LayoutBlock| {
            !matches!(
                b.block_label.as_str(),
                "header" | "footer" | "number" | "page_number" | "header_image" | "footer_image"
            ) && b.raw_bbox.len() == 4
        };
        let tail = Box_::union(pages[p].blocks.iter().filter(content));
        let Some((index, head)) = pages[p + 1]
            .blocks
            .iter()
            .enumerate()
            .find(|(_, b)| content(b))
        else {
            continue;
        };
        if !is_caption(&head.block_label)
            || is_visual(&head.block_label)
            || main_caption(&head.block_content)
        {
            continue;
        }
        let head_box = Box_::of(head);
        let bounds = Box_::union(pages[p + 1].blocks.iter().filter(content));
        for c in captions.iter_mut().filter(|c| c.page == p) {
            let Some(box_) = c.box_ else {
                continue;
            };
            if complete(&c.text)
                || tail.b - box_.b > 12.0
                || head_box.t - bounds.t > 12.0
                || !head.block_content.trim().starts_with(|c: char| {
                    c.is_ascii_lowercase() || ('\u{4e00}'..='\u{9fff}').contains(&c)
                })
                || head_box.r <= box_.l
                || head_box.l >= box_.r
            {
                continue;
            }
            let parts: Vec<_> = std::iter::once(index)
                .chain(continuations(&pages[p + 1], index))
                .collect();
            let extra: Vec<_> = parts
                .iter()
                .map(|i| pages[p + 1].blocks[*i].block_content.as_str())
                .collect();
            c.text = joined(std::iter::once(c.text.as_str()).chain(extra));
            for i in parts {
                let b = &pages[p + 1].blocks[i];
                consumed.insert((p + 1, i));
                c.refs.push(CaptionRef {
                    page_index: pages[p + 1].page_index,
                    text: b.block_content.clone(),
                    block_id: Some(b.block_id.clone()),
                    line_index: None,
                    start: None,
                    end: None,
                });
            }
            break;
        }
    }
    captions.retain(|c| !c.block.is_some_and(|b| consumed.contains(&(c.page, b))));
    for p in 0..pages.len() {
        let numbered = captions.iter().any(|c| {
            (pages[c.page].page_index - pages[p].page_index).abs() <= 1 && main_caption(&c.text)
        });
        let visuals: Vec<_> = pages[p]
            .blocks
            .iter()
            .filter(|b| is_visual(&b.block_label))
            .collect();
        let visual_box = Box_::union(visuals.iter().copied());
        captions.retain(|c| {
            if c.page != p || !numbered || main_caption(&c.text) || c.box_.is_none() {
                return true;
            }
            if c.block
                .is_some_and(|b| pages[p].blocks[b].parent_id.is_some())
            {
                return true;
            }
            let b = c.box_.unwrap();
            !(c.text.encode_utf16().count() <= 80
                && b.gap(visual_box) <= 24.0
                && b.b - b.t < (visual_box.b - visual_box.t) * 0.1)
        });
        let bounds = Box_::union(&pages[p].blocks);
        let plate = numbered
            && visuals.len() > 1
            && !captions
                .iter()
                .any(|c| c.page == p && main_caption(&c.text))
            && visual_box.area() > bounds.r * bounds.b * 0.5
            && !pages[p].blocks.iter().any(|b| {
                b.block_label == "text"
                    && (b.block_content.encode_utf16().count() > 80
                        || !visual_box.contains(Box_::of(b)))
            });
        for i in 0..pages[p].blocks.len() {
            let b = &pages[p].blocks[i];
            let repeated = b.block_label == "paragraph_title"
                && b.raw_bbox.len() == 4
                && Box_::of(b).t < bounds.b * 0.08
                && repeated_titles.get(&b.block_content).copied().unwrap_or(0) >= 2;
            if repeated {
                pages[p].blocks[i].block_label = "header".into();
                continue;
            }
            if numbered
                && (b.block_label == "figure_title" || plate && b.block_label == "text")
                && !main_caption(&b.block_content)
                && !sublabel(b)
            {
                pages[p].blocks[i].block_label = if b.block_content.encode_utf16().count() > 80 {
                    "text"
                } else {
                    "figure_annotation"
                }
                .into();
            }
        }
    }
}

pub(super) fn build_segments(
    pages: &[StructurePage],
    visuals: &[Visual],
    captions: &[Caption],
    assigned: &BTreeMap<Visual, usize>,
) -> Vec<FigureSegment> {
    let mut result = Vec::new();
    let mut owned = BTreeSet::new();
    let mut caption_order = Vec::new();
    for ci in assigned.values() {
        if !caption_order.contains(ci) {
            caption_order.push(*ci);
        }
    }
    for ci in caption_order {
        let caption = &captions[ci];
        for (p, page) in pages.iter().enumerate() {
            let mut members: Vec<_> = assigned
                .iter()
                .filter(|(v, c)| **c == ci && v.page == p)
                .map(|(v, _)| (*v, pages[v.page].blocks[v.block].clone()))
                .collect();
            if members.is_empty() {
                continue;
            }
            let box_ = Box_::union(members.iter().map(|(_, b)| b));
            let extra: Vec<_> = visuals
                .iter()
                .copied()
                .filter(|v| {
                    v.page == p
                        && !assigned.contains_key(v)
                        && members
                            .iter()
                            .any(|(_, m)| Box_::of(m).contains(Box_::of(&page.blocks[v.block])))
                })
                .collect();
            members.extend(extra.into_iter().map(|v| (v, page.blocks[v.block].clone())));
            let cap = caption.block.map(|b| &pages[caption.page].blocks[b]);
            for (i, b) in page.blocks.iter().enumerate() {
                let v = Visual { page: p, block: i };
                if members.iter().any(|(m, _)| *m == v)
                    || owned.contains(&v)
                    || is_visual(&b.block_label)
                    || captions.iter().any(|c| {
                        c.refs.iter().any(|r| {
                            r.page_index == page.page_index
                                && r.block_id.as_deref() == Some(b.block_id.as_str())
                        }) || c.page == p && (c.block == Some(i) || c.continuations.contains(&i))
                    })
                {
                    continue;
                }
                let inside = b.raw_bbox.len() == 4 && box_.contains(Box_::of(b));
                let near = b.raw_bbox.len() == 4 && box_.gap(Box_::of(b)) <= 24.0;
                let parent = caption.page == p
                    && cap.is_some_and(|c| c.parent_id.is_some() && c.parent_id == b.parent_id);
                if inside
                    || annotation(b) && (parent || near)
                    || (sublabel(b) || b.block_label == "figure_annotation") && near
                {
                    let mut b = b.clone();
                    b.block_label = if annotation(&b) && !inside && note(&b) {
                        "vision_footnote"
                    } else {
                        "figure_annotation"
                    }
                    .into();
                    members.push((v, b));
                    owned.insert(v);
                }
            }
            let mut blocks = Vec::new();
            let mut cap_ids = BTreeSet::new();
            if p == caption.page {
                if let Some(i) = caption.block {
                    let mut b = page.blocks[i].clone();
                    b.block_label = "figure_title".into();
                    b.raw_bbox = caption.box_.unwrap_or_default().values();
                    b.block_content = caption.text.clone();
                    b.caption_kind = Some("caption".into());
                    cap_ids.insert(b.block_id.clone());
                    blocks.push(b);
                }
                for i in &caption.continuations {
                    let b = page.blocks[*i].clone();
                    cap_ids.insert(b.block_id.clone());
                    blocks.push(b);
                }
            }
            blocks.extend(
                members
                    .iter()
                    .map(|(_, b)| b)
                    .filter(|b| !cap_ids.contains(&b.block_id))
                    .cloned(),
            );
            let notes: Vec<_> = members.iter().filter(|(_, b)| note(b)).collect();
            let text = joined(
                std::iter::once(caption.text.as_str())
                    .chain(notes.iter().map(|(_, b)| b.block_content.as_str())),
            );
            let mut refs = if caption.refs.is_empty() {
                vec![CaptionRef {
                    page_index: pages[caption.page].page_index,
                    text: caption.text.clone(),
                    block_id: caption
                        .block
                        .map(|b| pages[caption.page].blocks[b].block_id.clone()),
                    line_index: caption.line,
                    start: None,
                    end: None,
                }]
            } else {
                caption.refs.clone()
            };
            if caption.refs.is_empty() {
                for i in &caption.continuations {
                    let b = &pages[caption.page].blocks[*i];
                    refs.push(CaptionRef {
                        page_index: pages[caption.page].page_index,
                        text: b.block_content.clone(),
                        block_id: Some(b.block_id.clone()),
                        line_index: None,
                        start: None,
                        end: None,
                    });
                }
            }
            for (v, b) in notes {
                refs.push(CaptionRef {
                    page_index: pages[v.page].page_index,
                    text: b.block_content.clone(),
                    block_id: Some(b.block_id.clone()),
                    line_index: None,
                    start: None,
                    end: None,
                });
            }
            let mut ids: Vec<_> = blocks.iter().map(|b| b.block_id.as_str()).collect();
            ids.sort();
            result.push(FigureSegment {
                id: revision(&format!(
                    "{}:{}:{}",
                    page.page_index,
                    caption.name,
                    ids.join("|")
                )),
                page_index: page.page_index,
                caption_text: text,
                caption_name: caption.name.clone(),
                caption_refs: refs,
                blocks,
                cross_page: p != caption.page,
                kind: caption_kind(&caption.text),
            });
        }
    }
    result.sort_by_key(|s| s.page_index);
    result
}
