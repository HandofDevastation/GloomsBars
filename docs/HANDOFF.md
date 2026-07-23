# Gloom's Bars — Session Handoff
**Last updated: end of session 13 (2026-07-22). ⇒ Read SESSION 13 FIRST. A MASSIVE fully-QA'd session
(~12 commits): the name-text override (4th Text chip), flyout member skinning (the last square art),
the ENTIRE PROFILES ARCHITECTURE (profiles → whole-look presets → per-bar assignment, per-character
active), and the ENTIRE BAR-LAYOUT PHASE (Layout.lua: size/gaps/grid/orientation/count/visibility/
empty-collapse/position with drag+nudge+coords/quick-keybind launcher). TWO DIRECTION CHANGES from
Jason mid-session — read them before anything else: (1) **NEVER say "v1"/"later phase"** — "we're
building the addon; when it's done, it's done"; bar layout was committed roadmap, and it's now BUILT.
(2) **No engine jargon in UI text or chat** ("ownership" meant nothing to him — name controls by their
visible labels). Sessions 2–12 remain the valid foundation; the FROZEN docs [SHAPE-CATALOG.md](SHAPE-CATALOG.md) /
[EFFECTS-MATRIX.md](EFFECTS-MATRIX.md) / [ART-SPEC.md](ART-SPEC.md) still apply.**

## ▶ FIRST THING NEXT SESSION (session 14): nothing broken or mid-flight — all committed + QA'd.
Jason's parting note: he wants **cosmetic tweaks to the Bar layout section's arrangement** — "largely
cosmetic", he'll direct. Open items, none blocking:
- **Pending Jason decisions:** (a) relabel the "Default" mode to **"Blizzard"** across Visibility/Name/etc.
  (offered when he asked what Default means — no answer yet); (b) rewrite **CLAUDE.md** — its "pure skin
  v1 / settled decisions" block is NOW STALE (layout is built, profiles exist, no-v1 rule) — offered, not
  yet approved; (c) a **release tag** (last shipped v0.2.0; sessions 9–13 unshipped).
- **Deferred/roadmap:** force-SHOW for empty buttons (only Default/Hidden shipped — force-show fights
  Blizzard's secure SetShown in UpdateShownButtons; needs an Edit-Mode-API write or accepted taint,
  research before building); flyout members don't get hover glows (Glows wires bars only — fine, revisit);
  the flyout ARROW stays Blizzard (effects-matrix: leave/revisit); per-bar "text scale" compensation
  (offered, advised against); GA-style sliding switch for the quick-keybind checkbox (partial reskin
  shipped, Jason satisfied for now).
- **Watch-items:** green equipped-border fix + finish-flash over long rotations (both from s12, no repro);
  **NiceDamage restyles HotKey/Count fonts** (discovered via /gb fontinfo — it beats our text styling;
  if Jason reports keybind/count styling "not taking", that's why — a bar-text ownership talk someday);
  mid-combat Edit-Mode paths can transiently fight the combat-visibility state driver (rare, self-heals
  at the next combat edge).

## ★★★ SESSION 13 (2026-07-22) — NAME TEXT + FLYOUTS + PROFILES + THE WHOLE LAYOUT PHASE. ALL QA'd.
Commits: `f9f0bf3` (name override), `0188cd6` (flyout members), `f02d65b`/`a533bd9` (profiles 1+2),
`c64ba25`/`f3f138f` (per-button preset resolution 3a + 3b/3c/fixes), `a88d459` (layout L1+L2),
`051efd6` (visibility/empty/sliders/neg-gaps), `8812299` (position L3), `3455d03` (quick keybind L4).

### PART A — Macro-name override (`f9f0bf3`): the 4th Text chip. THREE modes: **Default / Custom / Hidden**
(mode row, not a toggle — Jason caught that off just meant "Blizzard style", not "gone"). ApplyNameOverride
mirrors the count block (zones bottom/center/plate, offsets, LSM font, size, colour; widens Blizzard's fixed
36×10 clip box to the icon; pristine stash + exact restore). ★ Name is the ONE text region OUTSIDE
TextOverlayContainer (btn+0, under our +1/+2 gradient frames) → ADOPTED into the container (SetParent;
un-adopted on disable). ★ Hidden EMPTIES THE TEXT (SetText post-hook re-assert; un-hide repopulates via
`C_ActionBar.UsesActionText/GetActionText` — AllowedWhenUntainted, macro names aren't secrets) because
alpha-0 LOSES: **NiceDamage re-drives label alpha after us** (that addon also re-fonts HotKey/Count — pepsi.otf).
`/gb fontinfo` now prints alpha/effective-alpha/parent + styleData.name (the probe that cracked it).

### PART B — Flyout member skinning (`0188cd6`): the LAST square art. `SpellFlyoutPopupButton1..N` are
created LAZILY inside `SpellFlyout:Toggle` (SmallActionButton anatomy + own mixin) → a Toggle post-hook
sweeps: new members get full ApplyButton (its per-button hooks are all guarded on missing methods), known
ones an ApplyDecor re-assert each open. ★ Members wear the **1:1 SIBLING** of the bar shape (FLYOUT_1X1:
pills→circle, squareNN→square, roundsqN-NN→roundsqN) — Blizzard fixes member size/spacing to small squares,
portrait silhouettes OVERLAPPED (Jason screenshot). Members clamp to natural size (preset sizeScale also
overlapped). Popup panel Background + bar-button BorderShadow suppressed (Arrow stays). Members follow the
preset OF THE BAR THE FLYOUT POPPED FROM (owner = Toggle's 2nd arg).

### PART C — PROFILES (Jason's architecture, settled): **profiles → whole-look presets → per-bar assignment.**
"We need profiles. Within the profiles… save different presets. Then… mix and match and assign different
presets to different action bars." Per-character ACTIVE profile (shared account-wide library); manual
create/copy/rename/delete; a preset = the WHOLE look (GB.PRESET_FIELDS, 36 fields); presets AUTO-SAVE (the
edit preset is a live document — switches snapshot the outgoing look first; PLAYER_LOGOUT saves).
- **Stage 1 (`f02d65b`):** data model (profiles[name] = {presets, bars, edit}, charProfiles), migration,
  Snapshot/Save/LoadPreset (always deepcopied), profile mgmt API, RefreshAll (composite over the public
  refresh surface). `/gb profiles` dev probe.
- **Stage 2 (`a533bd9`):** "Profiles" section FIRST in the accordion: profile picker + New/Copy/Rename/
  Delete, preset picker (pick = swap the whole look live) + New/Rename/Delete. Ported GloomsAuras
  flatEditBox + skinned name dialog (no StaticPopup); two-click "Sure?" deletes; **family hover TOOLTIPS
  (attachTip — dark plate + purple title, REUSABLE) replaced the hint block** (Jason: "giant ugly").
- **Stage 3 (`c64ba25`, `f3f138f`): per-button preset resolution — THE architecture.** presetCtx (a preset
  snapshot) + `pv(field)` as the ONE read funnel + `style()` for styleData, hoisted above every reader in
  Skin.lua. **KEY RULE: bars on the profile's EDIT preset render the WORKING COPY (editing stays live);
  only bars on OTHER presets render snapshots.** withPresetCtx wraps the 11 per-button entry points; 4
  global hooks resolve inline; `rec.barKey` (ForEachButton's bar arg) keys the lookup. Glows/Anims share
  Skin's ONE ctx via exports (`Skin:PV/PresetFor/ShapeKeyFor/EnterButtonCtx/LeaveButtonCtx`) — a Glows
  chain landing back in Skin's anchor math resolves the same button. Pulse SPEED stays global BY DESIGN
  (all procs pulse in sync). Apply-to-bars = the assignment grid (row per bar + preset dropdown).
  **ROOT-CAUSE BUG:** Enable's loop dropped ForEachButton's bar arg → barKey never set → assignments
  silently no-op'd; + a second Enable decor pass (the wrapper resolves ctx BEFORE ApplyButton's body
  learns the bar).
- **Per-character default (`f3f138f` era):** a character's FIRST login auto-creates its OWN profile,
  **"Name - Realm" (the GloomsAuras convention — Jason cited it)**; existing bindings honored. Footer
  "Profile: X" button (an unwired increment-1 stub Jason found) = the live profile SWITCHER (`3455d03`).

### PART D — BAR LAYOUT (Layout.lua, phases L1–L4). Jason's scope: size, gaps, rows/cols, orientation,
count, visibility, position (drag + arrows + Shift×10), quick keybind. Settings live PER BAR IN THE
PROFILE (settled: layout is bar geometry, NOT part of a look preset).
- **★ THE FOUNDATION:** Blizzard lays out each bar's **BUTTON CONTAINERS — plain UNPROTECTED Frames**
  (ActionBar.lua:14; the secure button sits CENTER'ed inside; `actionButton.container`). We re-anchor +
  re-SCALE containers ONLY — never the secure buttons. Scale inherits → the whole button (icon, text,
  glows) renders proportionally, which is WHY text grows with Button size (= Edit Mode's own semantics;
  explained to Jason: Button size = geometry per bar; Shape&icon Size = icon-in-button, per preset; they
  MULTIPLY). Re-asserts in per-bar post-hooks (UpdateGridLayout/UpdateShownButtons/UpdateVisibility/
  ApplySystemAnchor). OUT-OF-COMBAT ONLY + a PLAYER_REGEN_ENABLED queue.
- **MASTER SWITCH** (Jason: all-or-nothing): `profile.layoutEnabled` arranges ALL bars; per-bar tables are
  settings only. Un-owning = releaseBar: **unmark FIRST + a `releasing` reentrancy guard** (the Blizzard
  calls fire OUR hooks — recursed until pcall ate a stack error = the "Rows don't revert" bug), reset
  scales, invalidate `oldGridSettings`, re-run Blizzard's grid/visibility/anchor.
- **Gaps:** main-axis Gap + cross-axis **Row gap** (only visible at Rows>1, ABOVE Orientation), both
  **−32..64** (hex/circle silhouettes don't fill their square rects — negative overlap nestles them;
  step clamped ≥4px; caveat told to Jason: hit-rects overlap slightly). **Copy layout from** dropdown
  (tune one bar, copy around). **Visibility** dropdown: Default / Always visible / **In combat / Out of
  combat (RegisterStateDriver — the ONLY legal combat-edge flip)** / Hidden. **Empty buttons** Shown/Hidden
  (collapse reacts to the rendered icon; grid slot KEPT — hole, not shuffle; suspends during SHOWGRID;
  ACTIONBAR_SLOT_CHANGED coalesced via C_Timer.After(0)).
- **Position (L3, `8812299`):** movers (translucent purple, UIParent-parented so hidden bars are movable),
  drag = bar follows live, saved whole-px on drop; click selects; arrows 1px / Shift+arrow 10px (first
  nudge captures the current spot); ESC exits; combat auto-exits (drag + SetPropagateKeyboardInput are
  combat-restricted). **Live CENTER-RELATIVE coords on each mover** (0,0 = screen centre; X<0 left —
  Jason wants exact-0 centring). Button reads "Move bars"/"Lock bars" (names the NEXT action).
  positions = c.posX/posY (bar CENTER, UIParent space, scale-corrected ÷ relative scale on SetPoint).
- **Quick keybind (L4, `3455d03`):** `QuickKeybindFrame:Show()` (the Settings panel's own entry; addon is
  NOT LoD). Dialog reskinned IN PLACE (logic untouched, every region guarded): plate + rim + Khand title +
  GeneralSans + flat buttons + the GA-flatCheck checkbox (orange checkmark, asset → Media/ui/checkmark.png).
  ★ Their OnHide REOPENS SettingsPanel (assumes that origin) → when WE launched, an OnHide post-hook
  closes it same-frame. Buttons: Bar-layout section + footer.
- **QoL:** hovering an Apply-to-bars row or a Bar-layout chip **PINGS the real bar** (Skin:PingBar — the
  shape's `-inner` art tinted family purple on btn+3, one shared pulse driver, no masks needed).

### ★★ HARD-WON LEARNINGS this session (do NOT rediscover):
- **Bar button CONTAINERS are unprotected** — the entire layout engine stands on this. Never touch the
  secure buttons for geometry; scale/anchor containers.
- **EditMode bars OVERRIDE SetShown/Show/Hide to track `isShownExternal`** — hiding through them poisons
  it and BLOCKS your own later show ("can't show it again"). Use **ShowBase/HideBase** (what Blizzard's
  UpdateVisibility itself uses). External (vehicle) hides read that flag — never fight it.
- **`RegisterStateDriver(bar, "visibility", "[combat] show; hide")`** is the sanctioned combat-edge flip;
  nothing insecure may touch a bar once combat starts (incl. SetPropagateKeyboardInput!).
- **`x and false or nil` CAN NEVER YIELD false** (the `or` eats it) — the Empty-buttons Hidden click
  silently wrote Default. Use a plain if when the intended value is false.
- **Two slider writers fight:** the native thumb-drag + our click-anywhere seek quantize the cursor
  DIFFERENTLY near step boundaries → per-frame value flicker ("blur", worst on 0–64). A drag starting
  ON the thumb now belongs to the native slider alone (both factories).
- **Releasing/restoring THROUGH Blizzard calls fires YOUR OWN hooks** → unmark state FIRST + a reentrancy
  guard, or you recurse until a pcall silently eats a stack error (partial revert, no BugSack).
- **QuickKeybindFrame:OnHide reopens SettingsPanel** unless Edit Mode/GameMenu is up — suppress same-frame
  when you launched it yourself.
- **`SetVertexColor`-style traps continue:** FontString alpha wars are unwinnable vs other addons
  (NiceDamage) — hide TEXT by emptying it (SetText hook), not alpha; macro names restore via
  C_ActionBar.GetActionText (AllowedWhenUntainted).
- **Tofu arrows STRUCK AGAIN** (`→` in the layout hint) — session 10's rule stands: no arrow glyphs in any
  rendered string, ever.
- **NEW FILES need a full client RESTART** (TOC additions AND new media assets — /reload only re-reads
  existing files). Layout.lua and checkmark.png both required relaunches.
- **The per-button ctx architecture** (presetCtx + pv() + ONE Skin-owned ctx exported to Glows/Anims,
  save/restore wrappers on entry points, ctx falls back to the ENCLOSING ctx for creation-time passes)
  is THE pattern for any future per-button variance. shapeCtx (flyouts) was its seed.
- **`local style = style()`** (ApplyDecor) is legal Lua (RHS resolves before the local exists) but shadows
  the helper for the rest of the function — don't add style() calls inside ApplyDecor below line ~1012.

### ★★ JASON-DIRECTION (saved to memory, but re-read these):
- **NO "v1", no "later phase", never punt bar layout** — it was committed roadmap and is now BUILT.
  Deferring is "not now, stays on the roadmap" — never "maybe never". (memory: no-v1-framing)
- **No engine jargon anywhere he can see** — "ownership" meant nothing; name controls by visible labels.
  (memory: how-jason-works)
- **Buttons name the NEXT action** ("Move bars" ↔ "Lock bars").
- **"Default" mode = we don't touch it, Blizzard decides** — explained; possible "Blizzard" relabel pending.
- **GloomsAuras is the styling reference** he'll cite (checkbox, per-char profiles, "Name - Realm").

## ★★★ SESSION 12 (2026-07-21→22) — BUGS FIXED + PLATE COMPLETE + BIG QoL/PREVIEW WAVE. ALL committed + QA'd.
Commits, in order: `8498c4c` (the 3 bug fixes), `2de95ad` (dim-on-cooldown), `f78de4f` (Stage 4a keybind),
`67845be` (Stage 4b preview plate), `634d8da` (effects-matrix gaps + Highlight trigger), `dcae0e5` (charge-count
styling), `e5bf43d` (SDF cleanup), `74c62c8` (empty slots), `8b597e0`+`f7d7d5b` (preview keybind chip built then
REVERTED — Jason didn't want it), `adcbddb` (13 preview chips), `6de407c`/`91e99c9`/`f3c632b`/`e63c9f2` (caption
evolution), `dc1db56` (spacing + cast-drain preview + countdown controls), `4173b77`/`bfc2174`/`802d967`
(cast-complete preview burst added → fixed → REMOVED per Jason), `8104465` (Text consolidation), `2b36c72`
(preview CD number hidden).

### PART A — The 3 session-11 bugs, fixed (`8498c4c`):
1. **Finish flash GCD false-fires.** Root cause: chained casts keep `gbRunning` true so `gbStart` goes stale —
   after ~2s of rotation every button's "elapsed" clears `FLASH_MIN_CD` and a GCD boundary flashed whole bars.
   Fix (the handoff's suspected one): **frame-batch the flash decisions** — `queueFinishFlash` collects
   qualifying buttons, resolves one frame later (C_Timer.After(0)); ≥`FLASH_GCD_GROUP` (3) together = a GCD
   wave → suppress the whole batch (a real CD ends on ONE button; a GCD on MANY in the same frame). No secrets.
2. **Green equipped-item border reappearing.** Root cause FOUND in client source (`ActionBarActionButtonMixin:
   Update()` ~line 596): `border:SetVertexColor(0, 1, 0, 0.5)` — **on a Texture the 4th SetVertexColor arg IS
   the alpha**, silently undoing our `SetAlpha(0)` on every button refresh (target swap, page flip — far more
   paths than the reassert-frame events). Fix: one-time per-button post-hook on `Border:SetVertexColor`
   re-asserting alpha 0 while the skin is enabled (in `Suppress`). ⚠ No deterministic repro — Jason watching.
3. **Plate cooldown ellipse (Jason's design call: icon-square-only).** `AlignCooldowns` hand path now anchors
   all three cooldowns to the **ICON** (= the square half in plate mode; identical to before otherwise since
   `constructRef` returned the icon in non-plate). NEW half-swipe art: `<key>-swipe-t/-b.png` for the five 2:1
   shapes (`half_swipes()` in generate-hand-swipes.py — crops the icon half of the base; 256² pow2, no
   pre-distortion needed; -t = icon-on-top silhouette). `handSwipePart()` picks by `plateIconSide`; folded into
   `applyShapeArt`'s artKey so side flips re-set it. **The plate gradient moved to its OWN frame at btn+1**
   (`rec.plategradFrame` + a DEDICATED same-frame mask via buildMask — cross-frame mask attach is unproven §2):
   Blizzard's cooldowns are `useParentLevel` (btn+0), so the gradient now draws ABOVE the sweep and the sweep's
   hard midline edge hides under the opaque end of the fade (Jason's "no weird bottom edge" ask). Still below
   decor (+2) / cast fill (+3) / text (+4).

### PART B — Plate dim-on-cooldown (`2de95ad`) — ★ a NEW PROVEN PATTERN (verified in-game):
The plate colour (fill + gradient) dims to `PLATE_DIM` (0.45×) while the action's REAL (non-GCD) cooldown runs.
**We may not READ the cooldown clock (secret), but Midnight has a sanctioned indirect route:** a hidden per-button
proxy Cooldown widget is fed `C_ActionBar.GetActionCooldownDuration(action, ignoreGCD=true)` (returns a
LuaDurationObject) via `proxy:SetCooldownFromDurationObject(dur)` (clearIfZero defaults true), and we react to
the WIDGET's rendered lifecycle: `IsShown()` sync after each feed + OnCooldownDone/OnHide → undim. No secret
value ever touches Lua — same react-to-rendered-output principle as the usability tints. Both calls pcall-wrapped
(fail soft). Refreshed from the existing `ActionButton_UpdateCooldown` post-hook. `rec.plateDim` → ApplyDecor
paints with the multiplier. Config: Plate → **"Dim on cooldown"** (`plate.dimCD`, default off).
**NOTE:** this proxy pattern could someday replace bug #1's GCD heuristic (fire the flash from the proxy's
OnCooldownDone — GCD-proof by construction). Not done — the heuristic is QA'd; don't churn unless it misbehaves.
(Also checked: Blizzard does NOT desaturate icons on cooldown — only level-link — so there was no rendered-output
signal to react to; hence the proxy. `duration:IsZero()` is NOT flagged ReturnsNeverSecret — do NOT branch on it.)

### PART C — Plate Stage 4 complete:
- **4a (`f78de4f`): keybind-in-plate.** `ApplyHotkeyOverride`: zone "extension" + `plateActive()` → the hotkey
  centres in the half OPPOSITE the icon (`CENTER, btn, ±pw/2` — the platefill's math). Offsets still nudge.
- **4b (`67845be`): the Config preview mirrors plate mode.** Key move: `sref` = the SHAPE reference rect
  (= previewFrame in plate mode — the full 2:1 IS the frame — else previewIcon; they're geometrically identical
  non-plate, so all other shapes render unchanged). The icon shrinks to a pw×pw square in the chosen half
  (square TexCoord crop); plate fill + midline gradient render via the plate pool (masked by sref-anchored
  masks); handAnchor/border/outer/inner/anims/flash all re-point at sref; previewCD keeps tracking previewIcon
  (the square) with the half-swipe. `Anims:PreviewReconcile` receives the plate-aware ref (bars use ConstructRef).

### PART D — Effects-matrix gaps closed (`634d8da`) + a NEW glow trigger:
- **`SpellHighlightTexture` → the "highlight" trigger.** ★ LEARNED: it's NOT a combat suggestion — it's the
  **spellbook/talent-hover locator** ("this spell sits HERE on your bars"; drivers: SpellBookItem OnEnter +
  ClassTalentButton ShowActionBarHighlights → UpdateOnBarHighlightMarksBySpell). Blizzard pulses a square via
  `SharedActionButton_RefreshSpellHighlight(button, shown)` with a LOOPING Alpha anim (0→1→0) — a one-shot
  alpha-0 LOSES to it, so the post-hook **Stops the anim + Hides the texture**, then routes the state to
  `SetSource(btn, "highlight", shown)`. Priority: just below proc. Pulses. Seeded in Core's trigger seeding
  (warm yellow); gets the Glows-matrix row + Animations chip for free. QA'd via spellbook hover.
- **`NewActionTexture` + `CooldownFlash` (GCD flipbook):** both Show/Hide-driven → durable alpha-0 in
  `Suppress`, restored on disable. **Flyout member background stays deferred** (outside the v1 bar set).

### PART E — Text styling: two new engines + ONE home for all of it:
- **Charge count (`dcae0e5`):** `ApplyCountOverride` (styleData.count) — zones corner (Blizzard's spot) /
  center / extension (plate half, keybind math), offsets, LSM font, size, colour; pristine stash + exact
  restore. Applied from ApplyDecor — ★ Blizzard re-anchors Count ONLY in SmallActionButtonMixin's OnLoad
  (UpdateCount just SetText()s), so NO re-assert hook is needed.
- **Countdown numbers (`dc1db56`):** `styleCooldownText` (styleData.cdtext) — show/hide + colour/size/font/
  offsets for the Cooldown widget's number. ★ The widget creates its FontString LAZILY on the first visible
  countdown (find via GetRegions; one-frame retry), and Blizzard re-drives the hidden state from the
  countdownForCooldowns CVar callback → re-asserted from the UpdateCooldown post-hook + a hook on
  `ActionButton_UpdateCooldownNumberHidden`. **cdtext ABSENT = never touch anything** (the game CVar rules).
- **Consolidation (`8104465`, Jason: "scattered and nonintuitive"):** the **Text section** now has a CHIP ROW
  (Keybind · Charge count · Countdown — the Animations-section pattern); each element's block shows below and
  the section resizes (`bf:SetHeight` + `relayout()`). The standalone Charge-count section is GONE; the
  COUNTDOWN block moved OUT of Cooldown & availability. A future Name override = a 4th chip.

### PART F — Empty slots (`74c62c8`): dim or hide slots with no action.
Config section "Empty slots": **Normal / Dim / Hidden** + a dim-opacity slider (`db.emptySlots` /
`db.emptySlotAlpha`). **Alpha-only on the secure button** (`btn:SetAlpha` — NOT a protected operation; the
pure-skin wall holds — we never Show/Hide). "Empty" = reacting to rendered output: Blizzard's Update() Hide()s
the icon when a slot has no action → `icon:IsShown()` is the signal, re-checked in a per-button `Update`
post-hook. ★ `ACTIONBAR_SHOWGRID`/`HIDEGRID` (still live in this build) lift the treatment while an action is
on the cursor, so drop targets stay visible. Restored on disable.

### PART G — SDF cleanup (`e5bf43d`): −259 lines + 4 assets.
★ KEY FACT: `db.handShape` is ALWAYS seeded (Core ADDON_LOADED, legacy-shape migration) → `handKey()` is never
nil → the SDF soft-bloom fallback in Glows:Refresh was UNREACHABLE. Removed: GetGlow + the `glows` pool +
anchorGlow/currentGlowTex/glowScale/tintFor + dead public setters ApplyStyle/SetColor (zero callers) + the
whole session-8 bake-off harness (`/gb glowtest|glowstyle|handglow`, ForceTest/SetTestArt/HandPreview, the
`test` source, gbtest-glow-*.png, generate-art.py's glow_A/B/C+gen_test). Refresh is now unconditionally the
multi-part hand path. **KEPT deliberately:** GB.SHAPES + Media/masks + the per-shape ring/swipe SDF art — still
wired as live texture fallbacks in shared paths (applyShapeArt rings, preview fallbacks); removing them is a
bigger, riskier pull for a dedicated pass.

### PART H — Preview-pane upgrade (Jason drove the design; several iterations):
- **13 state chips (`adcbddb`):** + Highlight/Assist/Cast/Channel (real multi-part glow per trigger;
  assist+highlight breathe — PREVIEW_PULSING mirrors the bars) and Unusable/Out of mana/Out of range (tint the
  sample icon via the SAME db fields computeIconTint reads; range = desaturate+wash). 2×7 grid;
  PREVIEW_CENTER_Y −290. Every Glows row + Animations trigger flips the preview to its own chip.
- **Captions (`6de407c`→`e63c9f2`):** each state = { bold Semibold HEADING, Jason's descriptive prose, a bold
  **"Styled in:" bullet list** of clickable section links }. Links = `|Hgbsec:<title>|h` in caret orange on a
  mouse-enabled `SetHyperlinksEnabled` frame → `C:OpenSection(title)`, then **re-set the preview state**
  (some sections hijack it on open — Glows s.refresh → proc). Muted notes mark partial coverage ("Cast &
  channel — fill & bursts", "Text — countdown numbers"). ALL left-aligned (Jason: you can't centre a bullet
  list). ★ FontStrings can't mix fonts inline → the bold state name is its own heading line.
- **Cast/channel drain preview (`dc1db56`):** a looping 2.4s fake fill (previewCastFillFrame) mirroring
  CastFillOnUpdate's geometry exactly — cast fills up / channel drains, all 4 castDrainDir values, colour/alpha
  live from db; fresh same-frame mask per refresh + a first-show one-frame retry (§2 never-rendered quirk).
  Cast & channel fill setters poke the Cast chip so edits animate live.
- **Cast-complete burst: REMOVED (`802d967`).** Tried twice (`4173b77` shared burst player; `bfc2174` fixed it
  from legacy-SDF-square art to the hand `-outer` + hand anchor — which DID fix the finish-flash preview, kept).
  ★ But the REAL completion burst is **Blizzard's EndBurst animation replayed inside their widget** — a
  lookalike from our flash player reads wrong. Jason's rule: **better no preview than an unfaithful one.**
  (The cooldown finish-flash preview stays — it mirrors OUR OWN bar animation 1:1.)
- **Preview keybind chip: REVERTED (`f7d7d5b`).** Jason: bars show the real thing; not worth preview drift.
  Same reasoning killed the preview countdown number (`2b36c72` — SetHideCountdownNumbers on previewCD).

### ★★ HARD-WON LEARNINGS this session (do NOT rediscover):
- **`SetVertexColor(r,g,b,a)` on a Texture SETS ITS ALPHA** — Blizzard's equipped-border tint silently undid
  our alpha-0 suppression. Any alpha-0 suppression of a texture Blizzard SetVertexColor's needs a hook.
- **Button cooldowns are `useParentLevel` (btn+0)** — a frame at btn+1 draws OVER the swipe (the plate
  gradient trick). TextOverlayContainer +4, cast fill +3, decor +2 unchanged.
- **GCD wave heuristic:** a GCD ends on MANY buttons in the SAME frame; a real cooldown on ONE. Frame-batching
  OnCooldownDone (resolve via C_Timer.After(0), threshold 3) separates them with zero secret reads.
- **The Midnight duration-object proxy pattern WORKS in combat** (Part B) — the sanctioned way to know "a real
  cooldown is running" without reading the clock. `GetActionCooldownDuration(action, ignoreGCD)` +
  `SetCooldownFromDurationObject` + widget lifecycle. pcall both.
- **SpellHighlight is the spellbook/talent locator pulse** (not combat); its looping Alpha anim beats one-shot
  alpha-0 → Stop()+Hide() in the `SharedActionButton_RefreshSpellHighlight` post-hook.
- **Blizzard never re-anchors Count at runtime** (only SmallActionButtonMixin OnLoad) → count override needs no
  hook. The countdown FontString IS lazy + CVar-driven → needs both hooks (Part E).
- **`db.handShape` is always seeded** → the SDF fallbacks were dead; `handKey()` nil-paths can be pruned.
- **Preview honesty is a Jason design principle:** preview elements must mirror the ENGINE's exact art +
  anchors (the burst drew legacy SDF art because the preview player predated hand shapes); if a Blizzard
  internal can't be reproduced faithfully, OMIT it rather than fake it; don't render text the preview can't
  style truthfully (keybind/count/countdown chips all removed for this reason).
- **Jason interrupted a design I was about to build and supplied his own** (caption links → his bullet-list
  spec). When he starts "Wait—", STOP and let him finish before writing code.

### ✔ CLOSED / DROPPED this session:
- **Coexistence QA: CLOSED** — Jason's full addon ecosystem (ArcUI, EnhanceQoL, etc.) was enabled THE WHOLE
  TIME with zero issues; the handoff's standing "re-test with addons enabled" item is done.
- **Per-trigger glow spread/softness: DROPPED by Jason** — obsolete now that the per-trigger matrix exists.
- **Out-of-range is the ONLY state that touches keybind text** (Blizzard's range indicator colours it red;
  we recolour to match). OOM/unusable tint the icon only. (Answered for Jason.)

## ★★★ SESSION 11 (2026-07-21) — ANIMATION CATALOG COMPLETE (8/8) + PLATE MODE (2:1 shapes) + fixes. 3 BUGS OPEN.
A very long session. Commits: `8dc1349` (marching/sheen/sparkles), `cd5c2d1` (breathe/burst/rimflash/radar),
`ccddd0f` (plate mode Stages 1–3 + Config UX polish), `d194637` (plate overlays + cast/cooldown/taint fixes, WIP
with the known bugs). `0f9adc5` earlier (Cast/Channel SetCast regression fix — see below).

### PART A — Animation catalog COMPLETE (8/8). All QA'd in-game.
The plug-in registry (`Anims.lua`, `GB.Anims`) now has all eight modules; each auto-appears in the Config
Animations dropdown with its param UI generated from its schema (no per-module Config wiring):
1. **Comet Chase** (`shine`) — session 10. 2. **Marching Lines** (`march`) — dashes on the rim; its OWN thin
`<key>-line` masks (generate-march.py) + BLEND (true colour, not the washed-out ADD). 3. **Sheen Sweep**
(`sheen`) — a diagonal gleam across the icon FACE; first use of the `choice` param kind (Style: Glow=ADD/
Solid=BLEND) + custom bispeed L/R labels; restarts on each trigger for instant hover. 4. **Sparkles** (`sparkle`)
— randomised twinkles on the face; live Size param. 5. **Breathe** (`breathe`) — the outline scales in/out
(the only SCALE module; draws `<key>-rim` directly, no mask); rate bumped ~3× so Speed reaches a fast throb.
6. **Burst Ring** (`burst`) — N phase-staggered outline shockwaves expand+fade. 7. **Rim Flash** (`rimflash`)
— the outline blinks (sharp alpha). 8. **Radar Sweep** (`radar`) — a wide fading wedge rotates over the icon
FACE (a scanner; reimagines the catalog's weak "full-glow spin"); new `radar.png`.
- **Shared masking fix — prime-then-reveal (`PRIME_ALPHA`).** AddMaskTexture defers a frame (§2), which flashed
  the graphic UNMASKED on the first trigger of each button. Every masked module now primes near-invisible for
  that render frame, then attaches the mask + reveals together. (Breathe/Burst/RimFlash are mask-free — the rim
  art IS the shaped outline — so they skip this.)
- **Config UX polish (done + QA'd):** preview-pane caption now describes the selected state (what triggers it),
  synced from BOTH the Animations state chips AND the top preview chips (`STATE_DESC`, in `SetPreviewState`/
  `SetPreviewAnim`); the Animation dropdown got a ▾ caret; the Animations section sizes to the SELECTED module
  (per-block `bottom` → `heightFor`/`setSectionHeight`), no dead space under a short module / None.

### PART B — PLATE MODE for 2:1 portrait shapes (the North Star "plate" look). `styleData.plate`.
Rebuilds the "plate" reference look on the FIVE 2:1 portrait hand shapes only (`pill21`, `square21`,
`roundsq1-21`, `roundsq2-21`, `roundsq3-21` — a 2:1 silhouette halves into two clean squares; other aspects
don't, so plate mode is GATED to these via `plateActive()`). A SQUARE icon fills one half, a solid-colour plate
fills the other, and that colour fades up over the icon.
- **Engine (`Skin.lua`):** `plateActive()`/`plateStyle()`/`plateIconSide()` near `handKey()`. `applyIconSize`
  puts a square W×W icon in the chosen half (±W/2). `ApplyDecor` routes the SHAPE mask to a full-2:1 construction
  rect `rec.plateRect` (W×2W, centred) so a half-height square icon doesn't squish the silhouette; the same mask
  clips the icon, the **plate fill** (`rec.platefill`, tinted WHITE8X8, the opposite half) and the **plate
  gradient** (`rec.plategrad`, WHITE8X8 + `SetGradient`, opaque at the midline → transparent across `fadeStart`
  of the icon). The old decoration-layer gradient loop is skipped in plate mode. `Skin:RefreshPlate` applies
  enable/side changes (colour/fade → `ReapplyDecor`).
- **`Skin:ConstructRef(btn)` / `constructRef`** — the reference rect an OVERLAY should span: `plateRect` in plate
  mode (CREATED ON DEMAND — AlignCooldowns runs before ApplyDecor, so lazy creation avoids the square-icon
  fallback), else the icon. Glows/Anims/cooldown/cast-fill/burst/finish-flash all route through it so overlays
  trace the WHOLE plate. (This is the `d194637` work.)
- **Config `Plate` section** (repurposed from the now-dead "Construction"): Enable · Icon side (top/bottom) ·
  Plate colour · Fade start. Colour + fade start stay in sync with the Decoration-Layers gradient BOTH ways
  (mirrored in the setters). Greyed with a hint on any non-2:1 shape. Helpers `plateData`/`ensurePlate`/
  `plateShapeOK`.
- **DONE + QA'd:** the split geometry, colour, gradient, side toggle, colour/fade sync, and the glow + animation
  + cast-fill overlays tracing the full plate. **NOT done — plate Stage 4:** the Config PREVIEW PANE does not
  mirror plate mode yet (test on real bars), and the keybind-in-plate (centre the hotkey in the plate half).

### PART C — Fixes this session.
- **Cast/Channel regression (`0f9adc5`, QA'd):** session 10's rewrite dropped `Glows:SetCast`, but Skin.lua's
  PlaySpellCastAnim hook still called it (guarded → silent no-op) → NO cast glow/animation during casting.
  Restored `SetCast` as a thin wrapper over the internal source model.
- **Cast/channel drain on MULTIPLE buttons (QA'd FIXED):** the cast fill OnUpdate reads the GLOBAL
  `UnitCastingInfo("player")`, and each fill frame stays alive 1.5s after its own cast (grace window), so a
  button you cast a moment ago re-drained to your NEXT cast. Now gated on `castCurrentBtn` (set in `styleCast` to
  the button whose cast anim fired) + a per-frame `f.draining` flag. Minor known tradeoff: same spell on two bars
  → only the last-fired one drains.
- **Taint (finish-flash) REVERTED:** an attempt read the `SetCooldown` `duration` argument and compared it — that
  arg is a PROTECTED/SECRET number, so `duration > 2` THREW "attempt to compare a secret number value" every
  cooldown tick. Reverted to the game-clock timer; ALSO now clears `gbStart` on `OnCooldownDone` to reduce the
  GCD-boundary race. **This did NOT fully fix the flash — see bug #1.**

### ⚠ KNOWN BUGS (session 12 — fix these FIRST, one at a time, verify in-game):
1. **Finish flash false-fires on MULTIPLE buttons after a GCD.** The game-clock GCD filter (`hookFlashCooldown`
   in Skin.lua, `FLASH_MIN_CD = 2.0`) still lets GCD-length cooldowns flash on many buttons at once at a GCD
   boundary. **Root constraint:** we CANNOT read the secret cooldown duration to tell a GCD from a real CD
   (that's the taint above). **SUSPECTED best fix (non-secret):** a GCD ends MANY buttons in the SAME frame; a
   real cooldown ends ONE. So COUNT `OnCooldownDone` events across all buttons per frame/tick — if ≥N fire
   together, treat it as a GCD and suppress the flash. (Alt: find a non-secret GCD-duration API, e.g. the GCD
   spell's cooldown, and skip flashing when elapsed ≈ the current GCD.) Cheap interim: default Finish flash OFF.
2. **Green equipped-item border reappears on trinkets/equipped items.** It's Blizzard's `btn.Border`, suppressed
   via `btn.Border:SetAlpha(0)` in `Suppress(btn)` (Skin.lua ~line 137). My changes don't touch it, so it's
   PRE-EXISTING. **SUSPECT:** Blizzard re-shows/re-alphas it on an event we don't re-suppress on (equip /
   `PLAYER_EQUIPMENT_CHANGED` / bag update / `UpdateButtonArt` for that button) — needs a re-assert hook, OR the
   plate render path skips `Suppress` for some buttons. Check whether `Suppress` runs for the trinket at all.
3. **Cooldown radial sweep looks elliptical/diagonal on the tall plate.** Blizzard's cooldown is a RADIAL wedge;
   on a 2:1 widget it stretches into an ellipse (inherent to radial-on-tall). We CANNOT draw a custom LINEAR fill
   (cooldown REMAINING time is secret — unlike cast time). **DESIGN DECISION for Jason:** (a) accept the radial
   look on plates, or (b) anchor the cooldown to the ICON SQUARE only (clean circular sweep, but the plate half
   stays lit during cooldown). This is a taste call, not a code bug.

### ★★ HARD-WON LEARNINGS this session (do NOT rediscover):
- **The `SetCooldown` `duration` argument is a SECRET/PROTECTED value — comparing it TAINTS** ("attempt to
  compare a secret number value"). Confirms the session-7 "game clock, never read the duration" decision. The
  cooldown REMAINING/duration is off-limits; the CAST time (`UnitCastingInfo`) is readable (that's why the cast
  fill can be linear but a cooldown can't).
- **`UnitCastingInfo("player")` is GLOBAL** — a per-button cast fill can't tell whose spell is casting from it
  alone; gate on the current-caster button (`castCurrentBtn`, set from the PlaySpellCastAnim hook).
- **`plateActive()` is GLOBAL** (checks `db.handShape` is a 2:1 portrait + `db.plate.enabled`) — so when a 2:1
  plate shape is active, EVERY button renders as a plate (trinkets included).
- **`constructRef` must create `plateRect` ON DEMAND** — `refreshIconGeometry` calls `AlignCooldowns` (step 5)
  BEFORE `ApplyDecor` (step 6), and plateRect used to be created only in ApplyDecor → the cooldown fell back to
  the square icon and the swipe showed a squished shape ("dark remnant behind the glow").
- **The cooldown `-swipe` un-distorts ONLY on a widget of the shape's aspect** — a 2:1 swipe on a SQUARE widget
  stays squished; on a 2:1 widget it traces the pill (session-4 mechanic). Plate mode must anchor the cooldown to
  the 2:1 plateRect, not the square icon.

## ★★★ SESSION 10 (2026-07-21) — GLOW POLISH (#1) + the PER-TRIGGER ANIMATION SYSTEM (#2). ALL committed + QA'd.
A long, high-throughput session done GUI-first (Jason HATES slash commands — see below). Two big deliverables.
Commits: `3477eae` (glow matrix + flash fix), `34d10b8` (preview chips), `7f31e16` (shine prototype + assets),
+ this handoff commit (the animation framework). **Do NOT relitigate anything below — QA'd in-game.**

### PART A — Glow polish (NEXT #1). Commits `3477eae`, `34d10b8`.
- **Per-trigger glow model — `db.triggers`.** Each of proc/assist/cast/channel/hover/selected/flash is now ONE
  uniform record `{ enabled, color, opacity, layers }`, so each is tuned independently. Replaces the scattered
  `glowColor/glowIntensity/glowAssistColor` + `stateColors/stateIntensity` (kept DORMANT for the SDF fallback +
  seeded once from them on load). Config **"Glows" matrix** (replaced "Proc glow" + "State highlights"):
  per-trigger **on · colour · layers (both/inner/outer) · opacity**, + a global **Pulse speed**. Engine
  (Glows.lua): `winningTrigger` picks the highest-priority ENABLED trigger (disabling one drops to the next);
  the shared pulse driver uses each glow's OWN peak; outer/inner are Show-gated by `layers`. Folded in the old
  hardcoded cast/channel halo colour + brightness (two backlog items gone).
- **Flash-checked SQUARE fix (was a latent session-9 gap).** Blizzard's `UpdateFlash` re-drives
  `GetCheckedTexture():SetAlpha(1.0)` on the auto-attacking button (`ActionButton.lua:1306`), un-hiding the old
  SDF checked ring OVER the shaped flash glow. Our one-time alpha-0 loses. Fix: re-assert alpha 0 in a per-button
  `UpdateFlash` post-hook (Skin.lua) — same "re-assert in a hook" pattern as the cast fill.
- **Preview chips honest now (#1a).** The Config preview's **Proc/Hover/Selected/Flash** chips draw the REAL
  multi-part glow (`previewOuter` under the icon + `previewInner` over the plate, mirroring the bars) and honour
  the per-trigger **layers**; the **Cooldown** chip traces the hand `-swipe`. The pulsing chips (proc/flash)
  **breathe at the live Pulse speed** via an OnUpdate on `previewFrame`. The SDF `previewGlow`/`previewRing` stay
  as the dormant non-hand fallback.

### PART B — The per-trigger ANIMATION SYSTEM (NEXT #2 — "the fun one"). This commit.
- **THE FRAMEWORK — `Anims.lua` (`GB.Anims`), a plug-in registry.** Each animation = a MODULE:
  `{ id, label, defaults, params(schema), Start(host, icon, key, p), Stop(host) }`. **Start/Stop are keyed by
  HOST frame** — a button OR the Config preview frame — so ONE module renders identically on the bars AND in the
  editor preview. `Anims:Reconcile(btn, triggerKey, trigger)` (called from `Glows:Refresh`, hand path) runs the
  WINNING trigger's enabled animation + stops the rest; skips when the winner is unchanged (Refresh fires often);
  `Anims:Invalidate(triggerKey)` forces a re-reconcile after a Config edit. `Anims:PreviewReconcile(host,icon,
  key,trigger)` drives the preview. **Data: per trigger `anims[id] = { enabled, ...params }` — PER-STATE**, so
  Proc's Comet Chase (red/CW) and Hover's (green/CCW) are fully independent.
- **FIRST MODULE — Comet Chase** (`id = "shine"`, label **"Comet Chase"**): N glowing comets orbiting the rim.
  One shared comet (`Media/art/shine.png`) + a per-shape rim mask (`Media/art/hand/<key>-rim.png`). Params:
  **colour · comets (1–4) · spin** (a bidirectional velocity slider). Assets from `tools/generate-shine.py`.
- **CONFIG "Animations" section = State chips → Animation dropdown → the selected animation's params.** ONE
  animation per state (dropdown lists None + each module). Params are generated from each module's schema (kinds:
  `color`/`range`/`bispeed`/`choice`), so **new modules get their UI for free**. Generic dropdown flyout
  (`animDropdown`/`animFlyoutFrame`) modelled on the font flyout (catcher closes on outside click).

### ★★ HARD-WON LEARNINGS (do NOT rediscover):
- **The rotating-shine mechanic works:** a comet spun over the icon (`SetRotation`, oversized 1.6× so the spin
  covers the rim at every angle), clipped by a per-shape RIM MASK, reveals only the outline band → the bright
  head chases the rim on ANY silhouette. **`SetRotation` on a masked texture does NOT rotate the mask** (the
  comet sweeps under a fixed rim — validated). N comets = N phase-spaced copies (360/N apart) driven by ONE OnUpdate.
- **The comet + rim art:** the comet must be a **compact bright POINT + a short dim tail** (angle-only, so it hits
  the rim at any radius) — a wide wedge read as a thick "inchworm". The rim mask must be a **SOFT band CENTRED on
  the outline** (dilate + erode, then gaussian FEATHER) — a hard eroded band read as a metallic border and pinched
  to a point at the caps. Thickness/softness/tail are BAKED (regen `generate-shine.py`); count/colour/spin are LIVE.
- **Spin = one SIGNED velocity** in [-1,1]: sign = direction, magnitude = speed, 0 = still, |1| = fastest
  (`SHINE_MIN_REV` sec/rev). **WoW rotation is CCW-positive → NEGATE** so positive/right = clockwise (matches the
  UI). The comet's tail is baked on one side → **mirror the comet (`SetTexCoord(1,0,0,1)`) for CW motion** so the
  tail always TRAILS, never leads.
- **`AddMaskTexture` fails on a never-rendered texture** (API-NOTES §2) — show the comet FIRST, attach the rim mask
  one frame later (`C_Timer.After(0)`). Same pattern the plates use.
- **Arrow glyphs `←`/`→` are TOFU** in the bundled fonts — don't put them in labels (use plain "CCW"/"CW").

### ★★ SETTLED DECISIONS (2026-07-21, session 10 — do not reopen):
- **Per-trigger EVERYTHING, never global.** Glow (colour/opacity/layers) AND animation params are per-STATE.
  (Jason: an animation's settings must NOT be global — Proc red-CW and Hover green-CCW coexist.)
- **Animations are a plug-in SYSTEM, not one-offs.** Catalog of **8 types**: Comet Chase (BUILT) + **marching
  lines · sheen sweep · sparkles · breathe/pulse-scale · rim flash · burst-on-fire · full-glow spin** (planned).
  Each is a module registered in `Anims.lua`.
- **ONE animation per state** — the dropdown IS the choice (incl. None). The engine supports multiple-enabled if
  we ever want to layer them; the UI enforces one.
- **GUI ONLY — NO slash commands for the user.** Jason "really really really" HATES slash/CLI (saved to memory
  `gui-not-slash-commands`). Every user control is in Config; the `/gb shine` playground was REMOVED. Dev slash
  commands for Claude's own checks are tolerable but should be hidden/removed once a GUI equivalent exists.
- **Renamed "Shine chase" → "Comet Chase"** (user-facing label; the module `id` stays `"shine"` internally).

### ▶▶ NEXT (session 11) — in priority order
1. **Next animation types.** **Marching lines FIRST** — reuses Comet Chase's rim-mask + scrolling-texture
   mechanism (a dashed/dotted band scrolled around the rim), so it's a cheap second module that proves the
   registry. Then sheen sweep, sparkles, breathe, rim flash, burst-on-fire, full-glow spin — one small module
   each. Each new module auto-appears in the Animations dropdown + gets its param UI free from its schema.
2. **Animations UI polish:** (a) the dropdown has no ▾ **caret** yet (`Media/ui/caret.png` is available). (b)
   picking **None** leaves the section at full height (empty space) — dynamic section height via `relayout()`, or
   shrink. (c) optional per-shape rim **thickness/softness presets** (currently baked defaults in generate-shine.py).
3. **Glow leftover (#1 remainder):** per-trigger **spread/softness** for the glow (Jason said OPTIONAL — the
   now-dead `stateWidth` "Glow width" could be revived for hand shapes so hover reads subtler than proc).
4. **Effects-matrix gaps (#3):** `SpellHighlightTexture` (pulsing "press this"), `CooldownFlash` (GCD flipbook),
   `NewActionTexture`, flyout member background. See EFFECTS-MATRIX.md §B/§A/§I.
- **Anytime:** coexistence QA with ArcUI/EQOL re-enabled (our hover/flash/icon-vertex work touches a lot now);
  the old SDF shape/bloom code is dormant (removable once nothing references it); assist glow stays low-priority.

## ★★★ SESSION 9 (2026-07-21) — SHAPE SELECTION + PERSISTENCE, then GLOW-TO-TRIGGERS (both major; ALL committed + QA'd)
A long, high-throughput session. Delivered BOTH remaining big pieces of the shaped-glow rebuild end-to-end.
Structured, one-QA-step-at-a-time (Jason's workflow). Commits: `7903687` (shape selection), `32d66d2`
(proc glow), `54dde4e` (hover/selected), `c09ef80` (cast/cooldown shape), `88eda98` (cast rim glow),
`2d26e57` (flash). **Do NOT relitigate anything below — it's all QA'd in-game and settled.**

### PART A — Real shape selection + persistence (was NEXT #2). Commit `7903687`.
- **`db.handShape`** (a `GB.HAND_SHAPES` key) + **`db.sizeScale`** (uniform × the Edit-Mode button size) are
  real saved settings. `handShape` is **read straight from the db** (Skin `handKey()`), so it survives /reload.
  Seeded on first run from the legacy SDF shape (circle→circle, square→square, hexagon→hexagon, rounded→roundsq2).
- **`GB.HAND_SHAPES` / `HAND_ORDER` / `HAND_GROUPS`** (Core.lua): the 21 keys' metadata (aspect, orient, label)
  + picker grouping (1:1 / Portrait / Landscape). `GB:HandAsset(key, part)` = `Media/art/hand/<key>-<part>.png`.
  `GB:HandShapeInfo(key)` → {aspect, orient, label}.
- **The pivot mechanic:** `applyIconSize`/`handIconSize` derive the icon W/H from the shape's aspect × sizeScale
  (portrait → tall, landscape → wide, 1:1 → square), so the icon is ALWAYS the right proportion with **no manual
  sizing** — free width/height is retired. `refreshIconGeometry` is the shared per-button refresh used by
  `SetIconSize`/`SetHandShape`/`SetSizeScale`. iconW/iconH are still WRITTEN (derived) so downstream anchor math
  is unchanged; they're just no longer user-facing.
- **Config Shape & icon rebuilt** as a **grouped thumbnail grid** of all 21 silhouettes (each drawn from its own
  `-base` art, purple-selected, hover tooltip) + a single **Size** slider. Removed the SDF corner presets, corner
  radius, icon width/height, lock-aspect. Kept Icon zoom + Crop to fill. Preview pane renders the actual hand
  silhouette (icon mask + border + gradient) via a per-axis anchor mirroring `Skin.hgAnchor`.
- **Shared `makeScrollbar`** helper (Config.lua): a thin custom scrollbar with the **orange caret-colour thumb**,
  **click/drag-anywhere-on-track to jump** (same QOL as the sliders), wheel, auto-sized to live range. Used by the
  main window AND the font dropdown. Reuse it for any future scrollbar (returns `:Sync()`).
- `/gb handshape <key>` persists now; `/gb size <n>` added; `/gb handglow [off]` = force the multi-part glow on to
  study it out of combat. SDF shape system left DORMANT as fallback (handKey nil path — never hit post-migration).

### PART B — Glow to real triggers (was NEXT #1, "the payoff"). Every button state → the multi-part shaped glow.
The multi-part glow = **outer** (a per-shape `-outer` texture UNDER the icon at BACKGROUND −2, perfect outward
falloff) + **inner** (`-inner` OVER the gradient at **btn+3** — above the plate at +2, BELOW the text container at
+4 so keybind/count render over it) + **border recolour** (the button's Border adopts the glow tint). One tintable
WHITE pair per shape (`Media/art/hand/<key>-outer|-inner`) serves ALL triggers, differing only by tint + pulse.
- **Engine (Glows.lua):** per-button `getHandGlow`/`applyHandGlow(btn,tint,pulse,peak)`/`hideHandGlow`; a shared
  **pulse driver** (one OnUpdate animates every ACTIVE glow's alpha between peak and peak×PULSE_DEPTH — runs only
  while ≥1 glow is active). `Refresh` reconciles per-button **sources** by priority and calls `resolveGlow`.
- **Sources + priority (highest first): assist > proc(alert) > cast > flash > selected > hover > dev-test.**
  Procs/assist/flash/test PULSE; cast/selected/hover are STATIC. State highlights (hover/selected/flash) use
  `stateColors` + `stateIntensity`; procs use the proc Colour/Brightness; cast uses `CAST_TINT_G` (gold cast / lime
  channel). `SetSource` skips the refresh when a value is unchanged (kills churn from the frequent state event).
- **Triggers wired:**
  - **Proc / assist** — the existing alert-manager + assisted-highlight hooks (unchanged) now route to the multi-part
    glow. `32d66d2`. Config Proc glow: Colour, Brightness (peak alpha, live), Pulse speed (live). **Size removed**
    (baked into the art + border grow).
  - **Hover** — per-button `OnEnter`/`OnLeave` hooks. Blizzard's square highlight ring suppressed (alpha 0). `54dde4e`.
  - **Selected** — `ACTIONBAR_UPDATE_STATE` + `GetChecked()` (reads rendered state, no secret). Checked ring
    suppressed. NB: Blizzard checks a button briefly on ability PRESS (current-action) → a brief selected glow on
    press; that's DEFAULT behaviour, expected. `54dde4e`.
  - **Cast / channel** — `PlaySpellCastAnim` hook → `Glows:SetCast(btn,"cast"/"channel")`; cleared when the cast ends
    (via `f.gbBtn` in `CastFillOnUpdate`). Steady lime/gold halo; the drain fill shows progress. `88eda98`.
  - **Flash** — auto-attack/auto-shot: per-button `StartFlash`/`StopFlash` hooks (they toggle the flashing STATE,
    not each blink). SDF flash ring suppressed. Needs the "Attack" ability on a bar to have a button to flash. `2d26e57`.
- **Cast/cooldown made shape-correct (`c09ef80`):** the cast **fill/drain**, **completion & interrupt bursts**, and
  the **finish flash** now source the hand `-base` mask / `-outer` art. **Cooldown sweep**: each shape has its own
  `-swipe` (generated — see learnings) so the sweep traces the silhouette (normal + LoC + charge cooldowns).
  **Completion burst got its own colour** (`db.castCompleteColor`, Config → Cast & channel → Complete color) — was
  Blizzard's native white.

### ★★ HARD-WON LEARNINGS this session (do NOT rediscover):
- **`hgAnchor` sizes a frame to 2× the icon** (the hand silhouette occupies the CENTRE half of its canvas, so mapping
  it onto the icon needs a 2× region). STATIC glows (outer/inner/finish-flash) NEED that 2× frame. But a **DRAINING
  rectangle must NOT use it** — the cast fill on a 2× frame drained over 2× the height, so only the middle 50% was
  ever visible → "cast bar starts at 25%, ends at 75%". The fill FRAME stays icon-sized; the MASK does the shaping.
- **The hand `-swipe` crop has NO art padding** (unlike the SDF swipe's 8px), so a hand cooldown anchors to the icon
  bounds EXACTLY — no `GROW_RATIO` grow (that overshot, worst on the long axis of 2:1/3:2), and no `+0.75px` AA fudge
  (a WHITE sweep makes any overshoot fringe visible; 0 is right since the swipe + icon mask share the reference rect).
- **One-shot alpha-0 suppression LOSES to Blizzard's cast animation**, which re-drives the InnerGlow alpha every
  frame — so a rounded-square overlay reappears mid-cast. Suppress it **every frame** in `CastFillOnUpdate` (same
  pattern already used for CastFill + the interrupt square).
- **Inner glow at btn+3** (above gradient +2, below text +4) is what keeps the keybind/count readable over the glow.
- **Cooldown swipe is engine-generated from the hand base** — `tools/generate-hand-swipes.py` (PIL): crop the icon
  reference rect (uniform 128px margin), resize to a SQUARE 256² pow2 (the squish is the PRE-DISTORTION — the
  cooldown frame's real aspect un-distorts it), bake 0.8 alpha (matches SDF `swipe_alpha`; `applySwipe` multiplies
  the user swipeAlpha on top). Re-run if a base changes. 21 `-swipe.png` in `Media/art/hand/`.
- **Three DISTINCT end-bursts, each its own colour** (don't conflate): cooldown **Finish flash** (Cooldown &
  availability — fires when an ability comes OFF cooldown, >2s GCD-filtered), cast **Complete color** (Cast &
  channel — successful cast/channel end), cast **Interrupt color** (cancelled cast). All separate events.

### ▶▶ NEXT (session 10) — in priority order
1. **Glow polish (small):** (a) the Config **preview pane's Proc + Cooldown chips still show the OLD SDF art** (the
   idle/hover/selected shape is correct; only those two animated chips lag) — point them at the multi-part glow /
   hand swipe. (b) **Per-state appearance independence** — Jason's note: hover SHOULD read subtler than proc/selected,
   but they share one glow with only per-colour/per-intensity control. Add per-state spread/softness (would also make
   the now-dead `stateWidth` "Glow width" control meaningful again for hand shapes).
2. **Animation layer (NEXT #3 — the fun one):** the rotating shine-chase Jason misses — a bright comet masked to the
   shape's rim, rotating, layered on the static glow. Works on any silhouette (one shared shine texture + a rim mask).
3. **Effects-matrix gaps (NEXT #4):** the last square art — `SpellHighlightTexture` (pulsing "press this"),
   `CooldownFlash` (GCD flipbook), `NewActionTexture`, flyout member background. See EFFECTS-MATRIX.md §B/§A/§I.
- **Anytime / smaller:** cast-glow brightness is coupled to the proc Brightness (`glowPeak`) — could get its own; the
  cast glow colour is fixed `CAST_TINT_G` (gold/lime) — could be a Config control; assist glow stays low-priority
  (don't iterate); the preview Cooldown chip; the SDF shape/old-bloom code is dormant (can be removed once nothing
  references it). Coexistence QA with ArcUI/EQOL re-enabled (our hover/flash/icon-vertex work touches more now).

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

## ▶▶ NEXT (session 9) — [DONE in session 9 — see the SESSION 9 block at the top of this file]
1. ✅ **Wire the multi-part glow to REAL triggers** — DONE. Proc/hover/selected/cast/channel/flash all drive
   the outer+inner+border glow, event-driven + per-shape, reconciled by source priority. (Session 9 PART B.)
2. ✅ **Real shape selection + persistence** — DONE. `db.handShape`/`db.sizeScale`, 21-preset Config picker,
   free width/height removed, uniform size scale, preview renders hand shapes. (Session 9 PART A.)
3. ⏳ **Animation layer** — still NEXT (session 10 #2). The rotating-shine chase; layers on the static glow.
4. ⏳ **Close the effects-matrix GAPS** — still NEXT (session 10 #3). `SpellHighlightTexture`, `CooldownFlash`
   (GCD flipbook), `NewActionTexture`, flyout background.
- Cleanup done/available: the `gbtest-glow-*` bake-off assets + `/gb glowstyle`/`glowtest` are now removable
  (triggers are wired); the per-axis border/aspect assumption is resolved (the shape picker sets the aspect).

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
| 7 | ALL states drive the multi-part shaped glow (proc/hover/selected/cast/channel/flash) per-shape | ✅ VERIFIED IN COMBAT (session 9) — every trigger reconciled by source priority; no secret reads |
| 8 | Cooldown sweep + cast fill/burst + finish flash trace the hand silhouette | ✅ VERIFIED (session 9) — hand `-swipe` generated from the base; fill/burst mask from `-base` |
| 9 | Per-trigger glow matrix (colour/opacity/layers/enable per state) + flash-square fix | ✅ VERIFIED IN-GAME (session 10) — GUI-configured; disabled trigger drops to next; no square on auto-attack |
| 10 | Per-trigger ANIMATION SYSTEM: Comet Chase rides the winning glow; masked rim-chase on any shape; per-state independent | ✅ VERIFIED IN-GAME (session 10) — GUI + preview; SetRotation under a fixed rim mask; one animation per state |
| 11 | Midnight duration-object proxy: GetActionCooldownDuration(ignoreGCD) → SetCooldownFromDurationObject → react to widget lifecycle = a combat-safe "real cooldown running" signal, no secret reads | ✅ VERIFIED IN-GAME (session 12) — drives plate dim-on-cooldown; GCDs never trigger it |

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
