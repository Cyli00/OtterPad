use super::*;

impl Structure {
    pub(super) fn paddle_regions(&mut self) {
        let mut entries = Vec::new();
        let mut globals: BTreeMap<(i64, String), Vec<usize>> = BTreeMap::new();
        let mut locals: BTreeMap<(i64, i64, String), Vec<usize>> = BTreeMap::new();
        for (pi, page) in self.pages.iter().enumerate() {
            let mut ordered: Vec<_> = page.blocks.iter().enumerate().collect();
            ordered.sort_by_key(|(i, b)| b.block_order.unwrap_or(*i as i64));
            for (bi, b) in ordered {
                if !is_body(&b.block_label) {
                    continue;
                }
                let i = entries.len();
                entries.push((pi, bi));
                if let Some(g) = b.global_group_id.filter(|g| *g >= 0) {
                    globals
                        .entry((g, b.block_label.clone()))
                        .or_default()
                        .push(i);
                }
                if let Some(g) = b.group_id.filter(|g| *g >= 0) {
                    locals
                        .entry((page.page_index, g, b.block_label.clone()))
                        .or_default()
                        .push(i);
                }
            }
        }
        let mut parent: Vec<_> = (0..entries.len()).collect();
        pub(super) fn root(parent: &mut [usize], mut i: usize) -> usize {
            while parent[i] != i {
                parent[i] = parent[parent[i]];
                i = parent[i];
            }
            i
        }
        pub(super) fn union(parent: &mut [usize], a: usize, b: usize) {
            let l = root(parent, a);
            let r = root(parent, b);
            if l != r {
                parent[r] = l;
            }
        }
        let block = |i: usize| {
            let (p, b) = entries[i];
            &self.pages[p].blocks[b]
        };
        for group in globals.values() {
            for i in group.iter().skip(1) {
                union(&mut parent, group[0], *i);
            }
        }
        let mut local_groups: Vec<_> = locals.values().filter(|g| g.len() >= 2).collect();
        local_groups.sort_by_key(|g| g[0]);
        for group in local_groups {
            if group
                .iter()
                .filter(|i| !block(**i).block_content.trim().is_empty())
                .count()
                != 1
            {
                continue;
            }
            let roots: BTreeSet<_> = group.iter().map(|i| root(&mut parent, *i)).collect();
            let owners = (0..entries.len())
                .filter(|i| {
                    roots.contains(&root(&mut parent, *i))
                        && !block(*i).block_content.trim().is_empty()
                })
                .count();
            if owners == 1 {
                for i in group.iter().skip(1) {
                    union(&mut parent, group[0], *i);
                }
            }
        }
        let mut groups: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
        for i in 0..entries.len() {
            groups.entry(root(&mut parent, i)).or_default().push(i);
        }
        let mut replacements = Vec::new();
        for group in groups.values().filter(|g| g.len() >= 2) {
            let owners: Vec<_> = group
                .iter()
                .filter(|i| !block(**i).block_content.trim().is_empty())
                .collect();
            if owners.len() != 1 || group.iter().any(|i| block(*i).raw_bbox.len() != 4) {
                continue;
            }
            let owner = *owners[0];
            let b = block(owner);
            if !b.text_regions.is_empty()
                && (b.text_regions.len() >= group.len()
                    || b.text_regions.iter().any(|r| {
                        !group.iter().any(|i| {
                            self.pages[entries[*i].0].page_index == r.page_index
                                && block(*i).bbox() == r.bbox
                        })
                    }))
            {
                continue;
            }
            let areas: Vec<_> = group
                .iter()
                .map(|i| {
                    let b = block(*i).bbox();
                    (b[2] - b[0]) * (b[3] - b[1])
                })
                .collect();
            let total: f64 = areas.iter().sum();
            let regions = group
                .iter()
                .enumerate()
                .map(|(i, v)| TextRegion {
                    page_index: self.pages[entries[*v].0].page_index,
                    bbox: block(*v).bbox(),
                    source_length: ((b.block_content.encode_utf16().count() as f64 * areas[i]
                        / total)
                        .round() as usize)
                        .clamp(1, 1 << 30),
                })
                .collect();
            replacements.push((entries[owner], regions));
        }
        for ((p, b), regions) in replacements {
            self.pages[p].blocks[b].text_regions = regions;
        }
    }

    pub(super) fn mineru_regions(&mut self) {
        let entries: Vec<_> = self
            .pages
            .iter()
            .enumerate()
            .flat_map(|(p, page)| page.blocks.iter().enumerate().map(move |(b, _)| (p, b)))
            .collect();
        let mut replacements = Vec::new();
        for (i, (pi, bi)) in entries.iter().enumerate() {
            let owner = &self.pages[*pi];
            let b = &owner.blocks[*bi];
            if !is_body(&b.block_label) {
                continue;
            }
            let mut regions = b.text_regions.clone();
            let mut changed = false;
            for region in &mut regions {
                if region.page_index <= owner.page_index || region.bbox.len() != 4 {
                    continue;
                }
                let mut candidates = Vec::new();
                for (p, b) in entries.iter().skip(i + 1) {
                    let page = &self.pages[*p];
                    let block = &page.blocks[*b];
                    if !is_body(&block.block_label) {
                        continue;
                    }
                    if !block.block_content.trim().is_empty() {
                        break;
                    }
                    let box_ = block.bbox();
                    let a = &region.bbox;
                    if page.page_index <= owner.page_index
                        || box_.len() != 4
                        || block.block_label != owner.blocks[*bi].block_label
                    {
                        continue;
                    }
                    if a[0] >= box_[0] - 4.0
                        && a[1] >= box_[1] - 4.0
                        && a[2] <= box_[2] + 4.0
                        && a[3] <= box_[3] + 4.0
                        && (a[2] - a[0]) * (a[3] - a[1])
                            >= (box_[2] - box_[0]) * (box_[3] - box_[1]) * 0.7
                    {
                        candidates.push(page.page_index);
                    }
                }
                if candidates.len() == 1 && candidates[0] != region.page_index {
                    region.page_index = candidates[0];
                    changed = true;
                }
            }
            if changed {
                replacements.push(((*pi, *bi), regions));
            }
        }
        for ((p, b), regions) in replacements {
            self.pages[p].blocks[b].text_regions = regions;
        }
    }
}
