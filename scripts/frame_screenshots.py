"""将 docs 下的手机截图套上 Google Pixel 9 Pro 机框。

机框资源：scripts/device_frames/pixel9pro_obsidian.png
来源：https://github.com/jamesjingyi/mockup-device-frames (Pixel 9 Pro Obsidian)
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
FRAME_PATH = Path(__file__).resolve().parent / "device_frames" / "pixel9pro_obsidian.png"

# Pixel 9 Pro Obsidian frame：透明洞为屏幕区域
# frame size 1620x3136, screen hole (170, 142) – (1449, 2997) = 1280x2856
SCREEN = (170, 142, 1449, 2997)  # left, top, right, bottom inclusive

# README 展示用输出宽度（保持比例）
OUT_WIDTH = 480

SOURCES = [
    "PDF_reader.png",
    "immersive_reading_experience.png",
    "extract_figures_for_reading.png",
    "ask_anything_with_fullcontext.png",
]


def frame_screenshot(src_path: Path, frame: Image.Image, out_path: Path) -> None:
    src = Image.open(src_path).convert("RGBA")
    sw, sh = src.size

    sl, st, sr, sb = SCREEN
    tw, th = sr - sl + 1, sb - st + 1

    # cover-fit 填满屏幕后居中裁切
    scale = max(tw / sw, th / sh)
    nw, nh = int(sw * scale + 0.5), int(sh * scale + 0.5)
    src_r = src.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - tw) // 2
    top = (nh - th) // 2
    src_r = src_r.crop((left, top, left + tw, top + th))

    canvas = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    canvas.paste(src_r, (sl, st))
    # 机框叠在上方：边框/侧键/挖孔摄像头盖住截图
    result = Image.alpha_composite(canvas, frame)

    # 缩到 README 友好尺寸
    out_h = int(result.height * OUT_WIDTH / result.width + 0.5)
    result = result.resize((OUT_WIDTH, out_h), Image.Resampling.LANCZOS)
    result.save(out_path, "PNG", optimize=True)
    print(f"  -> {out_path.name} {result.size}")


def main() -> None:
    if not FRAME_PATH.exists():
        raise SystemExit(
            f"缺少机框: {FRAME_PATH}\n"
            "请从 jamesjingyi/mockup-device-frames 下载 Pixel 9 Pro Obsidian PNG。"
        )

    frame = Image.open(FRAME_PATH).convert("RGBA")
    print(f"机框: {FRAME_PATH.name} {frame.size}")

    for name in SOURCES:
        src = DOCS / name
        if not src.exists():
            print(f"  skip missing {name}")
            continue
        out = DOCS / name.replace(".png", "_framed.png")
        print(f"Framing {name}...")
        frame_screenshot(src, frame, out)

    print("Done.")


if __name__ == "__main__":
    main()
