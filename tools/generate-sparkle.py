#!/usr/bin/env python3
# Asset for the SPARKLES animation module (session 11) — the FOURTH animation in the
# plug-in registry (GB.Anims).
#
# Sparkles = N little twinkles scattered at RANDOM spots on the icon face, each fading
# in -> peak -> out then respawning elsewhere (the engine drives lifecycle + placement;
# this file just bakes the star). Clipped by the icon's own silhouette (<key>-base.png,
# reused). One shared star texture, tinted/blended live.
#
# The star = a bright tight CORE + four tapering RAYS along the axes (a classic 4-point
# diffraction-spike twinkle). The engine rotates each instance a random quarter-turn for
# variety. Rays decay to ~0 well inside the canvas edge (transparent padding — §2).
#
# Output: Media/art/sparkle.png. Fast (pure PIL). Re-run only to retune the star:
#   python3 tools/generate-sparkle.py

import math
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
ART = os.path.join(ROOT, "Media", "art")

SPARK_S = 128          # small square canvas (a sparkle is tiny)
CORE_SIGMA = 4.5       # bright central dot
SPIKE_THICK = 1.8      # perpendicular half-thickness of each ray (thin = crisp)
SPIKE_LEN = 15.0       # exponential brightness decay along a ray (px)
SPIKE_AMP = 0.9        # ray brightness vs the core


def make_sparkle():
    img = Image.new("RGBA", (SPARK_S, SPARK_S), (255, 255, 255, 0))
    px = img.load()
    c = (SPARK_S - 1) / 2.0
    for y in range(SPARK_S):
        for x in range(SPARK_S):
            dx, dy = x - c, y - c
            core = math.exp(-(dx * dx + dy * dy) / (2 * CORE_SIGMA * CORE_SIGMA))
            hray = math.exp(-(dy * dy) / (2 * SPIKE_THICK * SPIKE_THICK)) * math.exp(-abs(dx) / SPIKE_LEN)
            vray = math.exp(-(dx * dx) / (2 * SPIKE_THICK * SPIKE_THICK)) * math.exp(-abs(dy) / SPIKE_LEN)
            val = max(core, SPIKE_AMP * hray, SPIKE_AMP * vray)
            px[x, y] = (255, 255, 255, int(max(0.0, min(1.0, val)) * 255))
    img.save(os.path.join(ART, "sparkle.png"))
    print(f"  sparkle: {SPARK_S}x{SPARK_S} 4-point star (core {CORE_SIGMA}px, rays ~{SPIKE_LEN:.0f}px) "
          f"-> Media/art/sparkle.png")


if __name__ == "__main__":
    make_sparkle()
