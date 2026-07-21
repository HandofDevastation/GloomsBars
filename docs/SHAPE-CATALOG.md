# Gloom's Bars — Shape Catalog (Phase 1, FROZEN 2026-07-20)

> The shaped-glow rebuild is run in three phases (see docs/HANDOFF.md): **(1) freeze this
> catalog → (2) accounting of every Blizzard button visual (docs/EFFECTS-MATRIX.md) → (3)
> systematic per-shape implementation.** This file is Phase 1, FROZEN with Jason 2026-07-20 —
> do not reopen without him. Every effect in Phase 3 is generated from a shape's SINGLE
> silhouette so the icon + glow + ring + sweep + cast fill + flash can't mismatch.

## Core decision
- **Free width/height controls are REMOVED.** Icons are a preset silhouette + one **uniform
  size scale** (scaling preserves aspect → never warps). This retires the aspect-mask /
  nearest-ratio-snapping system (sessions 3–4): its runtime stretching is the root cause of
  the glow/overlay mismatch, and a fixed catalog makes every overlay authorable-perfect.

## The 21 silhouettes
Each silhouette is baked at its exact geometry; Phase 3 generates its full effect set from it.

**1:1 footprint (9):**
| Shape | Count | Note |
|---|---|---|
| Circle | 1 | |
| Square (sharp) | 1 | |
| Rounded square | 3 | curvature: subtle / medium / large (all below full-pill) |
| Hexagon | 1 | pointy-top (existing) |
| Diamond | 1 | rotated square / rhombus |
| Tombstone | 1 | flat bottom, fully rounded top |
| Tombstone inverted | 1 | flat top, fully rounded bottom |

**Elongated — portrait only, at 2:1 AND 3:2 (10):** these carry the plate-extension option
| Shape | per ratio | ×2 ratios |
|---|---|---|
| Square (sharp) | 1 | 2 |
| Rounded square | 3 curvatures | 6 |
| Pill (full semicircle caps) | 1 | 2 |

**Elongated — square (sharp) also in LANDSCAPE, at 2:1 AND 3:2 (2):** no plate extension.

## Decorations (config, layered on the silhouette — NOT new silhouettes)
- **Gradient overlay** — color + adjustable fade start. Available on **ALL 21** shapes
  (1:1 included), like the current version.
- **Plate extension** — a half-height solid color plate with a gradient fading over the
  icon, positioned **top or bottom**. Only on the **10 portrait-elongated** shapes.
  - The plate fills the **remainder of the height so the spell art stays a perfect square**
    (undistorted): plate ≈ 50% at 2:1, ≈ 33% at 3:2. This is the fix to the distortion saga —
    the icon never stretches; the plate provides the elongation.
  - Color/gradient are **user-configurable**; only the structure (position, half-height) is baked.
  - NOT on 1:1 shapes; NOT on the landscape square (a top/bottom plate would squish the short
    axis — if a landscape plate is ever wanted, it would be a left/right plate, deferred).

## Accepted defaults
- **Icons never stretch.** Non-1:1 shapes crop-to-fill (keep the art's aspect, crop the overflow),
  and the existing **Icon zoom slider STAYS** so the user controls how much of the art shows / how
  it's framed inside the silhouette. (Confirmed with Jason 2026-07-20.)
- Rounded-square curvatures stay **below full-pill**; "pill" is the fully-rounded end of the
  elongated rounding spectrum.
- "Fun" shapes beyond the above (e.g. teardrop, shield, octagon) = a later batch; not in the
  frozen core.
