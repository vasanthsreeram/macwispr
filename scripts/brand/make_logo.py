#!/usr/bin/env python3
"""Render the MacWispr app icon from geometry (one source for every size).

Mark: five rounded voice bars of rising/falling height that resolve into a
tall text cursor on the right — speech turning into typed text. Deep indigo →
violet squircle, soft top sheen, white bars with a mint cursor.

Usage: make_logo.py <out_dir>
Writes logo-1024.png (macOS icon canvas with margin + shadow), logo-mark.png
(full-bleed squircle), plus 512/256/128/64/32 web sizes.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersample canvas; downsampled at the end


def squircle_mask(size, inset, exponent=4.2):
    """Superellipse mask (Apple-style continuous corners)."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    r = (size - 2 * inset) / 2
    c = size / 2
    pts = []
    for i in range(2048):
        t = 2 * math.pi * i / 2048
        ct, st = math.cos(t), math.sin(t)
        x = c + r * math.copysign(abs(ct) ** (2 / exponent), ct)
        y = c + r * math.copysign(abs(st) ** (2 / exponent), st)
        pts.append((x, y))
    d.polygon(pts, fill=255)
    return m


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient(size, top, bottom):
    """Diagonal two-stop gradient (built small, upscaled smoothly)."""
    n = 256
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            t = (y + 0.35 * x) / (1.35 * (n - 1))
            px[x, y] = lerp(top, bottom, t)
    return g.resize((size, size), Image.BICUBIC)


def render_mark(size):
    """Full-bleed squircle tile with the waveform→cursor glyph."""
    k = size / 1024.0
    tile = gradient(size, (58, 52, 220), (150, 62, 240)).convert("RGBA")

    # top sheen
    sheen = Image.new("L", (size, size), 0)
    ImageDraw.Draw(sheen).ellipse((-0.3 * size, -0.9 * size, 1.3 * size, 0.5 * size), fill=34)
    sheen = sheen.filter(ImageFilter.GaussianBlur(220 * k))
    white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    tile = Image.composite(white, tile, sheen)

    d = ImageDraw.Draw(tile)
    bar_w = 74 * k
    gap = 46 * k
    heights = [200, 380, 540, 340, 180]  # voice envelope
    cursor_h = 560
    cap_extra = bar_w * 0.55  # cursor caps overhang the cursor column
    total_w = len(heights) * bar_w + len(heights) * gap + 26 * k + bar_w + cap_extra
    x = (size - total_w) / 2
    cy = size / 2
    for h in heights:
        h *= k
        d.rounded_rectangle((x, cy - h / 2, x + bar_w, cy + h / 2), radius=bar_w / 2, fill=(255, 255, 255, 255))
        x += bar_w + gap
    x += 26 * k
    # text cursor: tall mint bar with serif caps
    ch = cursor_h * k
    cw = bar_w * 0.62
    cx = x + (bar_w - cw) / 2
    mint = (110, 245, 200, 255)
    d.rounded_rectangle((cx, cy - ch / 2, cx + cw, cy + ch / 2), radius=cw / 2, fill=mint)
    cap_w = bar_w * 1.7
    cap_h = cw
    capx = cx + cw / 2 - cap_w / 2
    d.rounded_rectangle((capx, cy - ch / 2, capx + cap_w, cy - ch / 2 + cap_h), radius=cap_h / 2, fill=mint)
    d.rounded_rectangle((capx, cy + ch / 2 - cap_h, capx + cap_w, cy + ch / 2), radius=cap_h / 2, fill=mint)

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(tile, (0, 0), squircle_mask(size, 0))
    return out


def render_app_icon(size):
    """macOS icon canvas: 824/1024 tile centred with a soft drop shadow."""
    tile_px = int(size * 824 / 1024)
    inset = (size - tile_px) // 2
    mark = render_mark(tile_px)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh_mask = Image.new("L", (size, size), 0)
    sh_mask.paste(mark.split()[3], (inset, inset + int(size * 0.012)))
    shadow.putalpha(sh_mask.filter(ImageFilter.GaussianBlur(size * 0.018)).point(lambda a: int(a * 0.45)))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(mark, (inset, inset), mark)
    return canvas


def share_card(icon, path):
    """1200x630 social card: icon centred on the site's cream background."""
    card = Image.new("RGB", (1200, 630), (246, 241, 232))
    i = icon.resize((360, 360), Image.LANCZOS)
    card.paste(i, (420, 135), i)
    card.save(path)


def export_repo(root):
    """Write every logo the repo ships, all from the same geometry."""
    icon = render_app_icon(S).resize((1024, 1024), Image.LANCZOS)
    flat = Image.new("RGB", (1024, 1024), (255, 255, 255))
    flat.paste(icon, (0, 0), icon)
    targets = {
        "docs/assets": ["logo.png", "logo-solid.png", "logo-light.png", "logo-128.png", "logo-256.png", "logo-512.png"],
        "website/assets": ["logo.png", "logo-solid.png", "logo-light.png", "logo-mark.png",
                           "logo-128.png", "logo-256.png", "logo-512.png"],
    }
    sizes = {"logo-128.png": 128, "logo-256.png": 256, "logo-512.png": 512, "logo-mark.png": 128}
    for folder, names in targets.items():
        for name in names:
            dest = os.path.join(root, folder, name)
            if name in sizes:
                icon.resize((sizes[name], sizes[name]), Image.LANCZOS).save(dest)
            elif name == "logo-solid.png":
                flat.save(dest)
            else:
                icon.save(dest)
    for name in ("og.png", "share-og.png"):
        share_card(icon, os.path.join(root, "website/assets", name))
    os.makedirs(os.path.join(root, "website-macwispr/assets"), exist_ok=True)
    for name in ("logo-128.png", "logo-256.png", "logo-mark.png"):
        icon.resize((sizes[name], sizes[name]), Image.LANCZOS).save(
            os.path.join(root, "website-macwispr/assets", name))
    share_card(icon, os.path.join(root, "website-macwispr/assets/share-og.png"))
    # Versioned copies: /assets/* is cached immutable, so new art needs new URLs.
    for site in ("website", "website-macwispr"):
        brand = os.path.join(root, site, "brand")
        os.makedirs(brand, exist_ok=True)
        for px in (32, 128, 256, 512):
            icon.resize((px, px), Image.LANCZOS).save(os.path.join(brand, f"macwispr-icon-v2-{px}.png"))
        share_card(icon, os.path.join(brand, "macwispr-share-v2.png"))
    print("exported repo logos")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--repo":
        export_repo(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
        return
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    icon = render_app_icon(S).resize((1024, 1024), Image.LANCZOS)
    icon.save(os.path.join(out, "logo-1024.png"))
    mark = render_mark(S).resize((1024, 1024), Image.LANCZOS)
    mark.save(os.path.join(out, "logo-mark.png"))
    for px in (512, 256, 128, 64, 32):
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(out, f"logo-{px}.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
