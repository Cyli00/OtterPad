"""给 docs/screenshots 下的手机原图套上 iPhone 风格机框：uv run --with pillow scripts/frame_screenshots.py。

机框用 4 倍超采样绘制后缩小，边缘抗锯齿；机身外完全透明、不带投影，
深浅背景下都不会出现灰边。输出尺寸与屏幕区域固定，website/prepare_images.py 依赖这些坐标。
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

SHOTS = Path(__file__).resolve().parent.parent / "docs" / "screenshots"

SS = 4
CANVAS = (704, 1500)
BODY = (0, 0, 704, 1486)
BODY_RADIUS = 104
SCREEN = (32, 30, 672, 1452)
SCREEN_RADIUS = 74
ISLAND = (298, 45, 406, 79)

RIM_TOP = (150, 157, 167)
RIM_BOTTOM = (88, 96, 108)
HIGHLIGHT = (196, 202, 210)
BEZEL = (17, 20, 25)
ISLAND_COLOR = (5, 6, 8)
LENS = (34, 42, 54)

SOURCES = ["mobile-pdf", "mobile-reading-bilingual", "mobile-figures", "mobile-ai", "mobile-ai-en"]


def scaled(box: tuple[int, ...]) -> tuple[int, ...]:
    return tuple(v * SS for v in box)


def inset(box: tuple[int, ...], d: int) -> tuple[int, ...]:
    l, t, r, b = box
    return l + d, t + d, r - d, b - d


def rounded_mask(size: tuple[int, int], box: tuple[int, ...], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(scaled(box), radius * SS, fill=255)
    return mask


def frame(src_path: Path, out_path: Path) -> None:
    w, h = BODY[2] * SS, BODY[3] * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    # 外圈钛金属边：自上而下的渐变
    rim = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / (h - 1)
        rim.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(RIM_TOP, RIM_BOTTOM)) + (255,))
    img.paste(rim.resize((w, h)), (0, 0), rounded_mask((w, h), BODY, BODY_RADIUS))

    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle(scaled(inset(BODY, 7)), (BODY_RADIUS - 7) * SS, fill=HIGHLIGHT)
    draw.rounded_rectangle(scaled(inset(BODY, 9)), (BODY_RADIUS - 9) * SS, fill=BEZEL)

    sl, st, sr, sb = SCREEN
    tw, th = (sr - sl) * SS, (sb - st) * SS
    src = Image.open(src_path).convert("RGBA")
    # cover 适配后居中裁切
    scale = max(tw / src.width, th / src.height)
    nw, nh = round(src.width * scale), round(src.height * scale)
    src = src.resize((nw, nh), Image.Resampling.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    src = src.crop((left, top, left + tw, top + th))
    screen_bg = Image.new("RGBA", (tw, th), BEZEL + (255,))
    screen_bg.alpha_composite(src)
    img.paste(screen_bg, (sl * SS, st * SS), rounded_mask((w, h), SCREEN, SCREEN_RADIUS).crop(scaled(SCREEN)))

    il, it, ir, ib = ISLAND
    draw.rounded_rectangle(scaled(ISLAND), (ib - it) * SS // 2, fill=ISLAND_COLOR)
    cx, cy, r = ir - 17, (it + ib) / 2, 6
    draw.ellipse(scaled((round(cx - r), round(cy - r), round(cx + r), round(cy + r))), fill=LENS)

    body = img.resize(BODY[2:], Image.Resampling.LANCZOS)
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.paste(body, BODY[:2])
    out.save(out_path, "PNG", optimize=True)
    print(f"{src_path.name} -> {out_path.name} {out.size}")


def main() -> None:
    for name in SOURCES:
        frame(SHOTS / f"{name}.png", SHOTS / f"{name}-framed.png")


if __name__ == "__main__":
    main()
