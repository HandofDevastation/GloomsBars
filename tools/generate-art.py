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
GLOW_EXTENT = 96.0     # glow art: shape edge inset so the halo fits OUTSIDE it


# --- signed-distance functions (negative = inside) --------------------------

def sd_circle(px, py, extent=EXTENT):
    return math.hypot(px, py) - extent


def sd_roundrect(px, py, extent=EXTENT):
    corner = extent * 0.25
    qx = abs(px) - (extent - corner)
    qy = abs(py) - (extent - corner)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - corner


def sd_square(px, py, extent=EXTENT):
    # A crisp square: the roundrect SDF with a token corner (~1px at button
    # scale) so the silhouette anti-aliases cleanly.
    corner = extent * 0.04
    qx = abs(px) - (extent - corner)
    qy = abs(py) - (extent - corner)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - corner


def sd_hexagon(px, py, extent=EXTENT):
    # POINTY-TOP regular hexagon (a vertex at top & bottom) for honeycomb grids.
    # Circumradius = extent so the top/bottom vertices reach ±extent (fills the
    # padded canvas vertically); apothem = extent*cos(30°) is the flat left/right
    # edges (so it's ~13% narrower than tall — a regular hexagon). A convex
    # polygon's SDF is the max of its edge-normal half-plane distances; the three
    # abs() pairs cover the six edges. Exact on the edges — fine for AA + glow.
    a = extent * 0.8660254                          # apothem (center → flat edge)
    d1 = abs(px) - a                                # left / right vertical flats
    d2 = abs(0.5 * px + 0.8660254 * py) - a         # the two upper/lower-right slants
    d3 = abs(0.5 * px - 0.8660254 * py) - a         # the two upper/lower-left slants
    return max(d1, d2, d3)


# Per-corner rounding (Jason's ask, 2026-07-18): each corner is independently
# ROUND or SHARP, all rounded corners sharing one radius. This is the iq
# rounded-box SDF with the corner radius chosen per quadrant. The straight
# edges sit at ±extent regardless of corner radius, so corners with different
# radii still join on a continuous silhouette (no seam). tl/tr/bl/br are bools.
ROUND_R = 0.25   # rounded-corner radius, as a fraction of extent
SHARP_R = 0.04   # "sharp" is a ~1px token arc so it anti-aliases like `square`

def make_corners_sdf(tl, tr, bl, br, round_r=ROUND_R):
    def sdf(px, py, extent=EXTENT):
        rt = lambda on: extent * (round_r if on else SHARP_R)
        if px >= 0:
            r = rt(tr) if py < 0 else rt(br)
        else:
            r = rt(tl) if py < 0 else rt(bl)
        qx = abs(px) - extent + r
        qy = abs(py) - extent + r
        return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r
    return sdf


SHAPES = {
    "circle": sd_circle,
    "roundrect": sd_roundrect,
    "square": sd_square,
    "hexagon": sd_hexagon,
}

# 16 per-corner on/off patterns × 4 radius levels → "corner-<TL><TR><BL><BR>-r<N>".
# The Config UI's four corner toggles pick the pattern; the radius slider picks
# the level. corner-1111-r* == roundrect at that radius, corner-0000-r0 == square.
RADII = [0.12, 0.25, 0.42, 0.62, 0.82, 1.0]   # radius levels r0..r5; r5 == fully round (a square becomes a circle)
for _lvl, _rr in enumerate(RADII):
    for _bits in range(16):
        _tl, _tr, _bl, _br = (_bits >> 3) & 1, (_bits >> 2) & 1, (_bits >> 1) & 1, _bits & 1
        SHAPES["corner-%d%d%d%d-r%d" % (_tl, _tr, _bl, _br, _lvl)] = make_corners_sdf(_tl, _tr, _bl, _br, _rr)


# --- alpha profiles ---------------------------------------------------------

def mask_alpha(d):
    return 1.0 if d <= 0 else 0.0          # supersampling anti-aliases the edge


def swipe_alpha(d):
    return 0.8 if d <= 0 else 0.0          # Blizzard-like sweep darkening


def glow_alpha(d):
    # Proc-glow halo: peaks just outside the shape edge, blooms outward ~20px,
    # bleeds gently inward over the icon rim. Ends by +23 (96+23 < 120: padded).
    if d >= 23:
        return 0.0
    return min(1.0, 0.9 * math.exp(-((d - 3) / 8.0) ** 2))


def ring_alpha(d):
    if d >= 0:
        return 0.0
    fill = 0.20 if d <= -14 else max(0.0, 0.20 * (-d - 6) / 8)
    ring = 0.60 * math.exp(-((d + 8) / 5.0) ** 2)
    return min(1.0, fill + ring)


# --- PNG writer -------------------------------------------------------------

def render(sdf, profile, W=SIZE, H=SIZE):
    # sdf is evaluated in centered coordinates (origin at the canvas center).
    rows = []
    for y in range(H):
        row = bytearray([0])               # filter type 0 per scanline
        for x in range(W):
            acc = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px = (x * SS + sx + 0.5) / SS - W / 2.0
                    py = (y * SS + sy + 0.5) / SS - H / 2.0
                    acc += profile(sdf(px, py))
            row += bytes((255, 255, 255, round(acc * 255 / (SS * SS))))
        rows.append(bytes(row))
    return rows


def write_png(path, rows, W=SIZE, H=SIZE):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path)


# --- aspect-correct pill / rounded-rect masks -------------------------------
# The single square masks above OVALIZE when stretched onto a non-square icon
# (docs/HANDOFF §1b). These are generated at a range of aspect ratios with
# genuinely CIRCULAR corners, so the engine can pick the nearest aspect and
# stretch it to the icon with the corners staying round — a clean pill at full
# radius. Short axis = 128 texels (shape spans 120, 4px pad = the 240/256 rule);
# long axis = 128 * ratio. Corner radius = RADII[level] * 60 (half the shape's
# short side), so r5 == full semicircle caps == pill.
PILL_SHORT = 128
PILL_PAD_RATIO = 8 / 256          # keep the 240/256 edge-padding ratio on BOTH axes
PILL_SHORT_HALF = PILL_SHORT / 2 * (1 - 2 * PILL_PAD_RATIO)   # 60: shape half-extent, short axis
PILL_RATIOS = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0]


def sd_roundrect_wh(px, py, hw, hh, r):
    # Centered rounded rect: half-width hw, half-height hh, circular corner radius r.
    qx = abs(px) - (hw - r)
    qy = abs(py) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def gen_pills():
    # Each aspect/radius/orientation gets the icon MASK, the cooldown SWIPE (0.8
    # fill), and the state RING (rim glow) so overlays match the pill instead of
    # ovalizing. (The proc GLOW halo needs more canvas headroom than the 128 short
    # axis allows — generated separately when that overlay is wired.)
    S, pad = 256, 1 - 2 * PILL_PAD_RATIO
    for ai, ratio in enumerate(PILL_RATIOS):
        longd = round(PILL_SHORT * ratio)
        long_half = longd / 2.0 * pad                         # per-axis padding → uniform 240/256
        for lvl, frac in enumerate(RADII):
            r = frac * PILL_SHORT_HALF                        # r5 → 60 → semicircle caps
            # Non-square MASK + RING — AddMaskTexture / SetTexture accept non-square.
            for orient, W, H, hw, hh in (
                ("t", PILL_SHORT, longd, PILL_SHORT_HALF, long_half),   # tall: short = width
                ("w", longd, PILL_SHORT, long_half, PILL_SHORT_HALF),   # wide: short = height (transpose)
            ):
                rr = min(r, hw, hh)
                sdf = lambda px, py, hw=hw, hh=hh, rr=rr: sd_roundrect_wh(px, py, hw, hh, rr)
                base = f"pill-{orient}-a{ai}-r{lvl}"
                write_png(f"Media/masks/{base}.png",    render(sdf, mask_alpha, W, H), W, H)
                write_png(f"Media/art/{base}-ring.png", render(sdf, ring_alpha, W, H), W, H)
            # SQUARE (256², power-of-2) pre-distorted SWIPE — SetSwipeTexture rejects
            # a non-square / non-pow2 texture (→ nil → default rectangle), so bake the
            # pill squished by the aspect into a square; stretched to the non-square
            # cooldown frame it un-distorts into a clean pill sweep.
            fhw, fr = 0.5 * pad, frac * 0.5 * pad
            tsw = lambda px, py, ratio=ratio, fhw=fhw, fr=fr: sd_roundrect_wh(px / S, (py / S) * ratio, fhw, (ratio / 2.0) * pad, min(fr, fhw))
            write_png(f"Media/masks/pill-t-a{ai}-r{lvl}-swipe.png", render(tsw, swipe_alpha, S, S), S, S)
            wsw = lambda px, py, ratio=ratio, fhw=fhw, fr=fr: sd_roundrect_wh((px / S) * ratio, py / S, (ratio / 2.0) * pad, fhw, min(fr, fhw))
            write_png(f"Media/masks/pill-w-a{ai}-r{lvl}-swipe.png", render(wsw, swipe_alpha, S, S), S, S)


def gen_shape(name, sdf):
    write_png(f"Media/masks/{name}.png", render(sdf, mask_alpha))
    write_png(f"Media/masks/{name}-swipe.png", render(sdf, swipe_alpha))
    write_png(f"Media/art/{name}-ring.png", render(sdf, ring_alpha))
    glow_sdf = lambda px, py, s=sdf: s(px, py, GLOW_EXTENT)
    write_png(f"Media/art/{name}-glow.png", render(glow_sdf, glow_alpha))


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "pills":
        gen_pills()   # fast: only the aspect masks, not the ~384 corner PNGs
    elif len(sys.argv) > 1 and sys.argv[1] in SHAPES:
        gen_shape(sys.argv[1], SHAPES[sys.argv[1]])   # fast: one named shape (e.g. "hexagon")
    else:
        for name, sdf in SHAPES.items():
            gen_shape(name, sdf)
        gen_pills()
