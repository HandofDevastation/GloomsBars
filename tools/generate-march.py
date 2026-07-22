#!/usr/bin/env python3
# Assets for the MARCHING LINES animation module (session 11) — the second animation
# in the plug-in registry (GB.Anims), after Comet Chase.
#
# Same mechanic as Comet Chase (see generate-shine.py): an ANGLE-ONLY texture drawn
# over the icon, spun continuously by SetRotation, clipped by a per-shape RIM MASK so
# only the outline band shows. The engine draws N phase-spaced copies (360/N apart) of
# this one texture, so they read as N evenly-spaced DASHES marching around the rim on
# ANY silhouette. Count + colour + direction are LIVE; the dash shape + band are baked.
#
# WHY ITS OWN RIM MASK (not Comet Chase's <key>-rim.png): the comet band is a WIDE, SOFT
# ~20px glow band — right for a glowing comet, but it turns a dash into a fat soft BLOB.
# A "marching line" must read as a THIN, CRISP dashed track, so we bake a separate,
# much tighter band -> <key>-line.png. Radial thickness ("line vs blob") is set by the
# MASK, not the dash (the dash is bright across all radii); the dash sets the arc length.
#
# The dash itself is a SYMMETRIC angular wedge (a short solid arc with lightly feathered
# ends) — no bright head, no trailing tail. Symmetric ⇒ direction-agnostic, so the engine
# needs no tail-mirroring (unlike the comet).
#
# Output: Media/art/march.png (one shared dash) + Media/art/hand/<key>-line.png (21 thin
# rim masks). Fast (pure PIL). Re-run to retune the dash/band, or after a <key>-base
# changes:  python3 tools/generate-march.py

import glob
import math
import os

from PIL import Image, ImageChops, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
ART = os.path.join(ROOT, "Media", "art")
HAND = os.path.join(ART, "hand")

# --- Dash (shared) ----------------------------------------------------------
# A dash = a short SOLID angular wedge with lightly feathered ends, bright across all
# radii (the line mask crops it to the thin outline band). A NARROW core + tight feather
# reads as a crisp dash segment, not a fat glow. Half-widths are in radians.
DASH_S = 256                    # square canvas; the engine spins it over the icon
HEAD = math.radians(-90)        # dash sits "up" at rest; engine rotation carries it round
DASH_HALF = math.radians(4.5)   # solid half-width of the dash (each side of HEAD)
FEATHER = math.radians(2.5)     # gaussian softening past the solid core → soft dash ends
HOLE = 0.06                     # tiny centre hole (clipped by the line mask anyway)


def make_dash():
    img = Image.new("RGBA", (DASH_S, DASH_S), (255, 255, 255, 0))
    px = img.load()
    c = (DASH_S - 1) / 2.0
    for y in range(DASH_S):
        for x in range(DASH_S):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy) / (DASH_S / 2.0)
            if r < HOLE:
                continue
            ang = math.atan2(dy, dx)
            d = (ang - HEAD) % (2 * math.pi)
            if d > math.pi:
                d = 2 * math.pi - d          # symmetric angular distance from HEAD, [0, pi]
            if d <= DASH_HALF:
                val = 1.0                    # solid core
            else:
                val = math.exp(-((d - DASH_HALF) / FEATHER) ** 2)   # soft ends
            px[x, y] = (255, 255, 255, int(max(0.0, min(1.0, val)) * 255))
    img.save(os.path.join(ART, "march.png"))
    print(f"  dash: {DASH_S}x{DASH_S} narrow wedge "
          f"(core ~{math.degrees(2 * DASH_HALF):.0f} deg) -> Media/art/march.png")


# --- Line masks (per shape) -------------------------------------------------
# A THIN, mostly-crisp band centred on the silhouette outline: dilate + erode by
# LINE_HALF (much smaller than the comet's RIM_HALF), then a light gaussian so the edges
# aren't aliased but stay tight. Reads as a clean line track, not a soft glow band.
LINE_HALF = 4          # half-width of the band each side of the outline (base-canvas px) — THIN
FEATHER_PX = 2.0       # light gaussian softening (keep tight; a big blur re-fattens it)


def make_lines():
    count = 0
    for base_path in sorted(glob.glob(os.path.join(HAND, "*-base.png"))):
        key = os.path.basename(base_path)[: -len("-base.png")]
        base = Image.open(base_path).convert("RGBA")
        a = base.split()[3]                 # silhouette alpha (anti-aliased)
        er, di = a, a
        for _ in range(LINE_HALF):
            er = er.filter(ImageFilter.MinFilter(3))   # erode ~1px/pass → inner edge
            di = di.filter(ImageFilter.MaxFilter(3))   # dilate ~1px/pass → outer edge
        band = ImageChops.subtract(di, er)             # thin band centred on the outline
        band = band.filter(ImageFilter.GaussianBlur(FEATHER_PX))   # light AA only
        white = Image.new("L", base.size, 255)   # WHITE rgb — masks read luminance (API-NOTES §2)
        line = Image.merge("RGBA", (white, white, white, band))
        line.save(os.path.join(HAND, f"{key}-line.png"))
        count += 1
    print(f"{count} thin line masks (~{2 * LINE_HALF}px) written to Media/art/hand/")


if __name__ == "__main__":
    make_dash()
    make_lines()
