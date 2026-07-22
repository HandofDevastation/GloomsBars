#!/usr/bin/env python3
# Asset for the RADAR SWEEP animation module (session 11) — the EIGHTH animation in the
# plug-in registry (GB.Anims), reimagining the catalog's weak "full-glow spin" as a
# scanner/clock-hand sweep.
#
# Same mechanic as Comet Chase (generate-shine.py): an ANGLE-ONLY texture spun over the
# icon by SetRotation and clipped by a mask. But where the comet is a compact bright POINT
# clipped to the thin RIM, this is a WIDE wedge — a crisp leading edge with a long fading
# trail behind it — clipped to the icon's whole FACE (<key>-base.png, reused). Spinning, it
# reads as a glowing beam sweeping across the button with the trail fading behind it.
#
# Full brightness across all radii (the face mask contains it), fading to transparent at
# the canvas edge so rotation never clamp-bleeds (§2). Colour/spin/blend are live.
#
# Output: Media/art/radar.png. Fast (pure PIL). Re-run only to retune the wedge:
#   python3 tools/generate-radar.py

import math
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
ART = os.path.join(ROOT, "Media", "art")

RADAR_S = 256
HEAD = math.radians(-90)     # bright leading edge points "up" at rest; engine rotation carries it round
TRAIL = math.radians(135)    # fading sweep arc BEHIND the head (the rest of the circle is dark)
GAMMA = 1.35                 # trail falloff shape (>1 = brighter near the head, quicker fade toward the tail)
HOLE = 0.05                  # tiny centre hole (avoids a hot hub; clipped by the face mask anyway)
EDGE0, EDGE1 = 0.90, 1.0     # radial fade band → transparent canvas edge (no clamp bleed on spin)


def make_radar():
    img = Image.new("RGBA", (RADAR_S, RADAR_S), (255, 255, 255, 0))
    px = img.load()
    c = (RADAR_S - 1) / 2.0
    for y in range(RADAR_S):
        for x in range(RADAR_S):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy) / (RADAR_S / 2.0)
            if r < HOLE or r > EDGE1:
                continue
            ang = math.atan2(dy, dx)
            delta = (HEAD - ang) % (2 * math.pi)   # 0 at the head, growing backward along the trail
            if delta > TRAIL:                       # ahead of the head / past the tail → dark (crisp leading edge)
                continue
            val = (1 - delta / TRAIL) ** GAMMA
            if r > EDGE0:                           # soft transparent padding at the canvas rim
                val *= max(0.0, (EDGE1 - r) / (EDGE1 - EDGE0))
            px[x, y] = (255, 255, 255, int(max(0.0, min(1.0, val)) * 255))
    img.save(os.path.join(ART, "radar.png"))
    print(f"  radar: {RADAR_S}x{RADAR_S} wedge (trail ~{math.degrees(TRAIL):.0f} deg) -> Media/art/radar.png")


if __name__ == "__main__":
    make_radar()
