# Gloom's Bars — project guide

> **▶ NEW SESSION: read [docs/HANDOFF.md](docs/HANDOFF.md) FIRST.** It has current build
> state, settled decisions (do not relitigate), verification gates, how Jason works, and
> the next steps. Then this file (conventions), [docs/API-NOTES.md](docs/API-NOTES.md)
> (verified client facts — button anatomy, mask rules), [docs/SPEC.md](docs/SPEC.md)
> (the design brief), and `docs/wow-addon-dev/` (vendored addon-dev skill).

Bespoke WoW addon: a **pure appearance layer** for Blizzard's built-in action bars —
rounded/3:2 icons, restyled text, and **shape-matched proc glows + cooldown sweeps** (the
differentiator). Target: **Midnight 12.0.7** (Interface `120007`), retail only. Third
sibling to GloomsAuras + GloomsBuildBarn (author "Gloom", guild Hand of Devastation).

## The one principle that matters
**Never replace Blizzard's secure buttons — only restyle them.** Style Blizzard's
*rendered output* and *react to Blizzard's events*; never *compute* combat state from
secret data. Edit Mode owns geometry; this addon owns look. Everything hard about bar
replacements (taint, secure state drivers, combat lockdown) is avoided by staying an
appearance layer.

Hard walls (from [docs/SPEC.md](docs/SPEC.md)):
- Move/resize/show/hide of secure buttons: OUT OF COMBAT only (and v1 doesn't do it at all — pure skin).
- No reading secret combat values (cooldown remaining, charges, possibly range/usability).
- Keybind changes: OUT OF COMBAT only.

## Settled decisions (2026-07-18 — do not reopen without Jason)
- **Pure skin v1** — Edit Mode owns 100% of geometry; addon touches only textures/masks/fonts/glows. Sizing/gaps = possible later phase.
- **Bars 1–8** (the Edit-Mode action bars) in v1; pet/stance/extra-action/vehicle-leave later.
- **Standalone skinning** — no Masque integration.
- **Slash `/gb`** (long-form alias `/gloomsbars`). `/ga` = GloomsAuras, `/glooms` = Build Barn.

## Conventions
- Namespace `GB` → `_G.GloomsBars`; SavedVariables `GloomsBarsDB`.
- Plain frames, plain SavedVariables, no Ace3. Libraries only via `.pkgmeta` externals when needed.
- **In-game UI follows the GloomsAuras design language**: same tokens (bright purple
  `#936bff` on near-black navy, Khand titles + GeneralSans body — already in `Core.lua`
  `GB.COLOR`/`GB.FONT`), sliding switches not checkboxes, no native Blizzard UI
  textures/widgets, pixel-perfect to mocks. Jason has **Figma mockups for GloomsAuras**
  to reference as the styling basis (Figma desktop MCP tools may be available; otherwise ask him for screenshots).
- Reuse GloomsAuras's config toolkit patterns (`/Users/jasonstone/GloomsAuras/Config.lua`) when the options UI phase starts.

## Files
- `GloomsBars.toc` — manifest (Interface 120007).
- `Core.lua` — namespace, tokens, saved vars, bar/button census (`GB.BARS`, `GB:ForEachButton`), `/gb` router + probes.
- `Skin.lua` — GB.Skin engine v0: zoom+mask+art-suppression across all 8 bars, re-assert hooks, persisted toggle.
- `Media/masks/` — bundled mask PNGs (script-generated; edge-padding rule in API-NOTES §2).
- (Later phases) `Glows.lua`, `Cooldowns.lua`, `Config.lua`.

## Testing workflow
The repo root **is** the addon folder, symlinked into the client at
`/Applications/World of Warcraft/_retail_/Interface/AddOns/GloomsBars`.
QA is done by Jason (non-developer): give ONE copy-paste instruction at a time, verify
before claiming, and when something misbehaves ask for the **BugSack error text first**.

## Git / releases
GitHub Releases via BigWigs packager (`.github/workflows/release.yml`), fired by pushing
a version tag (e.g. `v0.1.0`). WoWUp installs/auto-updates from the repo URL. No
CurseForge/Wago. `## Version: @project-version@` in the TOC is filled by the packager.
