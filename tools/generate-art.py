#!/usr/bin/env python3
"""Generate Gloom's Bars mask/art PNGs (Media/masks/, Media/art/).

Every shape ships three textures: an icon mask (alpha 1 fill), a cooldown
swipe (alpha 0.8 fill), and a state ring-glow (soft rim + light center fill).
All art follows the edge-padding rule (docs/API-NOTES.md §2): shapes extend to
120 of the 128 half-canvas, never touching the edge, so clamped GPU sampling
can't flatten the silhouette.

Adding a shape = adding one signed-distance function to SHAPES below and
rerunning:  python3 tools/generate-art.py   (from the repo root)
"""
import math
import os
import struct
import zlib

SIZE, SS = 256, 4      # 256px canvas, 4x4 supersampling
EXTENT = 120.0         # shape half-extent in design px (of 128)


# --- signed-distance functions (negative = inside) --------------------------

def sd_circle(px, py):
    return math.hypot(px, py) - EXTENT


def sd_roundrect(px, py, corner=30.0):
    qx = abs(px) - (EXTENT - corner)
    qy = abs(py) - (EXTENT - corner)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - corner


SHAPES = {
    "circle": sd_circle,
    "roundrect": sd_roundrect,
}


# --- alpha profiles ---------------------------------------------------------

def mask_alpha(d):
    return 1.0 if d <= 0 else 0.0          # supersampling anti-aliases the edge


def swipe_alpha(d):
    return 0.8 if d <= 0 else 0.0          # Blizzard-like sweep darkening


def ring_alpha(d):
    if d >= 0:
        return 0.0
    fill = 0.20 if d <= -14 else max(0.0, 0.20 * (-d - 6) / 8)
    ring = 0.60 * math.exp(-((d + 8) / 5.0) ** 2)
    return min(1.0, fill + ring)


# --- PNG writer -------------------------------------------------------------

def render(sdf, profile):
    rows = []
    for y in range(SIZE):
        row = bytearray([0])               # filter type 0 per scanline
        for x in range(SIZE):
            acc = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px = (x * SS + sx + 0.5) / SS - 128.0
                    py = (y * SS + sy + 0.5) / SS - 128.0
                    acc += profile(sdf(px, py))
            row += bytes((255, 255, 255, round(acc * 255 / (SS * SS))))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path)


if __name__ == "__main__":
    for name, sdf in SHAPES.items():
        write_png(f"Media/masks/{name}.png", render(sdf, mask_alpha))
        write_png(f"Media/masks/{name}-swipe.png", render(sdf, swipe_alpha))
        write_png(f"Media/art/{name}-ring.png", render(sdf, ring_alpha))
