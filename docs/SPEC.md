# Action Bar Restyle Addon — Project Spec (v0 — brainstorm seed)

> **Status:** starting point, distilled from a brainstorm during a GloomsAuras session (2026-07-13).
> Jason will expand this in the new project. Everything here is *discussed / reasoned*, not yet built
> or verified in-game. Items marked **⚠ VERIFY** are unproven and must be probed before relying on them.

---

## The idea (one sentence)
A **pure appearance layer** for the game's action bars — highly customized *look* for Blizzard's
**existing** action buttons — **without replacing them** (no custom secure buttons, no casting machinery).

## Why this, and not a full replacement
- Replacement addons (Bartender, Dominos, ElvUI bars) exist to give **layout freedom** (bars anywhere,
  any size/spacing) and **conditional paging** (bar swaps by stance/stealth/mount/vehicle). To own that
  behavior you must create your **own secure action buttons**.
- **Edit Mode has since absorbed most of the layout half** — move/scale/rows/columns/spacing/visibility
  for up to 8 bars, built in. So for most users the reason to *replace* has shrunk to edge-case paging
  and suite-wide theming.
- **The real gap today is beautiful appearance** — especially **glows and cooldown sweeps that follow
  rounded / non-square icons.** Most restyle addons (e.g. EllesmereUI) leave those as **square rectangle
  glows on rounded icons → looks wrong.** That's the differentiator this addon targets.
- **Design bet:** let **Edit Mode own geometry**, this addon owns **look**. Result: lightweight, and it
  **completely sidesteps the secure-button / taint / combat-lockdown nightmare** of replacements.

## The one principle that matters
**Never replace Blizzard's secure buttons — only restyle them. Style Blizzard's *rendered output* and
*react to Blizzard's events*; never *compute* combat state from secret data.** Everything hard about
replacements (taint, secure state drivers, casting in combat) is avoided by staying an appearance layer.

## Environment
- WoW **Midnight 12.0.7** (Interface `120007`), retail — same target as GloomsAuras.
- The **secret-value model applies** (combat aura/cooldown/charge data is tainted/secret to addon code) —
  we know this well from GloomsAuras. It mostly *doesn't* bite a restyle addon, because we style Blizzard's
  displays rather than read the underlying values. The exceptions are called out below.
- Author "Gloom" / guild Hand of Devastation. Sibling to GloomsAuras + GloomsBuildBarn — reuse their idioms.

---

## Feature scope (from the brainstorm)

### A. Icon appearance — combat-safe, anytime (pure visual)
- **Aspect ratio (3:2 and others)** — the button *frame* is sized to 3:2 (out of combat, see §Walls); the
  square icon art is **cropped to the frame via `SetTexCoord`** (anytime). Tradeoff: cropping a square icon
  to 3:2 loses a little top/bottom (or stretch = distortion). Inherent, not a bug.
- **Rounded corners** — `MaskTexture` (a rounded-rect mask PNG) on the icon. **⚠ VERIFY masks render in
  Midnight** (GloomsAuras flagged this as unconfirmed).
- **Zoom levels** — `SetTexCoord` crop inward. Anytime.

### B. Geometry — OUT OF COMBAT ONLY (protected frames) — ⚠ SCOPE FORK
- **Per-icon sizing** and **gaps between icons** are doable, but resizing/repositioning secure buttons is
  **combat-locked**, and Blizzard re-applies its own layout on Edit-Mode/spec/vehicle changes — so you must
  **re-assert your geometry out of combat + after every Blizzard relayout.** That "dance" is the fiddliest
  part of any bar addon.
- **DECISION TO MAKE:** *pure skin* (Edit Mode owns 100% of geometry, addon touches only textures/fonts —
  cleanest, zero reposition headaches) **vs** *skin + sizing/gaps* (nicer control, pulls in the re-assert
  dance). Recommend starting **pure skin**, add geometry later if wanted.

### C. Text — combat-safe, anytime
- **Keybind / hotkey text** (`.HotKey`) — full control of **font, color, size, position**. Plain FontString,
  no restrictions (a keybind isn't secret). Easiest win.
- **Macro name** (`.Name`) and **stack/charge count** (`.Count`) — same, plain FontStrings.
- **Cooldown countdown number** — you **can restyle Blizzard's own** (font/size/color; position is more
  constrained since the cooldown widget manages it). What you **cannot** do is draw your **own** number by
  reading remaining time — that read is the **secret wall**. (OmniCC-style custom timers hit this in combat.)

### D. Dynamic visuals — react to Blizzard's events/state (combat-safe unless noted)
- **Cooldown swipe/animation** — Blizzard drives it; keeps working. Style: `SetSwipeColor`, edge texture,
  and the finish "bling" flash via `SetDrawBling(false)`. **On rounded icons the radial swipe stays squarish
  unless masked** — same shape trick as the glows (see below).
- **Proc glows** — **THE DIFFERENTIATOR.** Blizzard fires `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` (plain
  events) on a proc; we hook those and substitute our **own shape-matched glow.** Combat-safe (react to an
  event, never read a secret). Full creative control. See the deep dive.
- **Out-of-range coloring** — Blizzard's own (red keybind on out-of-range) keeps working. **Custom** range
  tinting needs to *read* range state (`IsActionInRange`), which is **⚠ VERIFY — may be restricted in Midnight
  combat** (same secret-value family). If walled, fall back to restyling Blizzard's own indicator.

### E. Keybinds — assign/modify from the addon (OUT OF COMBAT only)
- `SetBinding` / `SetBindingSpell` / `SetBindingMacro` / `SetBindingClick`, or `SetOverrideBinding*`, plus
  `SaveBindings()` to persist and `GetBindingKey` / `GetBindingAction` to read. Hover-to-bind flows + saved
  binding profiles are all feasible (cf. Clique). **Changing a binding is combat-locked** (existing binds
  fire in combat fine; you just can't rebind mid-fight — defer to OOC).

---

## The differentiator, in depth: shape-matched glows & sweeps
**Why other addons look bad:** their glows are **rectangle tracers** —
- Blizzard's default proc glow = a fixed rectangular animated texture sized to the button.
- LibCustomGlow (pixel glow / autocast ants) = traces the button's **bounding rectangle**, sharp corners.
Neither follows the icon's actual shape, so on a 3:2 rounded icon you get a sharp-cornered rectangle glow
floating around a rounded icon. (GloomsAuras hit this exact wall: LibCustomGlow "traces the frame rectangle,
not the texture's alpha shape.") **Not a WoW limit — a limit of that glow *technique*.**

**How to do better (both combat-safe — triggered by Blizzard's proc event):**
1. **Baked, shape-matched glow art (simplest, cleanest):** author the glow as a texture that already *is* a
   3:2 rounded-rect soft halo / ring, sized to the button; animate via alpha pulse / rotation / shine sweep.
   The shape is in the art, so it matches perfectly — rounded corners and all.
2. **Masked glow:** apply a rounded-rect mask (sized to the glow's outer extent, not the icon exactly) to a
   glow texture, clipping it to the shape.

**Nuances:**
- **Aspect ratio (3:2) alone is the easy half** — even LibCustomGlow follows whatever *rectangle* you give
  it; it's the **rounded corners** that need the texture/mask approach.
- **Moving-ants-around-the-perimeter is the hard style to round** (spawning particles along a rounded path).
  A soft pulsing **halo** or shaped **shine** looks better on rounded icons anyway and is far easier.
- **Rounded-rect + circle are very coverable** with a few baked textures. **Arbitrary** shapes need per-shape
  art (WoW can't derive a glow from an icon's alpha automatically).
- **The same mask trick fixes the square cooldown-sweep-on-rounded-icon** problem.

This is the whole reason the project is worth doing: purpose-built, shape-matched proc glows + sweeps are a
genuine, underserved differentiator.

---

## Walls / NOT allowed (hard constraints)
1. **Move / resize / show / hide buttons = OUT OF COMBAT only** (protected frames). Set on load + on
   `PLAYER_REGEN_ENABLED`, and re-assert after Blizzard re-lays-out (Edit Mode, spec, vehicle, stance).
2. **No reading secret combat values** to compute custom displays — cooldown remaining, charges, resource
   cost, and **possibly** range/usability. Style Blizzard's versions instead.
3. **Keybind changes = OUT OF COMBAT only.**

## Building blocks / technical approach (confirm exact names vs client source when building)
- **Hook Blizzard's action-button update functions** to (re)apply styling (icon texcoord, mask, fonts).
- **`MaskTexture`** for rounded/shaped icons *and* glows; **`SetTexCoord`** for crop / zoom / aspect.
- **Proc glow:** `hooksecurefunc` the overlay-glow show/hide (or the events `SPELL_ACTIVATION_OVERLAY_GLOW_
  SHOW/HIDE`), draw a custom shaped glow. (LibCustomGlow is available but its rectangle limit is *why* we go
  custom for shaped icons.)
- **Cooldown widget:** `SetSwipeColor` / `SetDrawBling(false)` / `SetDrawEdge`; restyle the count font.
- **Geometry (if in scope):** defer to `PLAYER_REGEN_ENABLED`; hook Blizzard's bar layout to re-assert.
- **Bundle art:** shaped glow textures (rounded-rect + circle to start), rounded-rect masks, borders.

## Reuse from GloomsAuras (big head start)
Config toolkit / widget framework, media + bundled-font handling, the design language + tokens
(navy/purple/orange, Khand/GeneralSans), LibCustomGlow + MaskTexture experience, the `wow-addon-dev` skill
(secret-values, widget-framework, toc-structure, common-patterns), and hard-won secret-value knowledge.

## Open decisions (Jason to resolve in the new project)
- **Pure skin vs skin+geometry** (the §B fork). Recommend pure skin first.
- **Name** (TBD). Namespace + SavedVariables + slash command (avoid `/ga`, `/glooms`).
- **Masque dependency vs standalone** skinning.
- **Which bars** to support (main, bonus/2–8, pet, stance/form, extra-action, vehicle-leave).
- **Glow art set** to author (rounded-rect, circle, …); animation styles (halo / shine / pulse).

## ⚠ Needs verification before building (verify-before-claiming)
- **`MaskTexture` renders in Midnight** (rounded corners depend on it).
- **`IsActionInRange` / `IsUsableAction` readability in Midnight combat** (decides if custom range/usable
  tinting is possible, or if we must style Blizzard's own).
- **Exact Blizzard action-button + cooldown API / hook points** — check the client's
  `Blizzard_ActionBar*` / secure-template source, as we did for the Cooldown Manager in GloomsAuras.

## How to work with Jason (carries over — also in his global memory)
- **Non-developer.** He sets requirements + does in-game QA; Claude writes all code + research.
- **ONE instruction at a time** for testing; never batch QA steps.
- **Verify before claiming** — never say it works until confirmed in docs AND in-game; frame builds as
  hypotheses to test.
- **Enable Lua errors during QA** (WoW hides them; silent throws look like "nothing happens"). Ask for the
  BugSack error text FIRST when something misbehaves.
- **Prefer sliding switches** over checkboxes for on/off; **no native Blizzard UI** textures/widgets (use
  toolkit widgets + bundled PNG icons); **pixel-perfect** to any mock, every pass.
