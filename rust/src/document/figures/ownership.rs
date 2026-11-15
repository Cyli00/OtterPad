use super::*;

pub(super) fn blocked(visuals: &[Visual], caption: &Caption, pages: &[StructurePage]) -> bool {
    let Some(cap) = caption.box_ else {
        return true;
    };
    let page = &pages[caption.page];
    let regions = sight_regions(
        Box_::union(visuals.iter().map(|v| &pages[v.page].blocks[v.block])),
        cap,
    );
    page.blocks.iter().enumerate().any(|(i, b)| {
        if caption.block == Some(i)
            || caption.continuations.contains(&i)
            || visuals
                .iter()
                .any(|v| v.page == caption.page && v.block == i)
            || !stable(b)
            || b.raw_bbox.len() != 4
        {
            return false;
        }
        let box_ = Box_::of(b);
        if visuals.iter().any(|v| {
            let vb = Box_::of(&pages[v.page].blocks[v.block]);
            vb.contains(box_)
                || b.block_content.encode_utf16().count() <= 80
                    && !main_caption(&b.block_content)
                    && vb.overlaps(box_)
        }) {
            return false;
        }
        regions.iter().any(|r| r.overlaps(box_))
    })
}

/// 视觉块与题注之间可能出现阻挡物的区域。两者上下（或左右）排列时，只取两者本身和
/// 夹在中间、宽度（或高度）限于较小一方的通道：通栏图配半栏题注、侧边题注下方接正文时，
/// 与较小一方并排的内容不在两者之间。斜向排列沿用两者的外接框。
fn sight_regions(visual: Box_, cap: Box_) -> Vec<Box_> {
    let x_overlap = visual.r.min(cap.r) - visual.l.max(cap.l);
    let y_overlap = visual.b.min(cap.b) - visual.t.max(cap.t);
    let stacked = x_overlap > 0.0 && y_overlap <= 12.0;
    if !stacked && !(y_overlap > 0.0 && x_overlap <= 12.0) {
        return vec![Box_ {
            l: visual.l.min(cap.l),
            t: visual.t.min(cap.t),
            r: visual.r.max(cap.r),
            b: visual.b.max(cap.b),
        }];
    }
    // 左右并排时转置坐标，按上下排列求通道后再转回。
    let flip = |b: Box_| {
        if stacked {
            b
        } else {
            Box_ {
                l: b.t,
                t: b.l,
                r: b.b,
                b: b.r,
            }
        }
    };
    let (a, b) = (flip(visual), flip(cap));
    let (upper, lower) = if a.t + a.b <= b.t + b.b {
        (a, b)
    } else {
        (b, a)
    };
    let narrow = if a.r - a.l <= b.r - b.l { a } else { b };
    let mut regions = vec![visual, cap];
    if lower.t > upper.b {
        regions.push(flip(Box_ {
            l: narrow.l,
            t: upper.b,
            r: narrow.r,
            b: lower.t,
        }));
    }
    regions
}

pub(super) fn clusters(
    pages: &[StructurePage],
    visuals: &[Visual],
    cross: bool,
) -> Vec<Vec<Visual>> {
    let mut clusters = Vec::new();
    for (pi, page) in pages.iter().enumerate() {
        let gap = Box_::union(&page.blocks).diagonal() * 0.06;
        let mut remaining: Vec<_> = visuals.iter().copied().filter(|v| v.page == pi).collect();
        while !remaining.is_empty() {
            let mut members = vec![remaining.remove(0)];
            let mut grew = true;
            while grew {
                grew = false;
                let mut i = 0;
                while i < remaining.len() {
                    let v = remaining[i];
                    let b = &page.blocks[v.block];
                    let vb = Box_::of(b);
                    let close = members.iter().any(|m| {
                        let a = &page.blocks[m.block];
                        let ab = Box_::of(a);
                        if cross {
                            (a.parent_id.is_some() && a.parent_id == b.parent_id
                                || a.group_id.is_some() && a.group_id == b.group_id)
                                && ab.gap(vb) <= gap * 3.0
                                || ab.gap(vb) <= gap
                        } else {
                            ab.gap(vb) <= gap
                                || (ab.t - vb.t).abs() < 12.0
                                    && (ab.b - vb.b).abs() < 12.0
                                    && ab.gap(vb) <= (ab.r - ab.l).min(vb.r - vb.l) * 0.3
                        }
                    });
                    if !close {
                        i += 1;
                        continue;
                    }
                    let mut proposed = members.clone();
                    proposed.push(v);
                    let region = Box_::union(proposed.iter().map(|v| &page.blocks[v.block]));
                    if page.blocks.iter().enumerate().any(|(index, b)| {
                        !proposed.iter().any(|v| v.block == index)
                            && stable(b)
                            && b.raw_bbox.len() == 4
                            && region.overlaps(Box_::of(b))
                            && !proposed
                                .iter()
                                .any(|v| Box_::of(&page.blocks[v.block]).contains(Box_::of(b)))
                    }) {
                        i += 1;
                        continue;
                    }
                    members.push(v);
                    remaining.remove(i);
                    grew = true;
                }
            }
            clusters.push(members);
        }
    }
    clusters
}

pub(super) fn boundary_clear(
    page: &StructurePage,
    box_: Box_,
    to_end: bool,
    owned: &BTreeSet<usize>,
) -> bool {
    let columns = Columns::detect(page);
    !page.blocks.iter().enumerate().any(|(i, b)| {
        if owned.contains(&i)
            || matches!(
                b.block_label.as_str(),
                "header" | "footer" | "header_image" | "number"
            )
            || b.raw_bbox.len() != 4
            || !stable(b) && !is_visual(&b.block_label)
        {
            return false;
        }
        let other = Box_::of(b);
        if box_.contains(other) || !columns.same(box_, other) {
            return false;
        }
        if to_end {
            other.t >= box_.b
        } else {
            other.b <= box_.t
        }
    })
}

pub(super) fn cross_owners(
    pages: &[StructurePage],
    visuals: &[Visual],
    captions: &[Caption],
) -> BTreeMap<Visual, usize> {
    let clusters = clusters(pages, visuals, true);
    let mut candidates: Vec<Vec<(bool, usize)>> = vec![vec![]; clusters.len()];
    for (index, cluster) in clusters.iter().enumerate() {
        let pi = cluster[0].page;
        let page = &pages[pi];
        let box_ = Box_::union(cluster.iter().map(|v| &page.blocks[v.block]));
        for (ci, caption) in captions.iter().enumerate() {
            let cp = &pages[caption.page];
            if (cp.page_index - page.page_index).abs() != 1 {
                continue;
            }
            if captions.iter().filter(|c| c.page == caption.page).count() > 1
                && !cp.blocks.iter().any(|b| is_visual(&b.block_label))
            {
                continue;
            }
            if visuals.iter().any(|v| {
                v.page == caption.page
                    && caption.box_.is_some_and(|b| {
                        Box_::of(&cp.blocks[v.block]).gap(b)
                            <= Box_::union(&cp.blocks).diagonal() * 0.15
                            && Columns::detect(cp).same(Box_::of(&cp.blocks[v.block]), b)
                    })
                    && !blocked(&[*v], caption, pages)
            }) {
                continue;
            }
            let forward = page.page_index < cp.page_index;
            let bounds = Box_::union(&page.blocks);
            let dominant = bounds.r * bounds.b > 0.0
                && box_.area() / (bounds.r * bounds.b) >= 0.5
                && !captions.iter().any(|c| c.page == pi)
                && !page.blocks.iter().any(|b| {
                    !matches!(
                        b.block_label.as_str(),
                        "header" | "footer" | "header_image" | "number"
                    ) && stable(b)
                        && !box_.contains(Box_::of(b))
                });
            if !dominant
                && !boundary_clear(
                    page,
                    box_,
                    forward,
                    &cluster.iter().map(|v| v.block).collect(),
                )
            {
                continue;
            }
            let following = dominant
                && forward
                && main_caption(&caption.text)
                && caption.box_.is_some_and(|b| {
                    !cp.blocks.iter().any(|v| is_visual(&v.block_label))
                        && b.t > Box_::union(&cp.blocks).b * 0.5
                        && (b.r - b.l >= (box_.r - box_.l) * 0.65
                            || page
                                .blocks
                                .iter()
                                .any(|v| legend_next_page(&v.block_content)))
                });
            if let Some(b) = caption.box_ {
                let owned = caption
                    .block
                    .into_iter()
                    .chain(caption.continuations.iter().copied())
                    .collect();
                if !following && !boundary_clear(cp, b, !forward, &owned) {
                    continue;
                }
                let a = Columns::detect(page).column(box_);
                let b = Columns::detect(cp).column(b);
                if a >= 0
                    && b >= 0
                    && a != b
                    && !(if forward {
                        a == 1 && b == 0
                    } else {
                        a == 0 && b == 1
                    })
                {
                    continue;
                }
            } else {
                let lines: Vec<_> = cp.markdown.split('\n').collect();
                let line = caption
                    .line
                    .unwrap_or(if forward { 0 } else { lines.len() });
                if caption.line.is_none()
                    || if forward {
                        lines.iter().take(line).any(|l| !l.trim().is_empty())
                    } else {
                        lines.iter().skip(line + 1).any(|l| !l.trim().is_empty())
                    }
                {
                    continue;
                }
            }
            candidates[index].push((following, ci));
        }
    }
    let preferred: BTreeSet<_> = candidates
        .iter()
        .flatten()
        .filter(|c| c.0)
        .map(|c| c.1)
        .collect();
    for options in &mut candidates {
        let has = options.iter().any(|c| c.0);
        options.retain(|c| c.0 || !has && !preferred.contains(&c.1));
    }
    let mut result = BTreeMap::new();
    for (i, options) in candidates.iter().enumerate() {
        if options.len() != 1 {
            continue;
        }
        let ci = options[0].1;
        if candidates
            .iter()
            .filter(|o| o.iter().any(|c| c.1 == ci))
            .count()
            != 1
        {
            continue;
        }
        for v in &clusters[i] {
            result.insert(*v, ci);
        }
    }
    result
}
pub(super) fn legend_next_page(text: &str) -> bool {
    static PATTERN: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?i)\b(?:legend|caption)\s+(?:on|continues?\s+on)\s+(?:the\s+)?next\s+page\b|图注见下页|圖說見下頁").unwrap()
    });
    PATTERN.is_match(text)
}
