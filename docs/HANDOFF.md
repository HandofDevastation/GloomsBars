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
| 1 | The 8 bars' button globals are `ActionButton1-12`, `MultiBarBottomLeft/BottomRight/Right/LeftButton1-12`, `MultiBar5/6/7Button1-12` | ⚠ UNVERIFIED | `/gb debug` (built, not yet run) |
| 2 | Button subregions `.icon/.HotKey/.Name/.Count/.cooldown` exist as expected | ⚠ UNVERIFIED | `/gb debug` |
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
  **Nothing has been loaded in-game yet.** Git repo initialized; GitHub repo not yet created.

## NEXT / START HERE (session 2 — or later today)
1. Confirm symlink exists: `…/Interface/AddOns/GloomsBars` → repo root.
2. QA step 1 (ONE step): in-game `/reload`, then `/gb` — expect the purple-prefixed
   command list. If nothing prints, ask for BugSack text.
3. QA step 2: `/gb debug` — record the census results in the table above (gates 1–2).
4. QA step 3: `/gb mask` — do bar-1 icons go round? Record gate 3. `/gb mask` again to undo.
5. Then: create the GitHub repo (HandofDevastation/GloomsBars), push, tag `v0.0.1` to
   prove the release pipeline, test WoWUp install-from-URL.
6. Then start Phase 2 (skin engine v0): read client `Blizzard_ActionBar*` source for
   hook points first (gate 5).

## Hard-won LEARNINGS (verified — do NOT rediscover)
- *(none yet — populate as gates close)*
- From siblings, already trusted: the secret-values model (GloomsAuras
  docs/API-NOTES.md), the release pipeline (Build Barn ships this exact workflow),
  bundled-font pre-warm fix (GloomsAuras Core.lua).
