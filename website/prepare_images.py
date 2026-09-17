# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "numpy"]
# ///
"""从原始截图生成网站主题预览：uv run website/prepare_images.py。"""

from collections import Counter
from pathlib import Path
import re
import sys

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "docs" / "screenshots"

# 坐标对应当前截图；论文原页、封面与图表保持原色，避免重映射数据色标。
IMAGES = {
    "mobile-reading-bilingual-framed": ((704, 1500), [(106, 1130, 594, 1206)]),
    "mobile-figures-framed": ((704, 1500), [(56, 270, 648, 784), (56, 928, 648, 1340)]),
    "mobile-pdf-framed": ((704, 1500), [(40, 165, 664, 1428)]),
    "desktop-reading": ((2358, 1623), [(1034, 736, 1434, 1255)]),
    "desktop-pdf-bilingual": ((2359, 1623), [(163, 73, 2308, 1505)]),
    "desktop-library": ((2359, 1623), [(136, 198, 665, 953), (689, 198, 1224, 953), (1243, 198, 1780, 953)]),
    "desktop-library-en": ((2359, 1623), [(136, 198, 665, 953), (689, 198, 1224, 953), (1243, 198, 1780, 953)]),
}


def palette():
    css = (ROOT / "style.css").read_text(encoding="utf-8")
    result = {}
    for name in ["paper", "paper-2", "ink", "ink-soft", "water", "water-2", "water-wash"]:
        value = re.search(rf"--{name}:\s*#([0-9a-fA-F]+);", css).group(1)
        if len(value) == 3:
            value = "".join(char * 2 for char in value)
        result[name] = np.array([int(value[i:i + 2], 16) for i in (0, 2, 4)])
    return result


def interpolate(values, stops, colors):
    return np.stack([np.interp(values, stops, [color[i] for color in colors]) for i in range(3)], axis=-1)


def prepare(name, size, protected, colors):
    source = Image.open(SOURCE / f"{name}.png").convert("RGBA")
    if source.size != size:
        raise ValueError(f"{name} 尺寸已变化，请重新核对图表保护区域")
    original = np.array(source)
    rgb = original[:, :, :3].astype(np.float32)
    alpha = original[:, :, 3].copy()
    ui = alpha == 255
    for left, top, right, bottom in protected:
        ui[top:bottom, left:right] = False

    samples = Counter(map(tuple, original[:, :, :3][ui][::12])).most_common(4)
    print(name, "取样", [(tuple(map(int, color)), count) for color, count in samples])
    lightness = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    spread = rgb.max(axis=-1) - rgb.min(axis=-1)
    result = rgb.copy()

    # 连续插值同时处理文字抗锯齿，避免只替换纯色后留下蓝边。
    neutral = ui & (spread <= 22)
    result[neutral] = interpolate(
        lightness[neutral], [0, 26, 70, 117, 190, 230, 241, 249, 255],
        [np.zeros(3), colors["ink"], colors["ink-soft"], np.full(3, 117),
         np.full(3, 190), colors["water-wash"], colors["paper-2"], colors["paper"], colors["paper"]],
    )
    blue = ui & (rgb[:, :, 2] > rgb[:, :, 0] + 22) & (rgb[:, :, 2] > rgb[:, :, 1] + 8)
    result[blue] = interpolate(
        lightness[blue], [0, 91, 142, 217, 249, 255],
        [colors["ink"], colors["water-2"], colors["water"], colors["water-wash"], colors["paper"], colors["paper"]],
    )
    if name.startswith("mobile-"):
        # 原图阴影延伸到画布边界，清除低透明度阴影，仅保留机框实体边缘。
        alpha = np.clip((alpha.astype(np.float32) - 220) * 255 / 35, 0, 255).astype(np.uint8)

    output = np.dstack((np.rint(result).clip(0, 255).astype(np.uint8), alpha))
    destination = ROOT / "assets" / f"{name}.webp"
    Image.fromarray(output).save(destination, lossless=True, method=6)
    saved = np.array(Image.open(destination).convert("RGBA"))
    for left, top, right, bottom in protected:
        assert np.array_equal(saved[top:bottom, left:right], original[top:bottom, left:right]), "图表保护区域发生变化"
    if name.startswith("mobile-"):
        assert not saved[:20, :20, 3].any() and not saved[:20, -20:, 3].any(), "机框四角仍有阴影残留"
    source_background = ui & np.all(original[:, :, :3] == [248, 249, 255], axis=-1)
    assert np.all(saved[:, :, :3][source_background] == colors["paper"]), "背景未映射为纸白"
    print(f"  已保存 {destination.name}；改色 {int(np.count_nonzero(neutral | blue))} 像素，图表原色校验通过")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    colors = palette()
    for name, (size, protected) in IMAGES.items():
        prepare(name, size, protected, colors)
