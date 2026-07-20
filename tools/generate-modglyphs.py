#!/usr/bin/env python3
"""Render the four Mac modifier glyphs (Cmd/Shift/Ctrl/Option) to white-on-
transparent PNGs, for inline |T...|t display in keybind text (the Mac modifier
style). Uses a macOS system font that carries the glyphs. Run on macOS:

    python3 tools/generate-modglyphs.py     (from the repo root)

Outputs Media/ui/{cmd,shift,ctrl,opt}.png — 128px square, white, alpha = glyph,
each normalized so its bounding box is ~the same visual height (keycap-like), so
they read consistently inline regardless of the glyph's natural size.
"""
import os
from PIL import Image, ImageFont, ImageDraw

FONT = "/System/Library/Fonts/SFNS.ttf"   # San Francisco — the macOS menu-bar glyphs
CANVAS = 128
FILL = 0.76                                # glyph's larger INK dimension as a fraction of the canvas
GLYPHS = {"cmd": "⌘", "shift": "⇧", "ctrl": "⌃", "opt": "⌥"}


def render(ch):
    # Render big, crop to the actual inked pixels (font metrics include whitespace
    # — the caret especially), then normalize by the larger ink dimension and
    # center, so the glyphs read at a consistent weight and sit centered inline.
    big = 220
    tmp = Image.new("RGBA", (big * 2, big * 2), (255, 255, 255, 0))
    ImageDraw.Draw(tmp).text((big * 0.5, big * 0.4), ch,
                             font=ImageFont.truetype(FONT, big), fill=(255, 255, 255, 255))
    bb = tmp.split()[3].getbbox()
    glyph = tmp.crop(bb)
    gw, gh = glyph.size
    scale = (CANVAS * FILL) / max(gw, gh)
    glyph = glyph.resize((max(1, round(gw * scale)), max(1, round(gh * scale))), Image.LANCZOS)
    gw, gh = glyph.size
    img = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 0))
    img.alpha_composite(glyph, ((CANVAS - gw) // 2, (CANVAS - gh) // 2))
    return img


if __name__ == "__main__":
    os.makedirs("Media/ui", exist_ok=True)
    for name, ch in GLYPHS.items():
        render(ch).save("Media/ui/%s.png" % name)
        print("wrote Media/ui/%s.png" % name)
