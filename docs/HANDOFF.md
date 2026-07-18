# Gloom's Bars — Session Handoff  (last updated 2026-07-18, session 1)

> Update this file at the end of EVERY session: what was built, what was QA'd in-game,
> what was learned (especially anything verified against the client), and what's next.
> This is the anti-relitigation record — if it's marked verified or settled here, do not
> re-derive it.

## How to work with Jason (the owner) — READ THIS
- **Non-developer.** He sets requirements + does in-game QA; Claude writes all code + research.
- **ONE instruction at a time** for testing; never batch QA steps.
- **Verify before claiming** — never say it works until confirmed in docs AND in-game;
  frame builds as hypotheses to test.
- **Enable Lua errors during QA** (WoW hides them; silent throws look like "nothing
  happens"). Ask for the **BugSack error text FIRST** when something misbehaves.
- UI: **sliding switches** over checkboxes; **no native Blizzard UI** textures/widgets;
  **pixel-perfect** to any mock. Styling follows **GloomsAuras' design language** —
  Jason has Figma mockups for GloomsAuras as the reference basis.

## Project & environment
- WoW **Midnight 12.0.7** retail, Interface `120007`. Client at
  `/Applications/World of Warcraft/_retail_/`.
- Repo root = addon folder, symlinked to `…/Interface/AddOns/GloomsBars`.
- BugSack + !BugGrabber are installed in the client (confirmed 2026-07-18).
- GitHub: HandofDevastation org (same as siblings). Releases via tag push →
  BigWigs packager → GitHub Release → WoWUp.
- Siblings for reference (read-only): GloomsAuras at `/Users/jasonstone/GloomsAuras`
  (config toolkit, API-NOTES.md, HANDOFF pattern), Build Barn at
  `/Users/jasonstone/Desktop/glooms-build-barn` (release recipe).

## The core idea (do NOT relitigate)
Pure appearance layer over Blizzard's own action buttons. Never replace secure buttons;
never read secret combat values; react to Blizzard's events and restyle Blizzard's
rendered output. Edit Mode owns geometry. Full rationale: [SPEC.md](SPEC.md).

**The differentiator:** shape-matched proc glows + cooldown sweeps that follow rounded /
3:2 icons (every other restyle addon leaves square glows on rounded icons). Approach:
baked shape-matched glow art + MaskTexture clipping, triggered by Blizzard's
`SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` events (combat-safe).

## Settled decisions (2026-07-18, with Jason — do not reopen)
1. **Pure skin v1** — no sizing/gaps; Edit Mode owns all geometry. Geometry = possible later phase.
2. **Bars 1–8 in v1** — pet/stance/extra-action/vehicle-leave later.
3. **Standalone** — no Masque.
4. **Slash `/gb`** + alias `/gloomsbars`; SavedVariables `GloomsBarsDB`; namespace `GB` → `_G.GloomsBars`.

## Verification gates (⚠ unproven — probe in-game before building on them)
| # | Claim | Status | Probe |
|---|-------|--------|-------|
| 1 | The 8 bars' button globals are `ActionButton1-12`, `MultiBarBottomLeft/BottomRight/Right/LeftButton1-12`, `MultiBar5/6/7Button1-12` | ✅ VERIFIED 2026-07-18 in-game — 12/12 on all 8 bars | `/gb debug` |
| 2 | Button subregions `.icon/.HotKey/.Name/.Count/.cooldown` exist as expected | ✅ VERIFIED 2026-07-18 — all found on ActionButton1, plus `.Border` + `:GetNormalTexture()` | `/gb debug` |
| 3 | **`MaskTexture` renders in Midnight** (rounded corners + shaped sweeps depend on it) | ⚠ UNVERIFIED | `/gb mask` (built, not yet run) |
| 4 | `IsActionInRange` / `IsUsableAction` readable in Midnight combat (custom range tint) | ⚠ UNVERIFIED | later probe; fallback = restyle Blizzard's own indicator |
| 5 | Exact Blizzard action-button/cooldown hook points | ⚠ UNVERIFIED | read client `Blizzard_ActionBar*` source (as done for CDM in GloomsAuras) |
| 6 | `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` still fire as plain events in Midnight | ⚠ UNVERIFIED | probe in glow phase |

## Build phases (≈ one session each)
1. **[CURRENT] Skeleton + probes** — TOC/Core, `/gb debug` (button census), `/gb mask`
   (MaskTexture render check). ✅ code written 2026-07-18; ❌ NOT yet QA'd in-game.
2. **Skin engine v0** — hook Blizzard's button-update path; restyle hotkey/name/count
   fonts (easiest win, combat-safe) + hide default border art. First visible product.
3. **Icon shape engine** — 3:2 crop + zoom via `SetTexCoord`; rounded corners via
   MaskTexture with bundled rounded-rect mask PNGs.
4. **Cooldown restyle** — `SetSwipeColor`, `SetDrawBling(false)`, edge; masked swipe
   matching the icon shape; restyle the countdown font (Blizzard's own — never draw ours).
5. **Shape-matched proc glows (THE differentiator)** — hook the overlay-glow show/hide,
   substitute baked shaped glow art (rounded-rect + circle), halo/shine/pulse animations.
6. **Config UI** — GloomsAuras-style panel (toolkit port), per-bar toggles, profiles.
7. **Later / optional** — keybind styling extras, hover-to-bind, pet/stance/extra bars,
   per-icon sizing+gaps (the §B geometry fork), minimap button + icon art.

## What's BUILT + QA status
- **Session 1 (2026-07-18):** repo scaffolded (TOC, Core.lua w/ tokens + saved vars +
  `/gb` router + 2 probes; .pkgmeta; release workflow; README; CLAUDE.md; this file;
  fonts copied from GloomsAuras; wow-addon-dev skill vendored into docs/).
  - ✅ QA'd in-game: addon loads, `/gb` command list prints, BugSack clean.
  - ✅ QA'd in-game: `/gb debug` census — gates 1–2 closed (see table).
  - GitHub repo live: https://github.com/HandofDevastation/GloomsBars (public,
    HandofDevastation org). `gh` CLI installed + authorized on Jason's machine
    (account `polaris1976`, scopes repo/workflow/read:org).

## NEXT / START HERE (session 2 — or later today)
1. QA step: `/gb mask` — do bar-1 icons go round? Record gate 3 (THE differentiator
   gate). `/gb mask` again to undo.
2. Confirm the `v0.0.1` release pipeline ran green (Actions tab / `gh run list`),
   then have Jason test WoWUp install-from-URL with the repo URL.
3. Then start Phase 2 (skin engine v0): read client `Blizzard_ActionBar*` source for
   hook points first (gate 5).

## Hard-won LEARNINGS (verified — do NOT rediscover)
- **2026-07-18:** All 8 Edit-Mode bars use the Dragonflight-era global names in
  Midnight 12.0.7 (`ActionButton#`, `MultiBarBottomLeft/BottomRight/Right/LeftButton#`,
  `MultiBar5/6/7Button#`, 12 each). Subregions on `ActionButton1`: `.icon`, `.HotKey`,
  `.Name`, `.Count`, `.cooldown`, `.Border`, `:GetNormalTexture()` — all present.
- From siblings, already trusted: the secret-values model (GloomsAuras
  docs/API-NOTES.md), the release pipeline (Build Barn ships this exact workflow),
  bundled-font pre-warm fix (GloomsAuras Core.lua).
