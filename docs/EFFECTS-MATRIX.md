# Gloom's Bars — Blizzard Button Visual Effects Matrix (Phase 2)

> **Phase 2 of the shaped-glow rebuild** (see docs/SHAPE-CATALOG.md for Phase 1). This is the
> COMPLETE accounting of every visual an action button produces, taken directly from the client
> templates — `Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml`,
> `Shared/ActionButtonComponentTemplate.xml`, `Shared/ActionButtonSpellAlerts.xml` (build 12.0.7) —
> cross-checked against docs/API-NOTES.md. Every visual a button can show is in ONE of the tables
> below; nothing is left uncatalogued. Phase 3 works this list shape-by-shape.

**Status legend**
- ✅ **Handled** — mechanism is hooked/suppressed/replaced today (art may still need re-baking per the 21 silhouettes).
- 🟡 **Partial** — handled for some cases, gaps remain.
- ⛔ **GAP** — NOT handled today; Blizzard's square/centered art currently shows over a shaped icon.
- ➖ **Leave** — informational or no shape conflict; intentionally untouched.

**"Shape art?"** = does Phase 3 need to bake a per-silhouette texture for this (one of the 21 shapes)?

---

## A. Base icon & frame
| Element | Blizzard mechanism (atlas / driver) | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| `icon` | the spell texture (BACKGROUND) | — | ✅ | zoom-crop + shape mask; crop-to-fill on non-plated elongated |
| `IconMask` | `UI-HUD-ActionBar-IconFrame-Mask` (Blizzard's rounding) | **yes (mask)** | ✅ | replace with our per-silhouette mask (the 21) |
| `SlotBackground` / `SlotArt` | `…IconFrame-Background` / `…-slot` (square backdrop) | no | ✅ | suppress (Hide + re-assert `UpdateButtonArt`) |
| `NormalTexture` | `UI-HUD-ActionBar-IconFrame` (border frame 46×45) | no | ✅ | suppress `SetAlpha(0)` (re-shows on press → re-assert) |
| `PushedTexture` | `…IconFrame-Down` | no | ✅ | suppress |
| `Border` | `…IconFrame-Border` — **equipped-item green** border | no | ✅ | suppress + re-assert on equip/world events |
| `NewActionTexture` | `…IconFrame-Mouseover` — shown on a newly-placed action | **yes** | ⛔ **GAP** | suppress, or replace with a shaped one-shot |
| `LevelLinkLockIcon` | `QuestSharing-Padlock` (level-locked abilities) | no | ➖ Leave | informational; leave (revisit if it clashes) |

## B. State highlights (mouse / selection)
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| `HighlightTexture` (hover) | `…IconFrame-Mouseover` | **yes (ring)** | ✅ | our shaped state-ring art per silhouette |
| `CheckedTexture` (active/toggled) | `…IconFrame-Mouseover` | **yes (ring)** | ✅ | shaped ring (checked tint) |
| `Flash` (`$parentFlash`) | `…IconFrame-Flash`, shown by low-mana/attack flash | **yes** | ✅ | shaped flash art per silhouette |
| `SpellHighlightTexture` + `SpellHighlightAnim` | `…IconFrame-Mouseover`, ADD 0.4, **pulsing** (looping alpha) — "you should press this" highlight | **yes** | ⛔ **GAP** | suppress + drive our own shaped highlight, OR fold into the glow engine |

## C. Proc / activation glows — THE DIFFERENTIATOR
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| `SpellActivationAlert` (proc) | `ActionButtonSpellAlertManager:ShowAlert/HideAlert`; per-button 1.4× frame, `ProcStartFlipbook`/`ProcLoopFlipbook`/`ProcAltGlow` | **yes (glow)** | ✅ mechanism / 🟡 shape | **bake the shaped glow per silhouette** (the whole current effort) |
| Assisted-combat **highlight** | `AssistedCombatManager:SetAssistedHighlightFrameShown` → `AssistedCombatHighlightFrame.Flipbook` (`rotationhelper_ants_flipbook`) | **yes (glow)** | ✅ mechanism | shaped assist glow (blue); low priority per Jason |
| Assisted-combat **rotation** ActiveFrame | `ActionBarButtonAssistedCombatRotationTemplate.ActiveFrame`: `Border` `UI-HUD-RotationHelper-Active`, rotating `Glow` `…-Active-FX` (masked) | **yes** | 🟡 | reskin/suppress when rotation helper is on (only active with that feature) |

## D. Cast / channel / interrupt
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| Cast/channel **fill** | `SpellCastAnimFrame.Fill.CastFill` (`UI-HUD-ActionBar-Cast-Fill`, translating fill, masked by `FillMask`) | **yes** | ✅ | suppress + our own progress fill masked to the silhouette |
| Cast **inner glow** | `Fill.InnerGlowTexture` (`…Casting-InnerGlow`) | **yes (ring)** | ✅ | shaped inner ring per silhouette |
| Cast/channel **finish burst** | `EndBurst.GlowRing` (`…Casting-Complete-Glow`, Scale 0→5), `FinishCastAnim` | partial | ✅ | replay Blizzard's burst (masked `EndMask`); tint per event |
| **Interrupt** display | `InterruptDisplay` (`ActionButtonInterruptTemplate`): `.Base` `UI-HUD-ActionBar-Interrupt`, `.Highlight` `…-Interrupt-Highlight` | **yes** | ✅ | suppress + replay the finish burst tinted red |

## E. Cooldown
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| `cooldown` **swipe** | `CooldownFrameTemplate`, swipe `0,0,0,0.8`; drawEdge/drawBling=false in template | **yes (swipe)** | ✅ | shaped swipe texture per silhouette (square pow2, pre-distorted) |
| `cooldown` edge / bling | rotating edge + finish star — draw to SQUARE bounds, unshapeable | no | ✅ | suppressed (SETTLED) — replaced by our shaped finish flash |
| our **finish flash** | ours, on `OnCooldownDone`, GCD-filtered by game clock | **yes (glow)** | ✅ | shaped burst per silhouette (shares glow art) |
| `chargeCooldown` | template `drawSwipe=false` (edge-only) | **yes (swipe)** | ✅ | `SetDrawSwipe(true)` → shaped recharge sweep |
| `lossOfControlCooldown` | red swipe `0.17,0,0,0.8`, edge `UI-HUD-ActionBar-LoC` | **yes (swipe)** | 🟡 | shaped swipe; confirm edge suppressed |
| `CooldownFlash` (**GCD flash**) | `ActionButtonCooldownFlashTemplate.Flipbook` `UI-HUD-ActionBar-GCD-Flipbook`, 22-frame flipbook on GCD | **yes** | ⛔ **GAP** | suppress (our finish flash covers real CDs), or shape a GCD flash |

## F. Targeting / pet / misc
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| `TargetReticleAnimFrame` | green ground-target reticle, `UI-HUD-ActionBar-Target(+Highlight)`, rotating | no | ✅ | suppress `SetAlpha(0)` |
| `AutoCastOverlay` | `AutoCastOverlayTemplate` (pet autocast shine/sparkles) | maybe | ➖ Leave | pet bar (out of v1 bars 1–8); revisit with pet bar |

## G. Availability / range (react to rendered output — never read secret)
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| Usable / OOM / unusable tint | `UpdateUsable` sets `icon` vertex `1,1,1` / `0.5,0.5,1` / `0.4,0.4,0.4` | no | ✅ | react to the vertex (hook), our tint policy |
| Out-of-range | `ActionButton_UpdateRangeIndicator(self,checksRange,inRange)` hands us `inRange`; reddens `HotKey` | no | ✅ | desaturate+tint icon + match keybind color |
| Desaturation (untalented etc.) | `SetDesaturated` in `:Update` | no | ✅ | tracked (rec.gbDesat) so we don't fight Blizzard's |

## H. Text
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| `HotKey` | `NumberFontNormalSmallGray`, re-anchored in script; color reddened by range path | no | ✅ | keybind override (font/size/color/pos), Mac symbols, `UpdateHotkeys` re-assert |
| `Count` (stacks/charges) | `NumberFontNormal`, BOTTOMRIGHT | no | 🟡 | per-style override still backlog |
| `Name` (macro name) | `GameFontHighlightSmallOutline`, BOTTOM | no | 🟡 | per-style override still backlog |

## I. Flyout (spellbook/multi-action popups)
| Element | Blizzard mechanism | Shape art? | Status | Phase 3 action |
|---|---|---|---|---|
| Flyout arrow | `FlyoutButtonTemplate` `.Arrow` (`UI-HUD-ActionBar-Flyout*`) | maybe | ➖ | leave / revisit |
| Flyout button background | `ActionBarFlyoutButton-IconFrame` (square border on flyout members) | **yes** | ⛔ **GAP** | known deferred: suppress + shape the flyout member bg |

---

## Summary — what Phase 3 must produce
**Per-silhouette baked art** (× the 21 shapes): `mask`, state `ring` (hover/checked/flash), cooldown `swipe`, cast `inner-ring`, proc/finish `glow`. These five families are the shape-dependent core.

**Gaps to close** (currently square art leaking over shaped icons):
1. ⛔ `SpellHighlightTexture` (pulsing "press this" highlight) — suppress or fold into glow engine.
2. ⛔ `CooldownFlash` GCD flipbook — suppress (finish flash covers real CDs).
3. ⛔ `NewActionTexture` — suppress or shape.
4. ⛔ Flyout member background — suppress + shape (long-deferred).
5. 🟡 `lossOfControlCooldown` edge — confirm suppressed.

**Shape-agnostic (no per-shape art):** slot/border suppression, usable/range/OOM tints, text/keybind, reticle suppression, edge/bling suppression.

**Animation layer (Phase 3, on the shaped glow/ring/finish):** pulse (exists) → optional shine-sweep / rotation / chase, authored per silhouette since the perimeter is now known.

---

## Glow architecture — multi-part & tintable (DECIDED 2026-07-20, Jason's mockups)
Every glow — proc, state highlight (hover/checked), cast, finish flash — is the SAME three-part
system, differing only by tint colour + trigger. This SUPERSEDES the single soft-bloom and the
separate state "ring": it's the clean fix to "doesn't look like a glow / doesn't fit," because each
part is baked from the shape's own silhouette and the outer part sits UNDER the icon (so only clean
outward falloff shows).

1. **Outer glow** — a per-silhouette texture UNDER the icon, sized larger than it, = the shape +
   smooth outward falloff. The opaque icon covers the interior, so only the outward bloom peeks out
   around the edge → "perfect falloff." Tinted at runtime (`SetVertexColor`); blend mode tunable
   (alpha/colour glow vs ADD). Sits at the Border's draw sublevel (below `.icon`).
2. **Inner glow** — a per-silhouette texture OVER the icon, shape-baked with an inner-edge falloff
   that fades toward centre (the middle stays untinted). Tinted at runtime. Above `.icon`.
3. **Border recolour** — if the Border decoration is on, its colour is overridden to the glow colour
   while the glow is active (the border is OUR texture → runtime `SetVertexColor`). No border → no
   recolour. Border draws between outer glow and icon.

**Art per silhouette:** two tintable WHITE masters — `-glow-outer`, `-glow-inner` (× the 21 shapes).
Replaces the single `-glow` + the `-ring` families in the tables above. Lateral overlap onto flush
neighbours is acceptable (Jason: fine, maybe preferred) — governed by frame level, tunable later.

