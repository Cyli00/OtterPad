//! Caption inventory and competitive visual ownership, ported from v0.1.7.
mod captions;
mod inventory;
mod ownership;
mod patterns;
use captions::*;
use inventory::*;
use ownership::*;
pub use patterns::supplementary_caption;
use patterns::*;
pub(crate) use patterns::{sublabel, usable};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::LazyLock,
};

use super::{
    revision,
    structure::{LayoutBlock, Structure, StructurePage, is_caption, is_visual},
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CaptionRef {
    #[serde(rename = "page_idx", alias = "page_index")]
    pub page_index: i64,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub block_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line_index: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub start: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub end: Option<usize>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FigureSegment {
    pub id: String,
    pub page_index: i64,
    pub caption_text: String,
    pub caption_name: String,
    pub caption_refs: Vec<CaptionRef>,
    pub blocks: Vec<LayoutBlock>,
    pub cross_page: bool,
    pub kind: String,
}
#[derive(Clone)]
struct Caption {
    page: usize,
    text: String,
    name: String,
    box_: Option<Box_>,
    block: Option<usize>,
    continuations: Vec<usize>,
    refs: Vec<CaptionRef>,
    line: Option<usize>,
}
#[derive(Clone, Copy, Debug, Default)]
struct Box_ {
    l: f64,
    t: f64,
    r: f64,
    b: f64,
}
impl Box_ {
    fn of(b: &LayoutBlock) -> Self {
        let a = b.bbox();
        if a.len() == 4 {
            Self {
                l: a[0],
                t: a[1],
                r: a[2],
                b: a[3],
            }
        } else {
            Self::default()
        }
    }
    fn union<'a>(blocks: impl IntoIterator<Item = &'a LayoutBlock>) -> Self {
        let mut value = None::<Self>;
        for b in blocks {
            if b.raw_bbox.len() != 4 {
                continue;
            }
            let b = Self::of(b);
            value = Some(value.map_or(b, |a| Self {
                l: a.l.min(b.l),
                t: a.t.min(b.t),
                r: a.r.max(b.r),
                b: a.b.max(b.b),
            }));
        }
        value.unwrap_or_default()
    }
    fn gap(self, b: Self) -> f64 {
        let x = (self.l - b.r).max(b.l - self.r).max(0.0);
        let y = (self.t - b.b).max(b.t - self.b).max(0.0);
        x.hypot(y)
    }
    fn contains(self, b: Self) -> bool {
        b.l >= self.l && b.r <= self.r && b.t >= self.t && b.b <= self.b
    }
    fn overlaps(self, b: Self) -> bool {
        self.l < b.r && b.l < self.r && self.t < b.b && b.t < self.b
    }
    fn area(self) -> f64 {
        (self.r - self.l) * (self.b - self.t)
    }
    fn diagonal(self) -> f64 {
        (self.r - self.l).hypot(self.b - self.t)
    }
    fn values(self) -> Vec<Value> {
        vec![self.l.into(), self.t.into(), self.r.into(), self.b.into()]
    }
}

struct Pattern {
    regex: Regex,
    kind: String,
}
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Visual {
    page: usize,
    block: usize,
}
#[derive(Clone, Copy)]
struct Columns {
    left: Option<f64>,
    right: Option<f64>,
}
impl Columns {
    fn detect(page: &StructurePage) -> Self {
        let bounds = Box_::union(&page.blocks);
        let mid = (bounds.l + bounds.r) / 2.0;
        let text: Vec<_> = page
            .blocks
            .iter()
            .filter(|b| {
                matches!(
                    b.block_label.as_str(),
                    "text" | "paragraph_title" | "abstract"
                ) && b.raw_bbox.len() == 4
            })
            .collect();
        let left: Vec<_> = text
            .iter()
            .filter(|b| Box_::of(b).r <= mid + 30.0)
            .collect();
        let right: Vec<_> = text
            .iter()
            .filter(|b| Box_::of(b).l >= mid - 30.0)
            .collect();
        if text.len() < 4 || left.len() < 3 || right.len() < 3 {
            return Self {
                left: None,
                right: None,
            };
        }
        Self {
            left: Some(left.iter().map(|b| Box_::of(b).r).fold(0.0, f64::max)),
            right: Some(
                right
                    .iter()
                    .map(|b| Box_::of(b).l)
                    .fold(f64::INFINITY, f64::min),
            ),
        }
    }
    fn column(self, b: Box_) -> i32 {
        if let (Some(l), Some(r)) = (self.left, self.right) {
            if b.r <= l + 30.0 {
                return 0;
            }
            if b.l >= r - 30.0 {
                return 1;
            }
        }
        -1
    }
    fn same(self, a: Box_, b: Box_) -> bool {
        let a = self.column(a);
        let b = self.column(b);
        a < 0 || b < 0 || a == b
    }
}

pub fn find_figures(structure: &Structure) -> Vec<FigureSegment> {
    let mut pages = structure.pages.clone();
    let mut captions: Vec<_> = pages
        .iter()
        .enumerate()
        .flat_map(|(i, p)| collect(p, i))
        .collect();
    normalize_inventory(&mut pages, &mut captions);
    let visuals: Vec<_> = pages
        .iter()
        .enumerate()
        .flat_map(|(p, page)| {
            page.blocks
                .iter()
                .enumerate()
                .filter(|(_, b)| is_visual(&b.block_label) && b.raw_bbox.len() == 4)
                .map(move |(b, _)| Visual { page: p, block: b })
        })
        .collect();
    let clusters = clusters(&pages, &visuals, false);
    let cross = cross_owners(&pages, &visuals, &captions);
    let mut options = Vec::new();
    for (ci, c) in captions.iter().enumerate() {
        let page = &pages[c.page];
        let cap = c.block.map(|b| &page.blocks[b]);
        let diagonal = Box_::union(&page.blocks).diagonal();
        let native: Vec<_> = visuals
            .iter()
            .copied()
            .filter(|v| {
                v.page == c.page
                    && cap.is_some_and(|b| {
                        b.parent_id.is_some() && b.parent_id == page.blocks[v.block].parent_id
                    })
            })
            .collect();
        let mut candidates: Vec<_> = visuals
            .iter()
            .map(|v| vec![*v])
            .chain(clusters.clone())
            .collect();
        if !native.is_empty() {
            candidates.push(native);
        }
        let cross_group: Vec<_> = cross
            .iter()
            .filter(|(_, caption)| **caption == ci)
            .map(|(v, _)| *v)
            .collect();
        if !cross_group.is_empty() {
            candidates.push(cross_group);
        }
        let mut seen = BTreeSet::new();
        let mut choices = Vec::new();
        for candidate in candidates {
            let mut key = candidate.clone();
            key.sort();
            if !seen.insert(key) {
                continue;
            }
            let mut score = 0.0;
            let mut valid = true;
            for v in &candidate {
                let b = &pages[v.page].blocks[v.block];
                let same = v.page == c.page;
                let parent = same
                    && cap
                        .is_some_and(|cap| cap.parent_id.is_some() && cap.parent_id == b.parent_id);
                let is_cross = cross.get(v) == Some(&ci);
                let visual_text = if !b.block_content.is_empty() {
                    b.block_content.clone()
                } else {
                    std::path::Path::new(b.source_image.as_deref().unwrap_or(""))
                        .file_stem()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .replace('_', " ")
                };
                let name = caption_name(&visual_text);
                let numbered = !name.is_empty()
                    && name.to_lowercase() == c.name.to_lowercase()
                    && !page.blocks.iter().any(|b| is_visual(&b.block_label));
                if !same && !is_cross && !numbered {
                    valid = false;
                    break;
                }
                if let Some(cap_box) = c.box_.filter(|_| same) {
                    let distance = Box_::of(b).gap(cap_box);
                    if distance > diagonal * 0.5
                        || !Columns::detect(page).same(Box_::of(b), cap_box)
                        || blocked(&[*v], c, &pages)
                    {
                        valid = false;
                        break;
                    }
                    score += 4.0 - distance / diagonal.max(1.0) * 10.0;
                } else if parent || is_cross || numbered {
                    score += if is_cross { 3.5 } else { 4.0 };
                } else if same
                    && c.line.is_some()
                    && captions.iter().filter(|x| x.page == c.page).count() == 1
                    && clusters.iter().filter(|x| x[0].page == c.page).count() == 1
                {
                    score += 2.5;
                } else {
                    valid = false;
                    break;
                }
                if parent {
                    score += 1.0;
                }
                let table = caption_kind(&c.text) == "table";
                if (b.block_label == "table") != table {
                    score -= 0.35;
                }
            }
            // 版面模型未标为题注的块（如以“Figure 2 shows”开头的正文）证据较弱，
            // 与题注块等距竞争时让位，单独存在时仍可配对。
            if cap.is_some_and(|b| !is_caption(&b.block_label)) {
                score -= 0.35;
            }
            if valid
                && !(candidate.len() > 1
                    && candidate.iter().all(|v| v.page == c.page)
                    && c.box_.is_some()
                    && blocked(&candidate, c, &pages))
            {
                choices.push((score, candidate));
            }
        }
        choices.sort_by(|a, b| b.0.total_cmp(&a.0));
        choices.truncate(24);
        options.push(choices);
    }
    let mut pending: BTreeSet<_> = (0..captions.len()).collect();
    let mut assigned = BTreeMap::new();
    while let Some(first) = pending.first().copied() {
        let mut component = vec![first];
        let mut related = BTreeSet::new();
        loop {
            for c in &component {
                related.extend(options[*c].iter().flat_map(|(_, v)| v.iter()).copied());
            }
            let extra: Vec<_> = pending
                .iter()
                .copied()
                .filter(|c| {
                    !component.contains(c)
                        && options[*c]
                            .iter()
                            .any(|(_, v)| v.iter().any(|v| related.contains(v)))
                })
                .collect();
            if extra.is_empty() {
                break;
            }
            component.extend(extra);
        }
        for c in &component {
            pending.remove(c);
        }
        let mut beam = vec![(0.0, BTreeMap::<Visual, usize>::new())];
        for ci in component {
            let mut next = Vec::new();
            for state in beam {
                next.push(state.clone());
                for (score, visuals) in &options[ci] {
                    if visuals.iter().any(|v| state.1.contains_key(v)) {
                        continue;
                    }
                    let mut values = state.1.clone();
                    for v in visuals {
                        values.insert(*v, ci);
                    }
                    next.push((state.0 + score, values));
                }
            }
            next.sort_by(|a, b| b.0.total_cmp(&a.0));
            next.truncate(64);
            beam = next;
        }
        let best = &beam[0];
        for (visual, caption) in &best.1 {
            if beam
                .iter()
                .filter(|s| best.0 - s.0 < 0.2)
                .all(|s| s.1.get(visual) == Some(caption))
            {
                assigned.insert(*visual, *caption);
            }
        }
    }
    build_segments(&pages, &visuals, &captions, &assigned)
}
