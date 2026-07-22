#!/usr/bin/env python3
# Asset for the SHEEN SWEEP animation module (session 11) — the THIRD animation in the
# plug-in registry (GB.Anims), after Comet Chase + Marching Lines.
#
# Unlike those two (rim effects: an angle-only texture spun around the OUTLINE), sheen
# is a FACE effect: a bright bar that slides diagonally across the whole icon, clipped by
# the icon's OWN silhouette mask (<key>-base.png — already generated; reused as-is). The
# engine tilts it (SetRotation), scales its thickness (SetSize width), and translates it
# (SetPoint offset) under the fixed base mask, so a gleam sweeps the face of any shape.
#
# So this ONE texture is a plain VERTICAL bright bar (a gaussian stripe down the middle,
# full height). Keeping it axis-aligned means the engine's width scale changes only the
# bar's THICKNESS cleanly; the diagonal + travel are applied live. Colour/blend are live.
#
# Output: Media/art/sheen.png. Fast (pure PIL). Re-run only to retune the bar profile:
#   python3 tools/generate-sheen.py
#   (Face masks are the <key>-base.png icon masks — nothing per-shape is generated here.)

import math
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
ART = os.path.join(ROOT, "Media", "art")

SHEEN_S = 256          # square canvas; the engine sizes/tilts/sweeps it over the icon
SHEEN_SIGMA = 15.0     # perpendicular gaussian (px) — the bar's half-thickness feel at width 1


def make_sheen():
    img = Image.new("RGBA", (SHEEN_S, SHEEN_S), (255, 255, 255, 0))
    px = img.load()
    c = (SHEEN_S - 1) / 2.0
    for y in range(SHEEN_S):
        for x in range(SHEEN_S):
            dx = x - c                                  # vertical bar: brightness by horizontal distance only
            val = math.exp(-(dx / SHEEN_SIGMA) ** 2)    # bright core down the middle, soft fade left/right
            px[x, y] = (255, 255, 255, int(max(0.0, min(1.0, val)) * 255))
    img.save(os.path.join(ART, "sheen.png"))
    print(f"  sheen: {SHEEN_S}x{SHEEN_S} vertical bar (sigma {SHEEN_SIGMA:.0f}px) -> Media/art/sheen.png")


if __name__ == "__main__":
    make_sheen()
