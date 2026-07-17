#!/usr/bin/env python3
"""Generate a polished Finder DMG background (dark, branded, drag arrow)."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Finder window content area (icon view). Match bounds in build-dmg.sh.
W, H = 720, 440
OUT = Path(__file__).with_name("background.png")


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _gradient(base: Image.Image) -> None:
    """Soft vertical gradient + subtle radial glow."""
    px = base.load()
    cx, cy = W // 2, int(H * 0.42)
    for y in range(H):
        t = y / max(H - 1, 1)
        r = int(18 + (32 - 18) * t)
        g = int(18 + (28 - 18) * t)
        b = int(22 + (36 - 22) * t)
        for x in range(W):
            # warm accent glow near center (brand coral-ish)
            dx = (x - cx) / (W * 0.55)
            dy = (y - cy) / (H * 0.55)
            fall = max(0.0, 1.0 - (dx * dx + dy * dy) ** 0.5)
            glow = fall ** 2
            px[x, y] = (
                min(255, int(r + 48 * glow)),
                min(255, int(g + 28 * glow)),
                min(255, int(b + 18 * glow)),
            )


def _draw_arrow(draw: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int) -> None:
    # Stem
    draw.line([(x0, y0), (x1 - 18, y1)], fill=(255, 255, 255, 200), width=5)
    # Arrow head
    tip = (x1, y1)
    left = (x1 - 28, y1 - 16)
    right = (x1 - 28, y1 + 16)
    draw.polygon([tip, left, right], fill=(255, 255, 255, 220))


def main() -> int:
    img = Image.new("RGB", (W, H), (18, 18, 22))
    _gradient(img)

    # Soft vignette
    vignette = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse((-80, -60, W + 80, H + 120), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(80))
    dark = Image.new("RGB", (W, H), (8, 8, 10))
    img = Image.composite(img, dark, vignette)

    draw = ImageDraw.Draw(img, "RGBA")

    title_font = _font(28)
    sub_font = _font(15)
    hint_font = _font(13)

    # Top title
    title = "MacWispr"
    sub = "Drag to Applications to install"
    # Center title
    tb = draw.textbbox((0, 0), title, font=title_font)
    tw = tb[2] - tb[0]
    draw.text(((W - tw) / 2, 36), title, font=title_font, fill=(245, 242, 236, 255))
    sb = draw.textbbox((0, 0), sub, font=sub_font)
    sw = sb[2] - sb[0]
    draw.text(((W - sw) / 2, 74), sub, font=sub_font, fill=(180, 175, 165, 255))

    # Drop zones (subtle rounded rects under where icons sit)
    # Icon centers used by build-dmg.sh: app (180, 210), Applications (540, 210)
    for cx in (180, 540):
        box = (cx - 70, 145, cx + 70, 285)
        draw.rounded_rectangle(box, radius=28, outline=(255, 255, 255, 28), width=2)
        draw.rounded_rectangle(
            (box[0] + 2, box[1] + 2, box[2] - 2, box[3] - 2),
            radius=26,
            fill=(255, 255, 255, 8),
        )

    # Arrow between zones
    _draw_arrow(draw, 265, 215, 455, 215)

    # Labels under zones (Finder also shows icon names — keep light)
    left_l = "MacWispr"
    right_l = "Applications"
    lb = draw.textbbox((0, 0), left_l, font=hint_font)
    rb = draw.textbbox((0, 0), right_l, font=hint_font)
    # Space reserved for Finder icon labels (~ below 285)
    draw.text((180 - (lb[2] - lb[0]) / 2, 300), left_l, font=hint_font, fill=(120, 118, 112, 0))
    # fully transparent labels — Finder names handle this; keep for layout notes only

    # Footer
    foot = "Apple Silicon · Microphone + Accessibility required"
    fb = draw.textbbox((0, 0), foot, font=hint_font)
    fw = fb[2] - fb[0]
    draw.text(((W - fw) / 2, H - 42), foot, font=hint_font, fill=(140, 136, 128, 220))

    # Accent bar at bottom
    draw.rectangle((0, H - 4, W, H), fill=(232, 120, 72, 255))

    img = img.convert("RGB")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT} ({W}x{H})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
