#!/usr/bin/env python3
# Assets for the rotating shine-chase animation layer (session 10, NEXT #2).
#
# The effect = a bright COMET drawn over the icon, spun continuously, clipped by a
# per-shape RIM MASK so only the part crossing the silhouette's outline shows — as it
# spins, the bright head chases around the rim. Works on ANY silhouette because:
#   * the comet is ANGLE-ONLY (bright at the head angle across ALL radii, fading along
#     a tail) — so wherever the rim sits radially (a pill's caps vs sides), the comet's
#     angular brightness lights it. One shared texture, spun by the engine.
#   * the rim mask is the silhouette's OUTLINE BAND, derived from each <key>-base by
#     subtracting an eroded copy (band width RIM_PX on the base canvas).
#
# Output: Media/art/shine.png (shared comet) + Media/art/hand/<key>-rim.png (21 masks).
# Fast (pure PIL). Re-run if a base changes:  python3 tools/generate-shine.py

import glob
import math
import os

from PIL import Image, ImageChops, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
ART = os.path.join(ROOT, "Media", "art")
HAND = os.path.join(ART, "hand")

# --- Comet (shared) ---------------------------------------------------------
# A compact glowing POINT with a short, dim trailing tail (not a wide wedge). The
# head is a tight gaussian; the tail is a short exponential fade at ~half brightness;
# the leading edge is crisp. Masked to a thin rim, this reads as a bright dot riding
# the edge with a wisp behind it.
COMET_S = 256          # square canvas; the engine spins it over the icon
HEAD = math.radians(-90)   # head points "up" at rest; engine rotation carries it round
CORE = math.radians(11)    # bright head half-width — the glowing point
TAIL_LEN = math.radians(34)  # trailing tail length (exponential)
TAIL_AMP = 0.72            # tail brightness vs the head
LEAD = math.radians(7)     # crisp leading edge (ahead of the head)


def make_comet():
    img = Image.new("RGBA", (COMET_S, COMET_S), (255, 255, 255, 0))
    px = img.load()
    c = (COMET_S - 1) / 2.0
    for y in range(COMET_S):
        for x in range(COMET_S):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy) / (COMET_S / 2.0)
            if r < 0.06:                      # tiny centre hole (clipped by the rim mask anyway)
                continue
            ang = math.atan2(dy, dx)
            delta = (ang - HEAD) % (2 * math.pi)   # 0 at head, growing along the tail (one way)
            if delta <= math.pi:                    # tail side: compact head + short dim tail
                head = math.exp(-(delta / CORE) ** 2)
                tail = TAIL_AMP * math.exp(-delta / TAIL_LEN)
                val = max(head, tail)
            else:                                   # leading side: crisp
                val = math.exp(-((2 * math.pi - delta) / LEAD) ** 2)
            px[x, y] = (255, 255, 255, int(max(0.0, min(1.0, val)) * 255))
    img.save(os.path.join(ART, "shine.png"))
    print(f"  comet: {COMET_S}x{COMET_S} point + tail -> Media/art/shine.png")


# --- Rim masks (per shape) --------------------------------------------------
# A SOFT band centred on the silhouette outline: dilate + erode by RIM_HALF so it
# reaches equally inward and outward (no hard eroded inner edge that pinches at the
# caps), then gaussian-feather so the shine fades softly at both edges → reads as a
# glow, not a hard border. Centring on the outline also blooms it slightly past the
# icon edge (the base canvas has 128px margin, so there's room).
RIM_HALF = 10          # half-width of the band each side of the outline (base-canvas px) — thin edge line
FEATHER = 9            # gaussian softening of the band edges


def make_rims():
    count = 0
    for base_path in sorted(glob.glob(os.path.join(HAND, "*-base.png"))):
        key = os.path.basename(base_path)[: -len("-base.png")]
        base = Image.open(base_path).convert("RGBA")
        a = base.split()[3]                 # silhouette alpha (anti-aliased)
        er, di = a, a
        for _ in range(RIM_HALF):
            er = er.filter(ImageFilter.MinFilter(3))   # erode ~1px/pass → inner edge
            di = di.filter(ImageFilter.MaxFilter(3))   # dilate ~1px/pass → outer edge
        band = ImageChops.subtract(di, er)             # band centred on the outline (~2*RIM_HALF wide)
        band = band.filter(ImageFilter.GaussianBlur(FEATHER))   # soft edges → glow, not border
        white = Image.new("L", base.size, 255)   # WHITE rgb — masks read luminance (API-NOTES §2)
        rim = Image.merge("RGBA", (white, white, white, band))
        rim.save(os.path.join(HAND, f"{key}-rim.png"))
        count += 1
        print(f"  {key}: soft rim band ~{2 * RIM_HALF}px, feather {FEATHER}")
    print(f"{count} rim masks written to Media/art/hand/")


if __name__ == "__main__":
    make_comet()
    make_rims()
