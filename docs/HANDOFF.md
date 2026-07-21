# Gloom's Bars — Session Handoff
**Last updated: end of session 8 (2026-07-21). ⇒ Read SESSION 8 FIRST — it is a MAJOR pivot (the
"shaped-glow rebuild": free width/height is being REPLACED by 21 hand-authored preset shapes, and the
glow is being rebuilt as a multi-part outer+inner+border system). Then read the new docs it produced —
[SHAPE-CATALOG.md](SHAPE-CATALOG.md) (Phase 1, FROZEN), [EFFECTS-MATRIX.md](EFFECTS-MATRIX.md) (Phase 2),
[ART-SPEC.md](ART-SPEC.md) (the hand-asset spec + naming). Sessions 2–7 below are the still-valid skin/
Config foundation, but the glow/shape parts of them are being superseded by session 8.**

## ▶ FIRST THING NEXT SESSION (session 9): pick up at SESSION 8 → "▶▶ NEXT (session 9)".
Session 8 built + QA'd the ENTIRE shaped-render foundation as a DEV PREVIEW (`/gb handshape <key>`): for any
of the 21 hand shapes, the icon clips to it AND the gradient + border + glow all follow it. Validated
in-game on diamond (pointy) and pill32 with a thick border (round caps, glow clears the border). Jason:
"That works better." **Nothing is mid-flight; the preview works.** The remaining work is turning the preview
into the real thing (wire to triggers, real shape picker, animation) — see the session-8 NEXT list.

## ★★★ SESSION 8 (2026-07-21) — THE SHAPED-GLOW REBUILD (major pivot; all QA'd; UNCOMMITTED until this commit)
A long, decisive session. We reframed the whole shape/glow model, and built + validated the render foundation
in-game as a dev preview. Structured into phases at Jason's request (he wanted a frozen plan, not reactive
feature-chasing — see memory `work-structured-catalog-first`).

**THE PIVOT (settled with Jason, do not reopen):** free width/height sizing produced warped glows/overlays
on stretched shapes (a stretched *round* glow ovals; a pill glow on a square; etc. — no profile tweak fixes
a SILHOUETTE mismatch). So: **free width/height is REMOVED → a fixed catalog of 21 hand-authored preset
shapes + one uniform size scale.** Each shape's icon mask + glow + overlays are cut from ONE silhouette, so
they can't mismatch. Icons never stretch (crop-to-fill; the Icon-zoom slider stays).

**Phase 1 — SHAPE CATALOG, FROZEN → [docs/SHAPE-CATALOG.md].** 21 silhouettes: 1:1 = circle, square,
rounded-square ×3 curvatures (keys `roundsq1/2/3`), hexagon, diamond, tombstone, tombstone-inv; elongated
PORTRAIT at 2:1 & 3:2 = pill, square, rounded-square ×3 (keys `pill32/pill21/square32/square21/roundsqN-32/
roundsqN-21`); square LANDSCAPE at 2:1 & 3:2 (`square32w/square21w`). Gradient overlay on ALL shapes; plate
extension only on portrait-elongated (keeps icon square). Details/defaults in the doc.

**Phase 2 — EFFECTS ACCOUNTING → [docs/EFFECTS-MATRIX.md].** Every Blizzard button visual, pulled from the
client templates + API-NOTES, mapped to what we do. **Surfaced 3 un-handled GAPS** (square art leaking over
shaped icons): `SpellHighlightTexture` (pulsing "press this"), `CooldownFlash` (GCD flipbook), `NewActionTexture`
— plus the known flyout-bg gap. Also documents the DECIDED multi-part glow architecture (below).

**★ Multi-part glow architecture (Jason's design, validated).** Every glow = the SAME 3 parts, differing only
by tint + trigger: **outer glow** (a texture UNDER the icon → perfect outward falloff, the icon hides the
solid centre), **inner glow** (OVER the gradient → tints the interior edge, fades to a clean centre),
**border recolour** (the Border decoration adopts the glow colour). SUPERSEDES the old single soft-bloom +
the separate state ring. One tintable WHITE pair per shape does procs / hover / cast / finish.

**★ Hand-authored assets (Jason makes them in Figma; ALL 21 done, imported to `Media/art/hand/`).** Spec +
naming in [docs/ART-SPEC.md]: per shape, 3 files `<key>-base/-outer/-inner.png`, greyscale/white on
transparent (engine tints). Canvas = a 256-short-side icon reference rect centred in a 128px-margin-all-sides
canvas (1:1 → 512², 3:2 portrait → 512×640, 2:1 → 512×768, landscape swapped). `base` = the icon MASK,
`outer/inner` = the glow. Border + cooldown swipe are engine-derived from the base; state ring is gone.
Jason's originals live at `~/Desktop/gb_assets`; imported+keyed copies in `Media/art/hand/` (63 files).

**★★ HARD-WON LEARNINGS this session (do NOT rediscover):**
- **Mask textures need WHITE rgb, not just alpha.** Figma exports transparent regions as BLACK rgb (0,0,0,0);
  the SDF masks are (255,255,255,0). WoW's `CLAMPTOBLACKADDITIVE` mask reads luminance, so a black-matted base
  **won't clip**. Fix applied: a script forced RGB→255 (alpha untouched) on all `Media/art/hand/*-base.png`.
  If Jason re-exports a base, re-whiten its RGB.
- **The border + gradient were masking to the OLD shape and HID the correctly-clipped icon** — this cost ~6
  debug rounds (everything looked "square" because the border/gradient still drew square). The mask worked all
  along. Lesson: when a hand shape is active, EVERYTHING masked (icon, gradient plate, border) must route to
  the hand base — which is now what `handShapeKey` does.
- **Non-square shapes need PER-AXIS mask/glow growth.** The base's silhouette fills a different FRACTION of the
  canvas per axis (short 0.5, long long/(long+256)), so a uniform border/glow margin flattens a pill's caps.
  `hgAnchor(tex, icon, grow)` compensates per axis (short adds 2·grow, long adds grow·(aspect+1)/aspect) so the
  edge lands exactly `grow` px out on every side; caps stay round. Used for icon (grow 0), border (grow=t), and
  the outer glow grows by the border thickness so a thick border can't bury it.

**Engine wiring (all in this commit):**
- `Skin.lua`: `handShapeKey` (module state) → `maskPlan` sources `hand\<key>-base.png`; `AnchorConstructionMask`
  + `AnchorBorderMask` defer to `hgAnchor` while it's set, so icon + plate + border all mask to the hand shape
  through the PROVEN ApplyDecor rebuild. `Skin:SetHandShape(key)` = set key + ReapplyDecor. `Skin:AnchorHandGrown`
  / `Skin:BorderGrow` expose the anchor + border thickness to the glow engine. `Skin:RecolorBorders(color)` =
  border adopts the glow colour.
- `Glows.lua`: `Glows:HandPreview(shape, color)` draws the multi-part glow (outer BACKGROUND-2 under icon; inner
  on its own frame btn+5 ABOVE the gradient; both BLEND, tinted, pixel-snap off; outer grows by BorderGrow,
  inner +2px to hide the hard-edge seam) + calls RecolorBorders. `Glows:ForceTest`/`SetTestArt` are the older
  glow-bake-off harness (kept).
- `Core.lua`: `/gb handshape <key|off>` (mask icon+border+gradient to the hand shape + glow on — the main
  preview), `/gb handglow <key|off>` (glow only), `/gb glowtest`, `/gb glowstyle 0|A|B|C` (bake-off leftovers).
  `HAND_KEYS` lists the 21.
- `tools/generate-art.py`: `gen_test` + `glow_A/B/C` (the bake-off candidate profiles; `Media/art/gbtest-glow-*`
  — dev scaffolding, can be deleted once the hand glows are wired to triggers).

**Current state:** `/gb handshape <key>` is a full dev preview of the finished look for any of the 21 shapes.
It is NOT yet: (a) wired to real triggers (glow is force-on), (b) selectable in Config, (c) persistent
(handShapeKey is session-only, not saved to db). The old SDF/aspect shape system is still in place underneath;
hand shapes ride ON TOP via handShapeKey.

## ▶▶ NEXT (session 9) — in priority order
1. **Wire the multi-part glow to REAL triggers** — replace the old single-bloom (`Glows.lua` proc engine) +
   the state ring so the outer+inner+border-recolour glow fires on procs (gold), hover/selected (tinted, from
   the state highlight paths), cast (lime), and the finish flash. Currently it's force-on via `HandPreview`;
   make it event-driven and per-shape. This is the payoff (shaped glow on a real proc).
2. **Real shape selection + persistence** — make `handShapeKey` come from `GB.db` (a real setting, applied at
   skin/decor time, surviving /reload), Config picker lists the 21 presets, REMOVE the free width/height
   sliders, add the uniform size scale. Retire/replace the SDF shape path for the icon where it's superseded.
3. **Animation layer** — the rotating-shine chase (Jason misses it): a bright comet masked to the shape's rim,
   rotating; works on any silhouette, cheap (one shared shine texture + a rim mask). Layers on the static glow.
4. **Close the effects-matrix GAPS** — suppress/shape `SpellHighlightTexture`, `CooldownFlash` (GCD flipbook),
   `NewActionTexture`; flyout background (long-deferred).
- Cleanup anytime: delete the `gbtest-glow-*` bake-off assets + `/gb glowstyle`/`glowtest` once triggers are
  wired; the per-axis border assumes the icon aspect matches the shape aspect (true once the shape picker sets
  the aspect — for the dev preview Jason sets a matching icon size by hand).

## ✔ SETTLED (session 7): Blizzard's cooldown EDGE + finish BLING can't be shaped — don't re-attempt.
The cooldown SWEEP follows the shape via its swipe-texture alpha (works). But the rotating EDGE line and the
finish BLING (star) are drawn INTERNALLY by Blizzard's Cooldown widget to the SQUARE frame bounds — no
maskable handle, and `SetEdgeTexture`/`SetBlingTexture` colour args only MULTIPLY their baked gold/blue
textures (never a clean recolour). We also can't draw our own versions: both need the cooldown's REMAINING
TIME (the secret wall). So: edge + bling are SUPPRESSED, and our own shape-masked **finish flash** (fired on
the `OnCooldownDone` event, GCD-filtered by the game clock — never reading the secret duration) replaces the
bling. Decision with Jason: drop the edge, shape the flash. Do NOT re-add Blizzard's edge/bling.

## ✔ SETTLED: per-corner MIXING stays cut for the ICON, but mixed-corner ART is used for OVERLAYS.
Session 5 cut per-corner mixing for the ICON MASK (9-slice had a ~44px short-side floor; do NOT re-attempt
a mixed ICON mask). BUT the full-render mixed-corner PNGs (`corner-<TLTRBLBR>-r<N>`) still exist and are
now USED for OVERLAYS that span a continuous-OFF construction (rounded icon + SQUARE plate): the proc GLOW
and the cast FILL pick `corner-1100` (below-plate) / `corner-0011` (above-plate) so their plate end goes
square. These are soft/whole-image renders, not 9-sliced, so no floor problem. (SESSION 6, `mixedCornerBase`.)

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

**Settled decisions (2026-07-19, session 5 — do not reopen):**
- **Per-corner MIXING is CUT.** Corners are all-or-nothing (Circle / Rounded / Square). Mixed
  rounded/sharp corners on a non-square icon can't render cleanly — do not re-attempt.
- **Hexagon is FIXED-ASPECT** (square only — one "Icon size", no width/height/lock/crop/extension).
- **Positioning/spacing (honeycomb layout) is the out-of-combat GEOMETRY FORK — a real FUTURE phase,
  NOT "never."** Clarified with Jason after I mis-framed it: (1) secure buttons can only be moved OUT
  of combat, and once moved they PERSIST (nothing reverts) — that's a NON-ISSUE, same as most addon
  config; don't keep flagging it. (2) The actual reason it's deferred/meaty is **taint** (moving
  Blizzard's secure buttons can cause "action blocked" errors). (3) v1 is still pure-skin; the fork is
  unbuilt and unscoped. The honeycomb can be built TODAY by hand in Edit Mode (two offset bars).
- **Border = a colored shape-backing** (a shape copy behind the icon, oversized by thickness), works
  for ALL shapes, reuses the masks. Lives in Decoration.

**Settled decisions (2026-07-19, session 6 — do not reopen):**
- **Continuous-OFF only applies with a PLATE on a straight-sided shape.** Circle + hexagon force
  Continuous ON (engine + greyed toggle); with no extension the engine forces it ON too (else the
  gradient plate loses its mask and draws as a square — the hexagon-gradient regression). A circle +
  an extension = a pill.
- **Proc-glow art = a WIDE soft bloom, GLOW_EXTENT 80 / GLOW_SCALE 128÷80.** Reprofiled twice this
  session (peak at the silhouette, wide Gaussian, inward rim-light). Bigger/softer than the old 96.
  The saved glow Size is reset ONCE via the `glowWideBloom` flag (art geometry changed).
- **Proc glow (and any alert-driven overlay) must gate on OUR action buttons only** — Midnight's
  Cooldown Viewer frames ALSO fire the spell-alert manager and their geometry is a SECRET combat value
  (arithmetic on it taints + throws). `Glows.isOurs` (a set from `GB:ForEachButton`) is the gate.
- **Standalone-consume LibSharedMedia** (no embed yet): `GB.GetLSM()` = `LibStub("LibSharedMedia-3.0",
  true)`; we register our bundled fonts into it. Guaranteed present on Jason's client (BugSack et al.
  embed it). Embedding via `.pkgmeta` is a future hardening step for standalone release robustness.

**Settled decisions (2026-07-20, session 7 — do not reopen):**
- **Cooldown edge + finish bling can't be shaped → suppressed; shaped finish flash replaces the bling.**
  (See the ✔ SETTLED block at top.) Drop the edge entirely; the flash is OUR OWN burst on `OnCooldownDone`.
- **The cooldown SWEEP fills the icon; NO overshoot slider.** The old `sweepOvershoot` was really fixing
  Blizzard's UNDERSHOOT (Blizzard insets the cooldown). It's baked at +0.75px (kills the AA rim leak); the
  user slider was removed (`/gb sweep` dev command + db field stay). **Charge cooldowns are now styled too**
  (`btn.chargeCooldown` was edge-only → `SetDrawSwipe(true)` forces the shaped recharge sweep).
- **Availability + range tint = REACT to Blizzard's rendered output, never read the secret.** `UpdateUsable`
  sets the icon vertex (usable 1,1,1 / OOM 0.5,0.5,1 / unusable 0.4,0.4,0.4) → we read THAT (not
  `IsUsableAction`). `ActionButton_UpdateRangeIndicator(self, checksRange, inRange)` HANDS us `inRange` → we
  react (not `IsActionInRange`). Out-of-range = **desaturate then tint** (a clean wash, not a multiply) on the
  icon AND recolour Blizzard's red keybind to the same colour. `computeIconTint` layers them (range > oom >
  unusable > usable). "Unusable" is NARROW: not target/cooldown/range — only wrong form/stance, silence,
  missing secondary resource (untalented = Blizzard-desaturated separately).
- **State-highlight rings: bolder ADD art + a Glow-width (spread) slider.** `ring_alpha` rim now peaks at
  full (1.0) alpha (was ~0.65 → faint); `db.stateWidth` drives the ring's spread via `stateWidthRatio` (was
  the fixed `RING_FIT`). Jason chose the bolder-glow direction (not an opaque ring). The cast inner glow
  SHARES the ring art → its alpha is scaled to 0.65 to keep the QA'd cast look. "Too subtle" is RESOLVED.
- **Config accordion opens ALL-CLOSED** (no default-open section — easier to find the one you want).

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

## CURRENT STATE — what's built and QA'd (base state 2026-07-18; SESSION 5 adds hexagon/border/construction)
> The bullets below are the session-1→4 skin foundation (all verified in-game). **SESSION 5 (above) adds:
> Hexagon shape, Border decoration, bidirectional + continuous construction, and REMOVES per-corner mixing.**
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
  observed working (LOW PRIORITY per Jason — do not iterate on it). ✅ "Hard to see" RESOLVED
  session 6: color/Brightness/Size/Pulse controls + a wide soft bloom (see SESSION 6).
- **Cast/channel overlay**: drain (`CastFill` mask swap), inner glow (art replacement via
  `PlaySpellCastAnim` hook, lime/gold, RING_FIT sizing), `EndBurst` end flash (mask
  swap). ✅ FULLY QA'd on round and square.
- **Decoration engine + construction zones** (`/gb style`, live, persisted): styles as
  data — extension zone below the icon, pooled WHITE8X8 gradient plates (solid+fade
  primitives), keybind override (position/font/size/color, re-asserted via `UpdateHotkeys`
  hook, text container raised). ✅ QA'd against Jason's Figma mock.
- **Text**: Count/Name/HotKey on bundled GeneralSans (sizes/flags/range-coloring kept).
  ✅ Verified via `/gb fontinfo`. ✅ Font picker DONE session 6 (LibSharedMedia dropdown); Count/Name
  per-style overrides still backlog.

**Dev slash commands** (scaffolding, not product): `/gb skin`, `/gb shape <name>`,
`/gb style <name>`, `/gb sweep <px>`, `/gb debug`, `/gb glowinfo`, `/gb fontinfo`,
`/gb mask`, `/gb maskinfo`, `/gb round`.

## Verification gates
| # | Claim | Status |
|---|-------|--------|
| 1 | 8 bars' button globals = Dragonflight-era names, 12 each | ✅ VERIFIED |
| 2 | Subregions `.icon/.HotKey/.Name/.Count/.cooldown` (+anatomy in API-NOTES §1) | ✅ VERIFIED |
| 3 | MaskTexture renders in Midnight (with the fresh-mask + edge-padding rules, API-NOTES §2) | ✅ VERIFIED |
| 4 | `IsActionInRange`/`IsUsableAction` readable in Midnight combat (custom range tint) | ✅ SIDESTEPPED (session 7) — we never CALL them; we react to `UpdateUsable`'s icon vertex + `UpdateRangeIndicator`'s `inRange` arg (Blizzard's rendered output). No secret read; usable/OOM/unusable/out-of-range tints all work in combat |
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

## ★ SESSION 4 (2026-07-19 cont.) — OVERLAYS ASPECT-AWARE + CUSTOM CAST/CHANNEL/INTERRUPT (all QA'd, COMMITTED)
Overlay art follows the pill AND Blizzard's cast visuals are replaced with our own pill-shaped ones.
All committed to `main` (latest `023487e`).
- **Aspect overlay art**: `gen_pills` now also emits per-aspect RING (non-square, `SetTexture` OK) and
  a **SQUARE 256² pow2 pre-distorted SWIPE** — KEY finding: `SetSwipeTexture` REJECTS a non-square /
  non-pow2 texture (→ `GetSwipeTexture()` nil → default rectangle), while `AddMaskTexture` and
  `SetTexture` accept non-square. So the cooldown swipe uses a square pill-squished-by-aspect texture
  that un-distorts when stretched to the (non-square) cd frame. (API-NOTES §2.)
- **Engine**: `aspectBase`/`shapeArt`/`applyShapeArt` (overlay art by CONSTRUCTION aspect, cached by
  `rec.artKey`); `AnchorConstruction(tex,icon,ratio,extraPx)` anchors overlays over icon+extension
  per-axis; state ring uses `RING_FIT` grow (rim reaches the pill edge); cooldown sweep + cast inner
  ring both aspect-aware. ✅ QA'd: hover ring, cooldown sweep, cast ring all follow the pill.
- **Perf**: cast masks moved OFF the size-slider hot path into the `PlaySpellCastAnim` hook (was
  ~192 CreateMaskTexture/tick → choppy). `applyShapeArt` cached. ✅ QA'd smooth.
- **Lock aspect ratio** now PRESERVES the current ratio (`db.iconAspect`, captured on enable) instead
  of forcing square. ✅ QA'd.
- **Proc glow**: soft halo forgives the aspect stretch → reads fine on pills; NO aspect art needed.
  Styling controls (intensity/color/width) = the future Proc-glow Config section.
- **New diagnostics**: `/gb cdinfo`, `/gb castinfo` (+EndBurst anim dump), `/gb borderinfo`, `/gb hunt`
  (arms a scan on the next cast interrupt to name red overlay elements across all buttons).

✅ **DONE — CUSTOM CAST/CHANNEL/INTERRUPT overlays** (`styleCast` + `CastFillOnUpdate` in Skin.lua, all QA'd):
- **Cast/channel FILL**: Blizzard draws `Fill.CastFill` at a FIXED centred square (masking can't enlarge
  it → stays square on a pill), so we SUPPRESS it (alpha-0 forced EACH FRAME in the OnUpdate — its cast
  anim re-drives alpha, so one-shot fails) and draw our OWN linear tint masked to the pill, sized to LIVE
  progress read in the OnUpdate (`UnitCastingInfo` → cast fills up / `UnitChannelInfo` → channel drains /
  neither → hide). Direction/colour/opacity from db (`castDrainDir`/`castFillColor`/`castFillAlpha`).
- **CANCEL/INTERRUPT**: Blizzard's red square = `btn.InterruptDisplay` (child frames `.Base`/`.Highlight`,
  atlas `UI-HUD-ActionBar-Interrupt`; found via `/gb hunt`). We suppress it (alpha-0 each frame) and
  instead REPLAY Blizzard's REAL completion burst — `cast.EndBurst` — tinted red. Key gotchas (all solved):
  Blizzard HIDES the parent `SpellCastAnimFrame` on cancel AND keeps fading it, so we `f.bursting`-force
  `cast:Show()`+`SetAlpha(1)` EVERY FRAME until the burst anim's `OnFinished` fires (not a fixed timer, or
  slowing it cuts it off); tint reset to white each cast so real completions stay gold; speed tunable via
  `setEndBurstSpeed` (scales the anim group's child `SetDuration`, restored to 1× each cast) → `db.
  castInterruptSpeed` (default 0.6×). Interrupt detected by the cast ending before ~85% progress.
- **Cast/channel timing IS readable** (`UnitCastingInfo`/`UnitChannelInfo`) — confirmed working in-game,
  NOT the secret cooldown wall. **`SetSwipeTexture` rejects non-square/non-pow2 textures** (API-NOTES §2).
- **Reads-from-events note**: we poll `Unit*Info` in an OnUpdate + hook `PlaySpellCastAnim`; no secret reads.
- db added: `castFillColor`, `castFillAlpha`, `castDrainDir` (up/down/left/right), `castInterruptColor`,
  `castInterruptSpeed`. ✅ **Config UI DONE session 6** (Cast & channel section).

## ★ SESSION 5 (2026-07-19 cont.) — HEXAGON + BORDER + CONSTRUCTION REWORK; per-corner mixing CUT (UNCOMMITTED)
Everything below is in the WORKING TREE, un-committed (base `edb4ef0`). QA status noted per item.

**Per-corner mixing REMOVED (QA'd — "looks better").** First tried a 9-slice fix for mixed corners: the
`/gb slice` probe PROVED slicing gives clean round corners on big stretched panels, but on real buttons it
hit a hard **~44px short-side FLOOR** (a sliced corner is a FIXED ~1:1 texel size, so it can't fit a small
button — degrades to square) AND the preview never implemented slicing. So the whole slice experiment was
**git-reverted to `edb4ef0`** (Skin/Core/generate-art/Media restored; `SHARP_R` back to 0.04). Then: removed
the Corners 2×2 grid from Config; **Corner radius now applies to ALL corners** and is **shown only for
Rounded** (hidden for Circle/Square; icon controls reflow up). Core loader **normalizes** any legacy mixed
shape (`corner-1100-r3` …) → `corner-1111-r<n>` (all-round pill) on load.

**Hexagon shape (QA'd — "looks fine").** Pointy-top regular hexagon SDF in `generate-art.py` (`sd_hexagon`;
regen one shape via `python3 tools/generate-art.py hexagon` — new single-shape CLI arg). In `GB.SHAPES`.
FIXED-ASPECT: the Hexagon preset forces a SQUARE icon and Config swaps width/height/lock/crop for a single
**Icon size** slider (no radius). Engine guard: `aspectBase` now takes the pill path ONLY for `circle` /
`corner-1111-r*` (parseShape defaults to "1111", which would otherwise send a non-square hexagon down the
pill path) → a hexagon uses the plain mask.

**Border (QA'd — "Looks great").** A colored copy of the shape drawn BEHIND the icon (`btn:CreateTexture`
BACKGROUND, one sublevel under `.icon`), oversized by `thickness` px, masked to the shape at the larger size
(`AnchorBorderMask`) → a rim peeks out around the whole construction. EVERY shape (reuses the mask; no new
art). db `styleData.border = {enabled,color,thickness,alpha}`; Config **Border** group in Decoration
(enable/color/thickness 1–12px/opacity). Live (thickness/size = re-anchor, color/opacity = SetVertexColor).
Rendered in the PREVIEW too.

**Construction rework — bidirectional extension (QA'd — "Looks good") + continuous toggle (BUILT, NOT QA'd).**
Extension is now a SIGNED `construction.extendPct` (< 0 = ABOVE the icon, > 0 = BELOW; a CENTERED slider);
legacy `extendBottomPct` read as +below and superseded on first edit. `ExtensionPct` / `ExtensionHeight`
(magnitude) / `ExtensionAbove` drive direction across the mask, gradient plate, border, overlays, and keybind
(all mirror above/below). **Continuous-shape toggle** (`construction.continuous`, default true): ON = icon +
plate masked as one shape (pill); OFF = icon masked to its OWN shape + the plate is a plain SQUARE rectangle
(rounded icon on a crisp square plate — the gradient's opaque near-edge squares the junction; the border, in
OFF mode, frames the ICON only). Engine: `maskExt = continuous and ext or 0` feeds the icon + border masks;
`maskKey` folds the continuous flag. Extension is DISALLOWED for hexagon (`ExtensionPct` → 0; slider + toggle
greyed). Config: Construction section rebuilt; sections now refresh on open (`ToggleSection`) so the hexagon
lockout reflects the live shape.

📌 **Open follow-ups from session 5:** (a) CONTINUOUS toggle un-QA'd — verify FIRST (top of file). (b) In
continuous-OFF the border frames only the ICON; wrapping the whole square-bottom construction needs a
TWO-PIECE border (offered to Jason, deferred). (c) The PREVIEW still doesn't render the plate/extension
(shape + border only), so a plated construction preview ≠ the bars.

## ★ SESSION 6 (2026-07-19 cont.) — CONFIG WIRING + PROC GLOW + KEYBIND/FONTS + continuous-OFF (UNCOMMITTED, ALL QA'd)
A long session: wired most stub Config sections, made the proc glow fully controllable + fixed its
shape/aspect/taint/pulse, added a real font picker + Mac modifier icons, and closed several continuous-OFF
gaps. Everything below was verified in-game (Jason: "I think we're good"). Base `829a96f`.

**Gradient reliability + direction + fade-start (Skin.lua `ApplyDecor`, all QA'd).**
- **Mask-retry (the original hexagon-gradient bug):** a plate is a fresh WHITE8X8 whose first
  `AddMaskTexture` silently fails (never-rendered quirk, API-NOTES §2) — and a fixed-aspect hexagon never
  changes `maskKey` to retry, so the gradient drew UNMASKED (square). Fix: `rec.plateFresh` → force ONE
  mask rebuild next frame via `C_Timer.After(0)` (`rec.forcePlateMask`), by when the plate has drawn.
- **Unified directional gradient:** one renderer replaces the old extension/else split. `layer.dir`
  (up/down/left/right) picks the solid edge + fade axis; `layer.bleedPct` ("Fade start") = the fade reach
  on EVERY shape (was extension-only — the hexagon fade-start now works). An extension on the solid edge
  still draws as a flat SOLID zone first (the plate look). Config: **Direction** 4-way (`dirRow` toolkit).

**Two-tone + alpha border (Skin.lua border block + Config Decoration, QA'd).** `border.color2` +
`border.gradDir` → `SetGradient` (only the rim shows → a colour transition); one colour = flat. The colour
pickers are alpha-enabled (`colorSwatch(...,withAlpha)` → `{r,g,b,a}`); each stop's alpha × the master
Opacity. Config: **Two-tone** toggle + **Color 2** + **Blend dir**.

**Cast & channel Config section (QA'd).** Wired the db fields from session 4: **Fill color / Opacity /
Direction**, **Interrupt color / Speed**. db-level, engine reads them on the NEXT cast (no live preview —
the preview doesn't animate casts).

**Text / keybind section (QA'd).** `styleData.hotkey` {zone (center/extension), offsetX/Y, size, font,
flags, color} via `ApplyHotkeyOverride` (existing) + `ReapplyDecor`. Config: Custom-keybind master toggle
+ Color/Size/**Font dropdown**/Position (Zone 2-way + X/Y offsets), greyed when off.

**LibSharedMedia font picker (QA'd).** `GB.GetLSM()` consumes the shared LSM; `GB.BUNDLED_FONTS` registered
into it at login (`RegisterMedia`). Config: a **scrollable font-dropdown flyout** (`fontDropdown`/
`fontFlyoutFrame`, FULLSCREEN_DIALOG strata + a click-catcher) listing every LSM font, each row drawn IN
its font. Engine resolves `hotkey.font` via `resolveFont` (LSM name → bundled map → legacy GB.FONT key).

**Mac modifier icons (QA'd, Jason loves it).** Opt-in `styleData.keybindMods == "symbols"`: rewrite the
keybind text's modifier PREFIXES (`s-`/`c-`/`a-`/`m-` = Shift/Ctrl/Alt/Cmd) into inline ⇧/⌃/⌥/⌘ glyph
textures (`|T...|t`), hyphen removed — general (any bind), re-asserted in the `UpdateHotkeys` hook. Glyph
PNGs from NEW `tools/generate-modglyphs.py` (macOS SFNS font → `Media/ui/{cmd,shift,ctrl,opt}.png`).
DECISION: glyphs stay WHITE (`:0` line-height) — Jason tried a coloured/sized variant (`|T...:px:...:r:g:b|t`
reading `GetTextColor`/`GetFont`) and it rendered MASSIVE + he preferred plain white. Don't re-add colour.

**Sliders easier to grab (Config `sliderRow`, QA'd).** The thin thumb was a 5px hit target; now the frame
is a tall full-width hit area with a thin visual track centered, plus **click/drag-anywhere-to-seek**
(cursor→value, snap to step). All sliders benefit.

**Proc glow — fully controllable + many fixes (Glows.lua, all QA'd).** THE differentiator, now tunable +
correct. Config **Proc glow** section: **Proc/Assist color, Brightness, Size, Pulse speed** (db-level,
live via `GB.Glows` setters; preview reflects color/size/brightness on the Proc chip). Fixes, in order:
- **TAINT:** Midnight's Cooldown Viewer frames fire the alert manager too, and their geometry is a SECRET
  value → arithmetic tainted. `isOurs` gates all glow paths to our action buttons (see settled decisions).
- **Shape follows the shape** (`RefreshShape` from `SetShape`; the texture was set once at creation).
- **Aspect + construction:** the halo anchors to the icon CORNERS via `Skin:AnchorOverlay` (=
  `AnchorConstruction`), so it tracks size/aspect AND spans the plate extension (`RefreshSize` from
  `SetIconSize`/`ReapplyDecor`).
- **Pulse:** Brightness was the pulse FLOOR (at 100% floor==peak → no pulse). Now Brightness = PEAK and
  the pulse always dips to `peak × PULSE_DEPTH(0.5)`.
- **Art = soft WIDE bloom** (see settled decisions): GLOW_EXTENT 96→80, GLOW_SCALE 128÷80, wide Gaussian
  `glow_alpha` (peak at the silhouette, inward rim-light). `tools/generate-art.py glows` = fast glow-only
  regen. Reset saved Size once (`glowWideBloom`).
- **Continuous-OFF match (tier 1):** glow uses `Skin:GlowArt()` → the mixed-corner glow (rounded icon end,
  square plate end) so it hugs the square plate. Rounded shapes only; circle/square/hexagon keep their own.

**Continuous-OFF closed gaps (QA'd).** (a) hexagon-gradient regression fixed (force continuous when
ext==0 — see settled decisions). (b) **cast FILL** now uses the same mixed-corner mask (`mixedCornerBase`)
so its bottom squares to the plate. (c) circle forces continuous + toggle greyed.

**New db (Core):** `glow{Color,AssistColor,Intensity(peak),Scale,PulseSpeed}`, `glowWideBloom`,
`BUNDLED_FONTS`, `GetLSM`/`RegisterMedia`. **New styleData:** `hotkey{...}`, `keybindMods`, `border.color2`
/`gradDir`/`color[4]`, `layers[].dir`. **Shared helper:** `Skin.mixedCornerBase()` (continuous-OFF hybrid
pattern) feeds `Skin:GlowArt()` + the cast fill.

📌 **Open follow-ups from session 6:** (a) **aspect proc-glow art** — a stretched non-square icon still
stretches the base round glow (uneven short vs long axis); the soft bloom forgives it and Jason said "good
enough," but true `pill-*-glow` art (like the ring/mask) is the clean fix if he asks. (b) two-piece border
for continuous-OFF (still deferred). (c) preview still doesn't render the plate/extension or the fill
gradient direction (shape/border/glow only). (d) custom family-styled color picker (still Blizzard's).

## ★ SESSION 7 (2026-07-20) — PREVIEW PLATE/EXTENSION + GLOW WIDTH/BOLDER RINGS + COOLDOWN & AVAILABILITY (COMMITTED, ALL QA'd)
A long session. Closed NEXT #1 (preview plate), fixed the "too subtle" highlights, and built the ENTIRE
"Cooldown & availability" Config section. Everything below QA'd in-game (Jason: "That's much better").

**Preview now renders the decoration plate/extension (Config.lua — NEXT #1 DONE, QA'd).** The preview pane
mirrors `Skin.ApplyDecor`: the gradient plate, extension (above/below), directional gradient + fade-start,
continuous ON/OFF, and the border span the whole construction — so Direction/Fade-start/extension now match
the bars. The construction is CENTERED at `PREVIEW_CENTER_Y` (icon shifts as the plate grows, so nothing
floats into the state chips or caption); overlays (ring/cooldown/glow/border) + the caption follow it. Plate
masks use the never-rendered-texture retry (`previewPlateFresh` → `C_Timer.After(0)`), same as the engine.
`anchorPreviewOverlay` + `getPreviewPlate` + `previewExtendPct` are the new preview helpers. `sliderRow`
gained an optional `sub` sub-label param.

**Gradient AUTO-FLIPS with the plate side (Config.lua, QA'd).** Moving the plate across centre (below⇄above)
flips a VERTICAL gradient (up↔down) to keep filling the plate — but ONLY on a genuine side change, so a manual
Direction pick survives same-side tweaks; a horizontal (left/right) gradient is never auto-flipped.

**State Highlights — Glow width + bolder rings (all three files, QA'd; matched Jason's mock screenshot).**
The mock had a **Glow width** slider we were missing (only colours + Intensity existed). `db.stateWidth`
drives `stateWidthRatio` (spread of the hover/selected/flash rings; replaced the fixed `RING_FIT` for state
rings). And the ring ART was too faint at 100% — `ring_alpha` in generate-art.py now peaks at FULL 1.0 alpha
(was ~0.65) over a wider band, so full Intensity is a punchy ADD glow. New fast `gen_rings` regen path;
**196 `-ring.png` regenerated**. The cast inner glow SHARES the ring art → its alpha scaled to 0.65 to keep
its QA'd look. (Jason chose "bolder glow", not an opaque ring. "Finish flash is fine, leave it.")

**Green ground-target reticle suppressed (Skin.lua `Suppress`, QA'd).** The green square that appears while a
ground-target spell is on the cursor = `btn.TargetReticleAnimFrame` (atlas `UI-HUD-ActionBar-Target`, fired by
`UNIT_SPELLCAST_RETICLE_TARGET`). Its `Setup` only `Show()`s + plays a ROTATE anim (never touches alpha), so
`SetAlpha(0)` sticks — sibling of the red `InterruptDisplay`. (NOTE: a gold PULSING glow on a cooldown ability
is a real Blizzard proc — e.g. "Hogstrider" — NOT us; confirmed on default bars.)

**★ Cooldown & availability section — BUILT (was a stub; all QA'd). See the session-7 SETTLED block.**
- **Sweep**: fills the icon shape (baked +0.75px; overshoot slider REMOVED). Sweep colour + opacity. Charge
  cooldowns styled too (`SetDrawSwipe(true)`). `applySwipe`/`Skin:StyleCooldown` (preview reuses it). A
  `ActionButton_UpdateCooldown` hook re-asserts the custom swipe colour after casts (Blizzard resets it).
- **Finish flash**: OUR shape-masked EXPANDING burst (alpha fade + scale-out of the shape glow) on
  `OnCooldownDone`. GCD skipped by the GAME CLOCK — `SetCooldown` hook stamps `GetTime()` (never the secret
  duration), `OnCooldownDone` checks elapsed ≥ `FLASH_MIN_CD` (2.0s); a `gbRunning` flag stops
  `SPELL_UPDATE_COOLDOWN` re-sets from resetting the timer. Hooks BOTH `btn.cooldown` and `chargeCooldown`.
  Toggle + colour; previews via `C:PlayPreviewFlash`. (`setupFinishFlash`/`playFinishFlash`/`hookFlashCooldown`.)
- **Availability**: react to `UpdateUsable`'s icon vertex (`refreshAvailability` reads it, NOT
  `IsUsableAction`). Desaturate-unusable toggle, Unusable tint, Out-of-mana tint. `computeIconTint` is the
  unified tinter (rec.gbDesat tracks OUR desaturation only).
- **Out-of-range**: `ActionButton_UpdateRangeIndicator` hook (Blizzard passes `inRange`) → `refreshRange`.
  Out-of-range = **desaturate then tint** the icon + recolour Blizzard's red keybind to the range colour.
  Toggle + Range colour. Out-of-range wins the priority in `computeIconTint`.

**Accordion opens ALL-CLOSED (Config.lua).** Removed the default-open first section.

**★★ Blizzard source is IN THE CLIENT** (huge for hook research this session): `/Applications/World of
Warcraft/_retail_/BlizzardInterfaceCode` — full FrameXML `.lua`/`.xml` + `Blizzard_APIDocumentationGenerated`
(exact method signatures). Used it to verify `OnCooldownDone`, `SetDrawSwipe`, `SetScaleFrom/To`,
`UpdateUsable`, `UpdateRangeIndicator`, the Cooldown template (edge/bling textures), `TargetReticleAnimFrame`.

📌 **Open follow-ups from session 7:** (a) availability has NO preview (icon-state; tested on real bars) —
could add unusable/OOM/range preview but the chip grid would overflow the construction; (b) charge-cooldown
sweep now DARKENS a still-usable ability (1/2 charges) — Jason accepted it; dial opacity if it bugs him; (c)
out-of-range keybind recolour is a VERTEX override → blends with a custom keybind text colour (fine for
default white); (d) "on cooldown" tint was deliberately SKIPPED (the sweep already shows it).

## ▶▶ NEXT (session 8) — in priority order
1. **Apply to bars** (per-bar enable/disable) — the last major stub Config section; needs engine per-bar
   support. Highest-value remaining capability.
2. **Custom family-styled color picker** — replaces Blizzard's default `ColorPickerFrame`, used by EVERY
   colour control in the editor (a design-language violation that's everywhere). Self-contained UI work.
3. **Aspect proc-glow art** (`pill-*-glow`) for tall icons (soft bloom forgives it; Jason said "good enough").
4. **Two-piece border** for continuous-OFF (frame icon + square plate as one outline).
5. **Bar-layout / geometry-fork scope** decision (out-of-combat; taint).
- Anytime: densify `PILL_RATIOS` if nearest-aspect snapping stretches caps; assist-frame border still base
  art (low priority, Jason: don't iterate); embed LSM via `.pkgmeta` for standalone release robustness;
  coexistence QA with ArcUI/EQOL re-enabled (our `UpdateUsable`/range/icon-vertex work now touches the icon
  tint — watch for conflicts with other button decorators).

## Config UI — deferred feedback (Jason, 2026-07-18, in-game QA of the editor)
Jason chose to defer these to keep wiring the sub-panels; revisit after breadth:
- ✅ **DONE (session 4): overlays now match the pill SHAPE + span the construction** (hover/checked/flash
  ring, cooldown sweep, cast fill/ring/interrupt).
- ✅ **DONE (session 7): the "size/width slider" + "state highlights too subtle"** — State Highlights got a
  **Glow width** slider AND the ring art was made bolder (full-alpha ADD rim). Both resolved.
- **Flyout buttons (pet/stance/etc.) keep a square Blizzard background border** at the
  default size — `Suppress()` misses the flyout background art. Identify + suppress it.
- **Color picker is the Blizzard default ColorPickerFrame** — clashes with the family
  look. Build a custom family-styled picker (swatch grid + sliders/wheel). **(NEXT #2.)**

## Smaller anytime-items
- Aspect-correct mask art for stretched constructions (corner distortion on tall shapes).
- Count/Name per-style overrides; more layer kinds (border, badge, top plate).
- Pet/stance/extra-action/vehicle bars; minimap button + icon art (`## IconTexture`).
- WoWup install test on a second machine (NOT Jason's — would clobber the dev symlink).
- Late-phase: coexistence QA with ArcUI/EQOL re-enabled; `.pkgmeta` externals when libs arrive.
