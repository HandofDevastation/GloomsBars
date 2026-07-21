# Gloom's Bars — Art Spec for hand-authored assets (Figma → PNG)

> For Jason to author the shape/glow PNGs by hand. Every asset for one silhouette shares ONE
> canvas per aspect, with the **icon reference rect centered and a 128px margin all around** for
> glow bloom. The engine anchors every asset the same way (icon rect → the on-screen icon), so as
> long as you draw inside these guides, exports drop straight in. See docs/SHAPE-CATALOG.md for the
> shape list, docs/EFFECTS-MATRIX.md for the glow architecture.

## Canvas dimensions
Icon reference rect short side = **256px**; margin = **128px per side**; canvas = icon rect + 256px each axis.

| Aspect | Icon reference rect (WxH) | **Canvas (WxH)** | Used by |
|---|---|---|---|
| 1:1 | 256 × 256 | **512 × 512** | all 1:1 shapes |
| 3:2 tall (portrait) | 256 × 384 | **512 × 640** | rounded-sq ×3, pill, square |
| 2:1 tall (portrait) | 256 × 512 | **512 × 768** | rounded-sq ×3, pill, square |
| 3:2 wide (landscape) | 384 × 256 | **640 × 512** | square only |
| 2:1 wide (landscape) | 512 × 256 | **768 × 512** | square only |

**In Figma:** make a frame at the Canvas size, drop a centered rectangle at the Icon reference rect
size as a guide (128px gap to every edge), draw the shape/glow against that guide, hide the guide,
export the frame as PNG.

## What to draw — 3 assets per silhouette
All are **greyscale/white on transparent** (RGBA PNG). **Do NOT bake color in** — the engine tints
each one at runtime (procs, hover, cast = the same asset, different tint). Luminance/alpha only.

1. **`<shape>-mask`** — the hard silhouette. Solid **white** shape filling the **icon reference rect**,
   transparent outside, anti-aliased edge. This defines the icon's exact shape (your corners/curvature
   live here). No blur.
2. **`<shape>-glow-outer`** — the shape's silhouette with an **outer glow / blur blooming OUTWARD** into
   the margin, fading to fully transparent before the canvas edge. The interior fill can be dropped
   (the icon covers it) — what matters is the falloff *outside* the icon edge. Your call on blur radius
   / softness / spread.
3. **`<shape>-glow-inner`** — the shape filled with an **inner glow**: brightest at the inner edge,
   fading toward center so the middle stays transparent (interior never fully tints). Clipped to the
   silhouette. Your call on how far it reaches inward.

## What I derive — you do NOT draw these
- **Border** — engine-generated from the mask (the shape scaled up by the thickness slider), so it
  auto-fits every shape and stays user-adjustable. Its color is overridden to the glow color on glow.
- **Cooldown swipe** — technical constraints (power-of-2, pre-distorted for aspect); I generate it
  from your mask. **IMPLEMENTED (session 9):** `tools/generate-hand-swipes.py` crops each `-base`'s
  reference rect (128px margin), squishes to a 256² pow2, bakes 0.8 alpha → `Media/art/hand/<key>-swipe.png`.
  Re-run it if you re-export a base.
- **State ring** — gone; hover/selected/cast reuse `-glow-outer` + `-glow-inner` with a different tint.

## Edge rule (important)
Nothing may touch the canvas edge — the 128px margin exists so the outer glow fades to 0 with room to
spare (a shape/glow that hits the edge gets a hard clamped smear). Keep all pixels inside the margin.

## `-base` masks must be WHITE rgb (not black-matted)
The `-base` PNG is used as a MASK, and WoW's mask reads LUMINANCE — so the transparent regions must be
WHITE `(255,255,255,0)`, not the BLACK `(0,0,0,0)` that Figma exports by default. A black-matted base
**won't clip** (the icon renders full/square). On import we force rgb→255 on every `-base` (alpha
untouched), so you don't have to — but if you re-export a base, it'll be black-matted again and needs
re-whitening. (Only the `-base` cares; the `-outer`/`-inner` glows are tinted textures, black transparent
is fine there.) See docs/API-NOTES.md §2.

## Efficiency option
21 silhouettes × 3 assets = 63 PNGs. Two ways to play it:
- **You make them all** — full control, Figma variants/components make the repetition fast.
- **You make 1–2 reference shapes** (mask + both glows) so I can measure your exact falloff/blur, then
  I replicate that look across all 21 in the generator to match. Least manual work, same look.
- **Hybrid** — you hand-make the shapes whose look you care most about; I generate the rest to match.

Recommend starting with **one** shape (your tall pill, say) end-to-end so we lock the look before
mass-producing — matches the Phase 3 "nail one silhouette first" plan.

## The 21 silhouettes — file naming (VALIDATED pipeline, 2026-07-20)
Each = 3 files: `<key>-base.png`, `<key>-outer.png`, `<key>-inner.png`. Canvas from the table at top.
Square (1:1) + pill32 are DONE and proven in-game (outer under icon + inner over + border recolor,
seam-free). The rest use the identical convention.

| Silhouette | Key | Canvas | Done |
|---|---|---|---|
| Circle | `circle` | 512×512 | |
| Square | `square` | 512×512 | ✓ |
| Rounded square — subtle / med / large | `roundsq1` / `roundsq2` / `roundsq3` | 512×512 | |
| Hexagon | `hexagon` | 512×512 | |
| Diamond | `diamond` | 512×512 | |
| Tombstone (flat bottom, round top) | `tombstone` | 512×512 | |
| Tombstone inverted | `tombstone-inv` | 512×512 | |
| Pill — 3:2 / 2:1 (portrait) | `pill32` / `pill21` | 512×640 / 512×768 | ✓ (32) |
| Square — 3:2 / 2:1 (portrait) | `square32` / `square21` | 512×640 / 512×768 | |
| Rounded sq 1 — 3:2 / 2:1 | `roundsq1-32` / `roundsq1-21` | 512×640 / 512×768 | |
| Rounded sq 2 — 3:2 / 2:1 | `roundsq2-32` / `roundsq2-21` | 512×640 / 512×768 | |
| Rounded sq 3 — 3:2 / 2:1 | `roundsq3-32` / `roundsq3-21` | 512×640 / 512×768 | |
| Square — 3:2 / 2:1 (landscape) | `square32w` / `square21w` | 640×512 / 768×512 | |

= 21 silhouettes × 3 files. Drop them all in the same folder; I pull them into the addon.

