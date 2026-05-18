#!/usr/bin/env python3
"""macOS AppIcon: kare kırp, kenarları doldur, güvenli alana oturt."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

CANVAS = 1024
# İçeriği hafif büyüt — Dock squircle kırpmasına karşı
ZOOM = 1.14


def trim_border(img: Image.Image, threshold: int = 248) -> Image.Image:
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    w, h = img.size
    pixels = img.load()
    min_x, min_y = w, h
    max_x, max_y = 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 12:
                continue
            if r >= threshold and g >= threshold and b >= threshold:
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    if max_x <= min_x:
        return img
    pad = max(2, int(min(w, h) * 0.008))
    return img.crop((
        max(0, min_x - pad),
        max(0, min_y - pad),
        min(w, max_x + 1 + pad),
        min(h, max_y + 1 + pad),
    ))


def center_square(img: Image.Image) -> Image.Image:
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    return img.crop((left, top, left + side, top + side))


def crop_cover(img: Image.Image, size: int) -> Image.Image:
    w, h = img.size
    scale = max(size / w, size / h)
    nw, nh = int(w * scale + 0.5), int(h * scale + 0.5)
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - size) // 2
    top = (nh - size) // 2
    return resized.crop((left, top, left + size, top + size))


def fit_macos_icon(src: Path, dst: Path) -> None:
    img = trim_border(Image.open(src).convert("RGBA"))
    square = center_square(img)

    if ZOOM != 1.0:
        w, h = square.size
        nw = int(w * ZOOM)
        nh = int(h * ZOOM)
        square = square.resize((nw, nh), Image.Resampling.LANCZOS)

    final = crop_cover(square, CANVAS)
    final.save(dst, format="PNG", optimize=True)
    print(f"OK: {dst} ({CANVAS}x{CANVAS})")


def emit_iconset(master: Path, iconset_dir: Path) -> None:
    iconset_dir.mkdir(parents=True, exist_ok=True)
    master_img = Image.open(master).convert("RGBA")
    for name, px in [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]:
        master_img.resize((px, px), Image.Resampling.LANCZOS).save(
            iconset_dir / name, format="PNG", optimize=True
        )


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "MacLLM/Resources/MacLLMIcon-1024-v2.png"
    master = root / "MacLLM/Resources/MacLLMIcon-1024.png"
    iconset = root / "MacLLM/Resources/Assets.xcassets/AppIcon.appiconset"
    fit_macos_icon(src, master)
    emit_iconset(master, iconset)
