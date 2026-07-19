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
| 3 | **`MaskTexture` renders in Midnight** (rounded corners + shaped sweeps depend on it) | ✅ VERIFIED 2026-07-18 — v3 standalone probe (own texture + `CircleMaskScalable` mask, own frame): clean full circle in-game. Note: the icon's baked-in square border stays visible at the circle's flat edges → production must SetTexCoord-zoom past baked borders before masking (spec anticipated this). | `/gb mask` v3 |
| 3b | Why did v2's button-level mask swap show NO change? | ✅ CLOSED 2026-07-18 — `/gb tint` produced a **red, circular icon on ActionButton1**. Root cause: editing an existing MaskTexture's atlas does NOT propagate to an already-rendered texture (even with Remove+Add); a **freshly created mask renders immediately**. ArcUI-overlay theory refuted (tint visible ⇒ the visible icon IS Blizzard's `.icon`). | `/gb tint` |
| 3c | Chat editbox anomaly after `/gb tint` | ✅ CLOSED 2026-07-18 — BugSack: `AddMaskTexture(): Texture already has the maximum number of mask textures (3)`. Tint probe created a new mask every run (no toggle) and hit the **3-mask-per-texture engine cap**; the throw aborted ChatEdit cleanup → undigested input text. Fix: probes are now idempotent toggles. Bonus: the error's Locals dump gave the full button anatomy → [API-NOTES.md](API-NOTES.md) §1. | BugSack |
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
  `/gb` router + probes; .pkgmeta; release workflow; README; CLAUDE.md; this file;
  fonts copied from GloomsAuras; wow-addon-dev skill vendored into docs/).
  - ✅ QA'd in-game: addon loads, `/gb` router works, gates 1–3 + 3b/3c closed.
  - ✅ **END STATE: `/gb round` renders ActionButton1 as a clean, sharp circle**
    (bundled padded mask PNG + zoom crop + slot art hidden) — the differentiator's
    core mechanism fully proven. Remaining known gap: border art returns on press
    (re-assert hooks = Phase 2, by design).
  - GitHub repo live: https://github.com/HandofDevastation/GloomsBars (public,
    HandofDevastation org), release `v0.0.1` published + zip verified. `gh` CLI
    installed + authorized on Jason's machine (account `polaris1976`,
    scopes repo/workflow/read:org).

## NEXT / START HERE (session 2)
Session 1 ended with the round-icon mechanism fully proven (see QA status above);
the mask saga's learnings are all in [API-NOTES.md](API-NOTES.md) §2 — read them
before touching mask/skin code.

**Phase 2 — skin engine v0 (STARTED 2026-07-18, same session):**
1. ✅ Hook-point research (gate 5 CLOSED for action bars): wow-ui-source `live` cloned
   at exactly **12.0.7 build 68453** → findings in [API-NOTES.md](API-NOTES.md) §3
   (UpdateButtonArt is the only slot-art re-shower; press re-show is C-side → use
   SetAlpha(0); zoom never stomped; glow phase hooks `ActionButtonSpellAlertManager`).
2. ✅ Built `Skin.lua` (GB.Skin): applies zoom+circle-mask+slot-art suppression to all
   8 bars; per-button `hooksecurefunc(btn, "UpdateButtonArt")` re-assert; SetAlpha(0)
   for Normal/Pushed; persisted via `GB.db.skinEnabled` (re-applies at PLAYER_LOGIN);
   `/gb skin` toggles. `/gb round` refuses while skin is on (mask-cap safety).
3. ✅ QA'd (2026-07-18): `/gb skin` — all bars round, border STAYS GONE on press
   (SetAlpha(0) + UpdateButtonArt hook strategy confirmed in-game).
4. Jason's noted remaining square offenders: cooldown swipe (addressed next, see 5),
   cast/channel overlay (`SpellCastAnimFrame`), spell-highlight/assisted-rotation
   blue glow (`SpellHighlightTexture`/`AssistedCombatRotationFrame`), plus known
   Highlight/Checked hover states.
5. ✅ QA'd (2026-07-18): **round cooldown sweep** — circular 0.8-alpha swipe on
   `cooldown` + LoC, edge/bling off, `chargeCooldown` untouched. Sweep aligned to the
   icon circle via icon-anchored oversizing + **overshoot 0.75px (QA-confirmed
   default; live-tunable `/gb sweep <px>`, persisted)** — overshoot cures the bright
   AA rim; needed because the sweep isn't clipped by the icon mask.
6. ❌ Masking the state textures FAILED in QA (hover stayed square — API-NOTES §2)
   → ✅ QA'd replacement (2026-07-18): **round state ART** (`Media/art/ring-glow.png`,
   tinted: gold hover / blue checked / red flash). Hover confirmed round in-game.
   **📌 PINNED (Jason): state glows are dimmer than default — color/opacity/intensity
   must become user controls in the Config UI phase.**
7. ⚠ REVISED (2026-07-18): the persistent blue square is **NOT** the rotation-helper
   frame — Jason disabled the rotation assistant and the glow REMAINED. Source says
   it's the **assisted highlight**, rendered by `ActionButtonSpellAlertManager`
   (`Shared/ActionButtonSpellAlerts.lua`) — the SAME system as gold proc glows, just
   with blue `OneButton_Proc*_Flipbook` atlases + alt-glow logic. **It gets
   shape-matched for free in the glow phase** (one manager hook covers procs AND the
   assist highlight). The `StyleAssistedFrame` reskin code stays (styles the
   rotation-helper frame if Jason re-enables that feature; QA deferred).
8. **FLEXIBILITY ARCHITECTURE (Jason's explicit requirement 2026-07-18 — do not
   regress):** the engine must stay flexible on icon shape/size/aspect; circle was
   only the proving ground. Now codified: `GB.SHAPES` registry (each shape = mask +
   swipe + ring PNGs), art generated reproducibly by `tools/generate-art.py` (adding
   a signed-distance function = a new shape), selected via `GB.db.shape` /
   `/gb shape <name>` (applies on /reload — live mask swap trips the no-re-render
   quirk). Shipped: `circle`, `roundrect`. Roadmap: aspect-ratio letterbox entries
   (3:2 = shape art + texcoord math, still pure-skin), per-bar shape selection in the
   Config UI, size/gaps = the §B geometry fork (still optional/later).
9. Next build steps: text styling (fonts stick per §3; colors need hooks), shaped
   cast/channel overlay frames (`SpellCastAnimFrame` etc.), then the glow phase
   (manager hook + shaped glow art — gold procs AND blue assist highlight).
10. ✅ QA'd (2026-07-18): `/gb shape roundrect` + /reload → all 8 bars rounded-rects.
    The shape registry is proven end-to-end.

## ★ DESIGN NORTH STAR (Jason, 2026-07-18) — heavily customized button looks
Jason's mockup: a rounded-rect icon with an **orange gradient plate covering the
bottom ~40%** (opaque at bottom, fading upward into the icon) and the **keybind in
bold white centered ON the plate**. "This is just one example — I want a TON of
flexibility in this; it's the entire point."

Architecture direction: **decoration layers / style recipes.** A button style =
shape + zoom + N decoration layers (gradient plates via native `SetGradient`,
borders, badges — each an OUR-owned texture clipped by its own fresh mask) + text
elements with full position/font/size/color control (re-anchor `.HotKey` etc.).
All pure-skin-safe. The Config UI ultimately edits recipes, not fixed toggles.
Do NOT build one-off hardcoded looks that fight this direction.

## Config UI backlog (Phase 6 — every dev slash-knob becomes a real control)
Jason's explicit expectation (2026-07-18): slash commands are DEV SCAFFOLDING only;
the product gets a full options panel in the GloomsAuras design language (tokens +
fonts already in Core.lua; sliding switches, no native Blizzard widgets,
pixel-perfect; Jason's GloomsAuras Figma mockups = styling reference).
Accumulate every ad-hoc control here:
- Skin enable/disable (now `/gb skin`)
- Icon shape picker (now `/gb shape`; later per-bar)
- Cooldown sweep overshoot (now `/gb sweep`)
- 📌 State-glow styling: color / opacity / intensity per state (hover, checked,
  flash, assist) — Jason: current hover is too dim vs default
- Text styling (fonts/sizes; hotkey color = needs hook, see API-NOTES §3)
- Later: per-bar enable, aspect-ratio, profiles, glow style options (glow phase)

## NEXT (continued)
11. Sometime: test WoWUp install-from-URL **on another machine** (NOT Jason's dev
   machine — WoWUp would clobber the dev symlink).
2. Then Phase 2 (skin engine v0): read the client's `Blizzard_ActionBar*` /
   `ActionButtonTemplate` source for hook points (gate 5) — we now know the exact
   member names to look for (API-NOTES §1). Probe the `showButtonArt` hypothesis.
3. Sometime: test WoWUp install-from-URL **on another machine** (NOT Jason's dev
   machine — WoWUp would clobber the dev symlink). Release `v0.0.1` pipeline already
   verified green (zip contents + version substitution checked 2026-07-18).

## Hard-won LEARNINGS (verified — do NOT rediscover)
- **2026-07-18:** All 8 Edit-Mode bars use the Dragonflight-era global names in
  Midnight 12.0.7 (`ActionButton#`, `MultiBarBottomLeft/BottomRight/Right/LeftButton#`,
  `MultiBar5/6/7Button#`, 12 each). Subregions on `ActionButton1`: `.icon`, `.HotKey`,
  `.Name`, `.Count`, `.cooldown`, `.Border`, `:GetNormalTexture()` — all present.
- **2026-07-18: MaskTexture WORKS in Midnight** (standalone circle probe = clean
  circle). `CircleMaskScalable` atlas exists and masks correctly via `SetAtlas` on a
  MaskTexture. THE differentiator is viable. Icons keep their baked square borders at
  the mask's flat edges → always zoom-crop (`SetTexCoord`) before masking.
- **2026-07-18:** Blizzard's default icon rounding = `.IconMask` (MaskTexture, atlas
  `UI-HUD-ActionBar-IconFrame-Mask`) attached to `.icon` (drawLayer BACKGROUND).
- **2026-07-18: Icon shaping WORKS on live buttons — but only with FRESH masks.**
  `SetAtlas` on Blizzard's already-rendered `IconMask` never re-renders (even after
  `RemoveMaskTexture`+`AddMaskTexture`). Production: always `CreateMaskTexture()` our
  own and `AddMaskTexture` it; never mutate Blizzard's. (Blizzard's own mask stays
  attached — fine, masks intersect.)
- **2026-07-18: What survives Blizzard's update cycle:** masks PERSIST through
  mouseover/updates; icon `SetVertexColor` gets STOMPED (range/usability tinting) —
  color/texcoord styling needs `hooksecurefunc` re-assert hooks (as the spec planned).
- **2026-07-18: For shaped skins, the square slot art must be suppressed:** the dark
  square behind a masked icon = `UI-HUD-ActionBar-IconFrame-Background` slot texture
  (+ the border `NormalTexture`). Replace with our own shaped backdrop in Phase 2/3.
- **2026-07-18:** The visible action button icon IS Blizzard's `.icon` even with ArcUI
  loaded — ArcUI does not overdraw the icon (it styles other elements, e.g. keybinds).
- **2026-07-18: Jason's client runs ArcUI** (+ StoneTweaks, VibeOverlay, BugSack). ArcUI
  restyles action bars — a QA confound and a coexistence question for the product itself
  (icon overdraw ruled out; keybind text styling etc. still ArcUI's).
- **2026-07-18: The `EQOL_ActionBarName` foreign member = EnhanceQoL** (UI-tweak suite).
  Its **"Hide action button borders" toggle was ON during all session-1 probes** — so the
  "default" baseline we observed had `NormalTexture` border art already suppressed by
  EQOL. Jason disabled it (2026-07-18) for a clean baseline. Long-term, Gloom's Bars owns
  border suppression; users should keep EQOL's Button-appearance tweaks off. Coexistence
  test with EQOL re-enabled belongs in late-phase QA.
- **2026-07-18: 3-mask-per-texture engine cap** (`AddMaskTexture` throws at 3) — probes
  and production styling must be idempotent; create ONE mask per icon and reuse.
- **2026-07-18: Full ActionButton anatomy captured** from BugSack locals →
  [API-NOTES.md](API-NOTES.md) §1 (slot art members, three cooldown widgets, proc
  highlight machinery, text members + offsets, `showButtonArt` hypothesis).
- From siblings, already trusted: the secret-values model (GloomsAuras
  docs/API-NOTES.md), the release pipeline (Build Barn ships this exact workflow),
  bundled-font pre-warm fix (GloomsAuras Core.lua).
