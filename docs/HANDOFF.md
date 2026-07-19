# Gloom's Bars — Session Handoff
**Last updated: end of session 3 (2026-07-19). Current release: v0.2.0. Session 2's Config-UI work
IS committed (`f878fc1`); session 3's icon-sizing work (crop-to-fill + the aspect-correct pill) is
UNCOMMITTED in the working tree — offer to commit at session start. Git history holds the full
narrative; this file is the current-state snapshot. ⇒ Read SESSION 3 then SESSION 2 below.**

> Update this file at the end of EVERY session: what was built, what was QA'd in-game,
> what was learned, what's next. This is the anti-relitigation record — if it's marked
> verified or settled here, do not re-derive it. Deep client facts live in
> [API-NOTES.md](API-NOTES.md) — read §1–§4 before touching mask/skin/glow code.

## How to work with Jason (the owner) — READ THIS
- **Non-developer.** He sets requirements + does in-game QA; Claude writes all code + research.
- **ONE instruction at a time** for testing; never batch QA steps.
- **Verify before claiming** — frame builds as hypotheses; never say it works until confirmed in-game.
- When something misbehaves, ask for the **BugSack error text FIRST** (WoW hides Lua errors).
- UI: **sliding switches** over checkboxes; **no native Blizzard UI** widgets; **pixel-perfect**
  to mocks. Jason's Figma numbers translate 1:1 into recipe values — ask for mockups; the
  figma-desktop MCP tools may allow reading values directly from his file.

## Project & environment
- WoW **Midnight 12.0.7** retail, Interface `120007`. Client at `/Applications/World of Warcraft/_retail_/`.
- Repo root = addon folder, symlinked to `…/Interface/AddOns/GloomsBars`. BugSack installed.
- GitHub: https://github.com/HandofDevastation/GloomsBars (public). Releases: tag push →
  BigWigs packager workflow → GitHub Release → WoWUp installs/updates via repo URL.
  Shipped: v0.0.1, v0.1.0, v0.2.0 (pipeline + zip contents verified). `gh` CLI authorized
  on Jason's machine (account `polaris1976`, scopes repo/workflow/read:org).
- Blizzard UI source for hook research: wow-ui-source `live` branch — clone matched the
  client exactly (commit "12.0.7 (68453)"). Re-clone when the client patches.
- Siblings (read-only reference): GloomsAuras at `/Users/jasonstone/GloomsAuras` (config
  toolkit `Config.lua`, API-NOTES pattern, design tokens), Build Barn at
  `/Users/jasonstone/Desktop/glooms-build-barn` (release recipe).
- Jason's client addon ecosystem (QA context): ArcUI (bars/CDM UI), EnhanceQoL (border
  hiding was ON during early probes — now off), StoneTweaks, VibeOverlay, Platynator
  (nameplates; ships the Lato font), BugSack. Dominos' hotkey styler was found styling
  keybind text — Jason REMOVED it. Late-phase QA: coexistence re-test with these enabled.

## The core idea (do NOT relitigate)
Pure appearance layer over Blizzard's own action buttons. Never replace secure buttons;
never read secret combat values; react to Blizzard's events and restyle Blizzard's
rendered output. Edit Mode owns geometry (the clickable areas). Full rationale: [SPEC.md](SPEC.md).

**Settled decisions (2026-07-18, with Jason — do not reopen):** pure skin v1 (no secure-frame
geometry); bars 1–8 (pet/stance/extra later); standalone (no Masque); slash `/gb` (+
`/gloomsbars`), SavedVariables `GloomsBarsDB`, namespace `GB` → `_G.GloomsBars`.

## ★★ NORTH STAR (Jason, 2026-07-18): USER-AUTHORED styles via a style editor
Jason: "I wanted to build this via the UI myself — not a baked-in recipe. Define the
height and width of the icons (via the UI), overlay a gradient and position it, decide
where the keybind shows up, apply a shape to the overall construction… I want a TON of
flexibility — it's the entire point."
- A button style = **data** (shape, zoom, construction zones, decoration layers, text
  elements with position/font/size/color). The engine (Skin.lua decor pass) interprets
  data; `GB.STYLES` in code is scaffolding/starter-templates ONLY. Real styles live in
  SavedVariables, authored through the **style editor** (the Config UI — next major build).
- Reference look (matched in-game, Jason: "pretty cool"): `plate` — button extends ~40%
  below the icon, orange gradient fades in over the icon's bottom half, solid through the
  extension, keybind bold white centered in the extension, one continuous rounded shape.
- Icon sizing scope: the VISIBLE construction is freely sizable/aspectable (textures are
  not protected). The CLICKABLE hit area is the secure button — Edit-Mode-sized unless the
  spec's §B out-of-combat geometry fork is taken later. The UI must communicate this.

## CURRENT STATE — what's built and QA'd (all verified in-game 2026-07-18)
Files: `Core.lua` (namespace, tokens, `GB.SHAPES`, `GB.STYLES`, saved vars, `/gb` router,
probes), `Skin.lua` (skin + decoration engine), `Glows.lua` (proc glow engine),
`Media/masks|art/` (generated), `tools/generate-art.py` (SDF art generator).

- **Skin engine** (`/gb skin`, persisted): all 8 bars (96 buttons) — icon zoom crop
  (0.08), fresh per-button shape mask, slot art suppressed (`SlotBackground`/`SlotArt`
  Hide + `NormalTexture`/`PushedTexture` SetAlpha(0) — survives press), re-asserted via
  per-button `UpdateButtonArt` hook. ✅ QA'd incl. press cycles.
- **Shape registry** (`GB.SHAPES`: circle, roundrect, square; `/gb shape`, /reload to
  apply): every shape = mask/swipe/ring/glow PNGs from `tools/generate-art.py` (adding a
  shape = one signed-distance function). ✅ QA'd on all three shapes.
- **Cooldown sweeps**: circular 0.8-alpha swipe texture on `cooldown` + LoC widgets
  (charge cooldown untouched — edge-only), edge/bling off, re-anchored to the icon with
  overshoot (default 0.75px, `/gb sweep <px>`, persisted). ✅ QA'd.
- **State art**: hover/checked/flash replaced with `<shape>-ring` art (gold/blue/red
  tints). ✅ Hover QA'd. 📌 Jason: dimmer than default — styling controls required (backlog).
- **Proc glows — THE DIFFERENTIATOR, PROVEN**: `Glows.lua` hooks
  `ActionButtonSpellAlertManager:ShowAlert/HideAlert` + `AssistedCombatManager:
  SetAssistedHighlightFrameShown`; silences Blizzard frames via durable alpha-0; one
  shaped additive pulsing halo per button (gold procs / blue assist). ✅ QA'd: real
  in-combat proc traced the shape on round AND square. Assist-highlight replacement also
  observed working (LOW PRIORITY per Jason — do not iterate on it). 📌 "Hard to see" →
  intensity/styling controls in the editor.
- **Cast/channel overlay**: drain (`CastFill` mask swap), inner glow (art replacement via
  `PlaySpellCastAnim` hook, lime/gold, RING_FIT sizing), `EndBurst` end flash (mask
  swap). ✅ FULLY QA'd on round and square.
- **Decoration engine + construction zones** (`/gb style`, live, persisted): styles as
  data — extension zone below the icon, pooled WHITE8X8 gradient plates (solid+fade
  primitives), keybind override (position/font/size/color, re-asserted via `UpdateHotkeys`
  hook, text container raised). ✅ QA'd against Jason's Figma mock.
- **Text**: Count/Name/HotKey on bundled GeneralSans (sizes/flags/range-coloring kept).
  ✅ Verified via `/gb fontinfo`. Jason finds GeneralSans bland → font picker later, try Khand.

**Dev slash commands** (scaffolding, not product): `/gb skin`, `/gb shape <name>`,
`/gb style <name>`, `/gb sweep <px>`, `/gb debug`, `/gb glowinfo`, `/gb fontinfo`,
`/gb mask`, `/gb maskinfo`, `/gb round`.

## Verification gates
| # | Claim | Status |
|---|-------|--------|
| 1 | 8 bars' button globals = Dragonflight-era names, 12 each | ✅ VERIFIED |
| 2 | Subregions `.icon/.HotKey/.Name/.Count/.cooldown` (+anatomy in API-NOTES §1) | ✅ VERIFIED |
| 3 | MaskTexture renders in Midnight (with the fresh-mask + edge-padding rules, API-NOTES §2) | ✅ VERIFIED |
| 4 | `IsActionInRange`/`IsUsableAction` readable in Midnight combat (custom range tint) | ⚠ UNVERIFIED — not needed so far; Blizzard's own indicators kept working |
| 5 | Blizzard hook points (UpdateButtonArt, alert manager, cast anim, hotkeys…) | ✅ SOURCE-VERIFIED @ exact client build + confirmed in-game via the working hooks (API-NOTES §3) |
| 6 | Proc glows hookable without secret reads | ✅ VERIFIED IN COMBAT — the differentiator is proven |

## Hard-won LEARNINGS (verified — do NOT rediscover; details in API-NOTES)
- **Masks**: fresh masks render; editing a live mask's texture never re-renders; runtime
  attach silently fails on never-rendered never-masked textures (→ replace art instead);
  3-mask-per-texture cap; masks don't clip `SetColorTexture` fills (use WHITE8X8);
  ALL mask/glow art needs transparent edge padding (edge-clamp bleed flattens+blurs);
  `CircleMaskScalable` is NOT usable at button size (scalable/9-slice flattening).
- **Re-assertion map**: `UpdateButtonArt` = only slot-art re-shower (hook it); press
  border re-show is C-side (SetAlpha(0), never Hide); icon texcoord never stomped;
  vertex color stomped by `UpdateUsable` (leave it — Blizzard's usability tint);
  `UpdateHotkeys` re-anchors keybind text (hook it); cooldown swipe textures never re-set.
- **Glow systems**: THREE mechanisms (spell alerts / assisted highlight / rotation
  helper) — all hooked centrally; per-button alert frames, never pooled; assist ants
  flipbook only animates in combat.
- Zoom-crop icons (~0.08) before masking (baked borders at shape tangents).
- Error inside a slash handler leaves typed text undigested in the chat box (check BugSack).
- From siblings: secret-values model (GloomsAuras API-NOTES), release pipeline (Build
  Barn), bundled-font pre-warm (GloomsAuras Core.lua).

## ★ SESSION 2 (2026-07-18 cont.) — THE STYLE EDITOR IS BUILT (`Config.lua`, new file)
`/gb` now OPENS the Config UI (the old dev slash-subcommands still exist under it). Built in
the GloomsAuras family language (flat SQUARED navy chrome, purple Khand headers, orange
carets, sliding toggles, warm orange bottom-glow). Layout: LEFT preview pane · vertical
divider · RIGHT **scrollable** one-open accordion · footer (master Enable toggle + Profile
placeholder). Toolkit ported from GloomsAuras/Config.lua (skinPlate, flatButton, makeToggle,
sliderRow, colorSwatch). Bundled `Media/ui/caret.png` = the orange accordion caret.

**ARCHITECTURE SHIFT (done): a style is DATA in SavedVariables.**
- `GB:GetStyle()` returns `GB.db.styleData` (the active user document); `GB.STYLES` are now
  just starter templates. First run deep-copies `styleData` from the old `GB.db.style` key so
  existing looks carry over (see Core loader).
- Shape scheme: `GB.db.shape` = `"circle"` OR `"corner-<TL><TR><BL><BR>-r<N>"` — 16 per-corner
  on/off patterns × 6 radius levels (r0..r5; r5 = fully round / circle-on-a-square). Legacy
  keys (roundrect / square / unsuffixed `corner-XXXX`) auto-migrate in the Core loader.
- New db fields: `zoom`, `iconW`/`iconH` (absent = auto = Edit-Mode size), `iconLockAspect`,
  `stateColors{hover,selected,flash}`, `stateIntensity`, `styleData`.

**Live-apply engine methods (all in Skin.lua, all QA'd working in-game):**
- `Skin:SetShape(name)` — recreates icon + plate masks FRESH (the mask-re-render quirk),
  re-sets swipe + state-ring art. `Skin:SetZoom(v)` — SetTexCoord. `Skin:SetStateColor/
  SetStateIntensity` — SetVertexColor/SetAlpha on hover/checked/flash art. `Skin:SetIconSize
  (w,h)` — re-anchors the visible icon + every overlay. Construction/decoration edits →
  `Skin:ReapplyDecor` (re-anchor).
- ★ KEY LEARNING: **re-anchoring a live mask (SetPoint) DOES re-clip live** — only the TEXTURE
  swap (SetAtlas/SetTexture) hits the no-re-render quirk. So extension + icon-size changes
  apply live via re-anchor; only SHAPE changes need fresh masks. (Resolved the "verify pending"
  note in API-NOTES §2.)
- ★ GOTCHA (cost a QA round): a `local function` called by an earlier `Skin:` setter must be
  DEFINED ABOVE that setter — a Lua local isn't in scope for definitions above it (bit
  `applyIconSize`, which SetIconSize called → nil).

**Sections WIRED + QA'd in-game:**
- **Shape & icon — COMPLETE:** presets (Circle / Rounded / Square), 4-corner on/off grid,
  Corner radius (6 levels, live), Icon zoom (live), Icon width/height + Lock-aspect (live).
- **State highlights:** hover/selected/flash color swatches + intensity (live).
- **Construction:** extend-below slider (live). **Decoration layers:** one gradient layer —
  on/off, color, fade start (live; edits `styleData`). The PLATE is now UI-authored.

**Preview pane:** a real engine-styled sample button (your slot-1 icon, masked to the current
shape/zoom) + state chips (Idle/Proc/Cooldown/Hover/Selected/Flash) from the same art;
reflects shape/zoom/state/aspect. Does NOT yet render the decoration plate (follow-up).

**STILL STUB sections:** Text · Proc glow (needs Glows.lua wiring) · Bar layout (the GEOMETRY
fork — rows/gap; Edit-Mode-owned; scope decision still OPEN with Jason) · Apply to bars
(per-bar enables — needs engine per-bar support).

**Art gen:** `tools/generate-art.py` now emits 16 patterns × 6 radius levels (`make_corners_sdf`
+ `RADII`) → ~384 corner PNGs. **Generation is SLOW (~4 min, pure Python) — run it in the
background.**

## ★ SESSION 3 (2026-07-19) — ICON-SIZING POLISH DONE (next-step #1 complete, QA'd in-game)
Both halves of the old next-step #1 are built and verified in-game (clean vertical pills on a full
action bar, plate + keybinds inside the pill shape). UNCOMMITTED — offer to commit.

**(a) Crop-to-fill (art no longer stretches).** Resizing to a non-square icon used to stretch the
square spell art. New `Skin:TexCoordFor(w,h)` computes a cover-fit `SetTexCoord` (keep the art's
aspect, crop the overflow); used everywhere the icon texcoord is set (initial, zoom, size). New
`Skin:SetIconFill(mode)` + db `iconFill` ("fill" default / "stretch") + a **"Crop to fill" toggle**
in Shape & icon. Preview matches. ✅ QA'd.

**(b) The clean PILL via aspect-correct masks** (THE deferred masking item — resolved). Two findings
(now in API-NOTES §2): 9-slicing a MaskTexture WORKS in Midnight but CANNOT scale a pill from fixed
padded sources (corner radius locks to the baked arc; small icons collapse to square) — proven, kept
only as the `/gb pill` probe. The solution shipped is **pre-generated aspect masks**: `generate-art.py`
`gen_pills` emits `pill-<t|w>-a<ratioIdx>-r<level>` (8 ratios × 6 radii × 2 orientations = 96 masks,
circular corners, 240/256 padding). Engine: `Skin:AspectMask(w,h)` picks the nearest aspect+orientation
for a NON-square ALL-rounded shape (circle / corner-1111); `maskPlan`/`buildMask` build a fresh mask
only when the plan changes (cache key `rec.maskKey`/`plate.maskKey`), else re-anchor. The mask spans
the whole CONSTRUCTION (icon+extension), so a plated icon is one continuous pill. Square + mixed-corner
shapes keep the plain per-corner masks untouched. Fast regen: `python3 tools/generate-art.py pills`.
✅ QA'd on a full bar (round caps, straight sides, no ovalization; a couple of sizes).

📌 NOW-VISIBLE follow-up (was backlog, now obvious on pills): the **state ring / cooldown sweep / proc
glow overlays are still the base square art** (GROW_RATIO-anchored) → they read oval on a pill. Making
them aspect-aware is the natural next masking task (they'd want the same aspect-mask or a shaped-art
treatment). Also: nearest-aspect snapping (8 ratios) can slightly stretch caps at odd sizes → densify
`PILL_RATIOS` if Jason notices.

## ▶▶ NEXT (session 4) — in priority order
1. **Overlays follow the pill/aspect** (state ring, cooldown sweep, proc glow, cast ring) — currently
   square base art, visibly oval on non-square icons. Biggest visual gap now that pills exist.
2. Wire the remaining stub sections: **Text** (keybind zone/anchor/nudge/font/size/color — the
   engine's `ApplyHotkeyOverride` exists; route it through `styleData.hotkey`), **Proc glow**
   (read Glows.lua first; tint/intensity/width → db), **Apply to bars** (per-bar enable).
3. Render the decoration **plate in the preview pane** (currently shape/zoom/states only).
4. Work the deferred-feedback backlog below (overlay shape/size + width controls, state-
   highlight boldness, flyout border, CUSTOM color picker to replace Blizzard's).
5. Resolve the **Bar-layout scope** decision with Jason (own geometry vs defer to Edit Mode).

## Config UI — deferred feedback (Jason, 2026-07-18, in-game QA of the editor)
Jason chose to defer these to keep wiring the sub-panels; revisit after breadth:
- **Overlays (hover/checked/flash ring, proc glow, cooldown sweep) don't match the
  icon's SIZE or SHAPE.** The state ring anchors to the ICON, not the full plate
  construction (icon+extension), so on a plate it mismatches; and there are no
  size/width controls yet (the mock had them). Needs: anchor overlays to the
  construction, + per-overlay size/width sliders.
- **State highlights too subtle** — the ring art is a soft rim; reads as a color
  overlay, not a bold highlight. Needs bolder art (fuller radial) or a spread/opacity
  control that can exceed the base art's intensity (current intensity slider only dims).
- **Flyout buttons (pet/stance/etc.) keep a square Blizzard background border** at the
  default size — `Suppress()` misses the flyout background art. Identify + suppress it.
- **Color picker is the Blizzard default ColorPickerFrame** — clashes with the family
  look. Build a custom family-styled picker (swatch grid + sliders/wheel).

## Smaller anytime-items
- Aspect-correct mask art for stretched constructions (corner distortion on tall shapes).
- Count/Name per-style overrides; more layer kinds (border, badge, top plate).
- Pet/stance/extra-action/vehicle bars; minimap button + icon art (`## IconTexture`).
- WoWup install test on a second machine (NOT Jason's — would clobber the dev symlink).
- Late-phase: coexistence QA with ArcUI/EQOL re-enabled; `.pkgmeta` externals when libs arrive.
