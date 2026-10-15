#!/usr/bin/env python3
"""Render the MacWispr app icon from geometry (one source for every size).

Mark: a silver studio microphone on a dark graphite squircle with a soft
red glow, in the style of Apple's own macOS icons (Voice Memos, Dictation).

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


def vgrad(w, h, top, bottom):
    """Vertical gradient image (RGBA)."""
    g = Image.new("RGBA", (1, 256))
    for y in range(256):
        g.putpixel((0, y), lerp(top, bottom, y / 255) + (255,))
    return g.resize((max(1, int(w)), max(1, int(h))), Image.BICUBIC)


def render_mark(size):
    """Full-bleed squircle tile with a studio microphone, macOS style."""
    k = size / 1024.0
    tile = vgrad(size, size, (64, 64, 72), (14, 14, 18))

    # soft top sheen on the tile
    sheen = Image.new("L", (size, size), 0)
    ImageDraw.Draw(sheen).ellipse((-0.25 * size, -0.95 * size, 1.25 * size, 0.42 * size), fill=40)
    sheen = sheen.filter(ImageFilter.GaussianBlur(180 * k))
    tile = Image.composite(Image.new("RGBA", (size, size), (255, 255, 255, 255)), tile, sheen)

    cx = size / 2
    # capsule head
    hw, top, bot = 300 * k, 170 * k, 640 * k
    head_box = (cx - hw / 2, top, cx + hw / 2, bot)

    # warm glow behind the capsule
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse((cx - 260 * k, 230 * k, cx + 260 * k, 640 * k), fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(120 * k))
    tile = Image.composite(Image.new("RGBA", (size, size), (255, 69, 58, 255)), tile, glow)

    # capsule: brushed-silver vertical gradient
    cap = vgrad(hw, bot - top, (250, 250, 252), (176, 178, 186))
    cmask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(cmask).rounded_rectangle(head_box, radius=hw / 2, fill=255)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.paste(cap, (int(head_box[0]), int(top)))
    tile = Image.composite(layer, tile, cmask)

    d = ImageDraw.Draw(tile)
    # grille lines across the capsule
    for i in range(5):
        y = top + (150 + i * 62) * k
        d.rounded_rectangle((cx - hw * 0.30, y, cx + hw * 0.30, y + 14 * k), radius=7 * k,
                            fill=(140, 142, 152, 255))
    # highlight streak on the capsule
    hl = Image.new("L", (size, size), 0)
    ImageDraw.Draw(hl).rounded_rectangle((cx - hw * 0.36, top + 40 * k, cx - hw * 0.22, bot - 90 * k),
                                         radius=20 * k, fill=150)
    hl = hl.filter(ImageFilter.GaussianBlur(10 * k))
    tile = Image.composite(Image.new("RGBA", (size, size), (255, 255, 255, 255)), tile, hl)

    # U-shaped holder, stem and base in white
    d = ImageDraw.Draw(tile)
    w = 34 * k
    white = (245, 245, 247, 255)
    yoke = (cx - hw / 2 - 70 * k, 330 * k, cx + hw / 2 + 70 * k, 760 * k)
    d.arc(yoke, start=0, end=180, fill=white, width=int(w))
    # round caps where the arc ends, plus short uprights toward the capsule
    ry = (yoke[1] + yoke[3]) / 2
    for side in (-1, 1):
        x = cx + side * (hw / 2 + 70 * k)
        d.rounded_rectangle((x - w / 2, ry - 70 * k, x + w / 2, ry + w / 2), radius=w / 2, fill=white)
    d.rounded_rectangle((cx - w / 2, 750 * k, cx + w / 2, 850 * k), radius=w / 2, fill=white)
    d.rounded_rectangle((cx - 120 * k, 832 * k, cx + 120 * k, 832 * k + w), radius=w / 2, fill=white)

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
