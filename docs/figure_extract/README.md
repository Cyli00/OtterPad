# Figure Extract Manifest

`figures.json` 是 figure 提取管线的持久化产物，位于 `library/<documentId>/figures/figures.json`。

## JSON 结构

```jsonc
{
  "figures": [ ... ],       // FigureManifestEntry 数组
  "diagnostics": { ... }    // 提取过程诊断统计
}
```

> **向后兼容**：旧版 manifest 为裸数组 `[{entry}, ...]`，`loadManifest()` 自动识别两种格式。

---

## figures — 每条 entry 的字段

### 核心字段（始终存在）

| 字段 | 类型 | 说明 |
|------|------|------|
| `img` | `string` | 裁剪 PNG 的绝对路径 |
| `figure_title` | `string` | 完整 caption 文本（含子图说明，多行已合并） |
| `page_idx` | `int` | Figure 所在 PDF 页码（0-based） |
| `block_ids` | `string[]` | 组成该 figure 的所有 layout block ID（含 caption + 视觉块 + 子标签） |

### 裁剪信息（v2 新增，可选）

| 字段 | 类型 | 说明 |
|------|------|------|
| `crop_bbox` | `double[4]` | 裁剪区域 `[left, top, right, bottom]`，API 坐标系（144 DPI, zoom=2.0）。可用 `renderZoom/apiZoom` 缩放到渲染坐标 |
| `caption_bbox` | `double[4]` | Caption 的 bbox（API 坐标系），仅当 caption 来自 parsing_res_list block 时存在 |
| `width_px` | `int` | 输出 PNG 宽度（像素，216 DPI 渲染） |
| `height_px` | `int` | 输出 PNG 高度（像素） |

### 诊断字段（v2 新增，可选）

| 字段 | 类型 | 可选值 | 说明 |
|------|------|--------|------|
| `caption_source` | `string` | `blockMatch` / `markdownFallback` | Caption 的发现来源。`blockMatch`：parsing_res_list 中某 block 的内容匹配 caption 正则（Phase 1/2）；`markdownFallback`：仅在 markdown 行中检测到（Phase 3 兜底） |
| `pair_method` | `string` | `samePage` / `crossPage` / `lateBound` / `ordinalMatch` | Figure-Caption 配对方式。`samePage`：同页空间距离最近（Pass 1）；`crossPage`：跨页 ±1 双向唯一配对（Pass 2）；`lateBound`：同页未占用 caption 晚到认领（Pass 3）；`ordinalMatch`：分离式排版序号配对，预印本 Figure Legends 布局中 caption 和 figure 完全在不同页面，按文档顺序 1:1 配对（Pass 4） |
| `direction` | `string` | `above` / `below` / `left` / `right` | Figure 相对 caption 的空间方向。仅 `region_method=caption_anchored` 时存在 |
| `region_method` | `string` | `caption_anchored` / `visual_union` / `legacy_fallback` | 裁剪区域推断方式。`caption_anchored`：基于 caption 位置 + 方向推断 + stable blocker 扩展；`visual_union`：直接取视觉块的外接矩形；`legacy_fallback`：无视觉块时排除 caption 后取剩余 block union |

---

## diagnostics — 诊断统计

| 字段 | 类型 | 说明 |
|------|------|------|
| `total_captions` | `int` | Inventory 阶段召回的 caption 候选总数（Phase 1 + Phase 3） |
| `total_clusters` | `int` | 视觉块聚类后的簇总数 |
| `paired_count` | `int` | 成功配对的 segment 数（= figures 数组可能的最大长度） |
| `cropped_count` | `int` | 实际裁剪成功的 figure 数（≤ paired_count，裁剪失败时减少） |
| `dropped_count` | `int` | 被丢弃的视觉簇数 |
| `dropped` | `object[]` | 每个被丢弃簇的详情（仅 dropped_count > 0 时存在） |

### dropped 条目

| 字段 | 类型 | 说明 |
|------|------|------|
| `page_idx` | `int` | 被丢弃簇所在页码 |
| `block_count` | `int` | 簇内 block 数 |
| `reason` | `string` | 丢弃原因。当前仅 `uncaptioned`（无 caption 可匹配） |

---

## 示例

```json
{
  "figures": [
    {
      "img": "/path/to/library/abc123/figures/Figure_1.png",
      "figure_title": "Figure 1. Experimental setup for two-photon imaging.",
      "page_idx": 2,
      "block_ids": ["b001", "b002", "b003"],
      "crop_bbox": [85.0, 120.5, 580.0, 450.2],
      "caption_bbox": [85.0, 455.0, 580.0, 480.0],
      "width_px": 742,
      "height_px": 494,
      "caption_source": "blockMatch",
      "pair_method": "samePage",
      "direction": "above",
      "region_method": "caption_anchored"
    }
  ],
  "diagnostics": {
    "total_captions": 6,
    "total_clusters": 5,
    "paired_count": 5,
    "cropped_count": 5,
    "dropped_count": 0
  }
}
```

---

## 坐标系

- **API 坐标系**：PaddleOCR 返回的 bbox 基于 144 DPI（zoom = 2.0）
- **渲染坐标系**：裁剪渲染使用 216 DPI（zoom = 3.0），缩放比 = 3.0 / 2.0 = 1.5
- `crop_bbox` 和 `caption_bbox` 均为 API 坐标系，乘以 1.5 得到渲染坐标
- `width_px` / `height_px` 为渲染坐标系下的实际像素尺寸
