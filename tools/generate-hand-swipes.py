#!/usr/bin/env python3
# Derive per-shape COOLDOWN SWIPE textures from the hand-authored -base masks.
#
# The 21 hand silhouettes ship as base/outer/inner PNGs (docs/ART-SPEC.md); the
# cooldown swipe is engine-derived (Blizzard's SetSwipeTexture REJECTS a non-square
# / non-power-of-2 texture -> falls back to a square sweep). So for each <key>-base:
#   1. crop the icon reference rect (a uniform 128px margin on every side),
#   2. resize it to a SQUARE 256x256 (pow2) -- squishing a non-square silhouette is
#      the PRE-DISTORTION: the cooldown frame (anchored to the icon's real aspect)
#      stretches it back so the sweep un-distorts to the true silhouette,
#   3. bake 0.8 alpha inside (matches the SDF swipe_alpha; applySwipe multiplies the
#      user swipeAlpha on top), white RGB so SetSwipeColor tints it cleanly.
#
# Output: Media/art/hand/<key>-swipe.png. Fast (pure PIL). Re-run if a base changes:
#   python3 tools/generate-hand-swipes.py

import glob
import os

from PIL import Image

HAND = os.path.join(os.path.dirname(__file__), "..", "Media", "art", "hand")
MARGIN = 128        # ART-SPEC: icon reference rect centered with a 128px margin all sides
S = 256             # square, power-of-2 swipe
SWEEP = 0.8         # matches generate-art.py swipe_alpha


def main():
    count = 0
    for base_path in sorted(glob.glob(os.path.join(HAND, "*-base.png"))):
        key = os.path.basename(base_path)[: -len("-base.png")]
        base = Image.open(base_path).convert("RGBA")
        w, h = base.size
        ref = base.crop((MARGIN, MARGIN, w - MARGIN, h - MARGIN))
        ref = ref.resize((S, S), Image.LANCZOS)
        a = ref.split()[3].point(lambda v: int(v * SWEEP))
        white = Image.new("L", (S, S), 255)
        swipe = Image.merge("RGBA", (white, white, white, a))
        out = os.path.join(HAND, f"{key}-swipe.png")
        swipe.save(out)
        count += 1
        print(f"  {key}: {w}x{h} base -> {S}x{S} swipe")
    print(f"{count} hand swipes written to Media/art/hand/")


if __name__ == "__main__":
    main()
