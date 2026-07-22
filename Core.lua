-- Core.lua — Gloom's Bars
--
-- Pure appearance layer for Blizzard's action bars on WoW Midnight (12.0+).
-- The one principle (docs/SPEC.md): NEVER replace Blizzard's secure buttons —
-- only restyle their rendered output and react to Blizzard's events. Edit Mode
-- owns geometry; this addon owns look. That sidesteps the taint / combat-
-- lockdown machinery of full bar replacements entirely.
--
-- This file: namespace (_G.GloomsBars = GB), saved variables, design tokens,
-- and the /gb slash router with the session-1 probes (/gb debug, /gb mask).

local ADDON_NAME = ...

local GB = {}
_G.GloomsBars = GB
GB.ADDON_NAME = ADDON_NAME

local PREFIX = "|cff936bffGloom's Bars|r"   -- bright purple, matches the sibling addons
GB.PREFIX = PREFIX

local function msg(text)
  print(PREFIX .. ": " .. tostring(text))
end
GB.msg = msg

-- ---------------------------------------------------------------------------
-- Design tokens — shared skin with Gloom's Auras / Build Barn (same author).
-- Bright-purple accent on a near-black navy plate, condensed Khand titles +
-- GeneralSans body. Fonts bundled in Media/fonts/.
-- ---------------------------------------------------------------------------
local function color(hex)
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  return { r = r, g = g, b = b, hex = hex }
end
GB.COLOR = {
  purple = color("936bff"),  -- bright purple — accents, selection, buttons
  heroic = color("8031ff"),  -- deep purple
  green  = color("20ba56"),  -- confirm green
  red    = color("c41e3a"),  -- destructive
  orange = color("ff7729"),  -- warning / accent
  -- Panel base: pre-compensated so #060714 lands on screen (see GloomsAuras Core.lua).
  dark   = { r = 18/255, g = 19/255, b = 31/255, a = 1 },
  rim    = { r = 1, g = 1, b = 1, a = 0.10 },
}

GB.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

-- ---------------------------------------------------------------------------
-- Shape registry — the skin engine is SHAPE-AGNOSTIC (Jason's requirement:
-- flexibility on icon shape/size/aspect). Every shape is a data entry whose
-- three PNGs come from tools/generate-art.py (bundled art, edge-padded — see
-- API-NOTES §2). Selected via GB.db.shape (/gb shape <name>; applies on
-- /reload — live-swapping masks trips the no-re-render quirk). Future:
-- per-bar shapes, aspect-ratio letterbox entries (3:2), §B size/gap fork.
-- ---------------------------------------------------------------------------
local function shape(name)
  return {
    mask  = GB.MEDIA .. "masks\\" .. name .. ".png",
    swipe = GB.MEDIA .. "masks\\" .. name .. "-swipe.png",
    ring  = GB.MEDIA .. "art\\" .. name .. "-ring.png",
    glow  = GB.MEDIA .. "art\\" .. name .. "-glow.png",   -- proc halo (edge at 96/128)
  }
end
GB.SHAPES = {
  circle = shape("circle"),
  roundrect = shape("roundrect"),
  square = shape("square"),
  hexagon = shape("hexagon"),   -- pointy-top regular hex (honeycomb grids); fixed shape like circle
}
-- Per-corner rounding (Jason 2026-07-18): every corner is independently round or
-- sharp, all rounded corners sharing one radius. The masks (from generate-art.py)
-- span the full 16 on/off patterns × 4 radius levels: "corner-<TL><TR><BL><BR>-r
-- <N>". The Config UI's four corner toggles pick the pattern, the radius slider
-- picks the level. corner-1111-r* == roundrect at that radius, corner-0000-r0 ==
-- square. Masks verified to carry the right silhouette.
for level = 0, 5 do
  for bits = 0, 15 do
    local tl = math.floor(bits / 8) % 2
    local tr = math.floor(bits / 4) % 2
    local bl = math.floor(bits / 2) % 2
    local br = bits % 2
    local name = ("corner-%d%d%d%d-r%d"):format(tl, tr, bl, br, level)
    GB.SHAPES[name] = shape(name)
  end
end

function GB:GetShape()
  return GB.SHAPES[(GB.db and GB.db.shape) or "circle"] or GB.SHAPES.circle
end

-- ---------------------------------------------------------------------------
-- Hand-authored preset silhouettes — the frozen catalog (docs/SHAPE-CATALOG.md,
-- assets docs/ART-SPEC.md). The shaped-glow pivot (session 8): free width/height
-- is retired; the icon is ONE of these 21 presets + a uniform size scale, so the
-- silhouette can never warp. Each entry: aspect = long/short side ratio, orient =
-- which axis is the long one ("square" = 1:1). The engine derives the icon's W/H
-- from aspect × orient × naturalSize × sizeScale, so a shape is always the right
-- proportion (no manual sizing). Files: Media/art/hand/<key>-base|-outer|-inner.png.
-- ---------------------------------------------------------------------------
local HAND_DEF = {  -- { key, aspect, orient, label }, in picker order
  -- 1:1 footprint
  { "circle",        1,   "square",    "Circle" },
  { "square",        1,   "square",    "Square" },
  { "roundsq1",      1,   "square",    "Rounded 1" },
  { "roundsq2",      1,   "square",    "Rounded 2" },
  { "roundsq3",      1,   "square",    "Rounded 3" },
  { "hexagon",       1,   "square",    "Hexagon" },
  { "diamond",       1,   "square",    "Diamond" },
  { "tombstone",     1,   "square",    "Tombstone" },
  { "tombstone-inv", 1,   "square",    "Tombstone (inv.)" },
  -- portrait-elongated (3:2 & 2:1) — these carry the plate-extension option
  { "pill32",        1.5, "portrait",  "Pill 3:2" },
  { "pill21",        2,   "portrait",  "Pill 2:1" },
  { "square32",      1.5, "portrait",  "Tall square 3:2" },
  { "square21",      2,   "portrait",  "Tall square 2:1" },
  { "roundsq1-32",   1.5, "portrait",  "Tall rounded 1 · 3:2" },
  { "roundsq1-21",   2,   "portrait",  "Tall rounded 1 · 2:1" },
  { "roundsq2-32",   1.5, "portrait",  "Tall rounded 2 · 3:2" },
  { "roundsq2-21",   2,   "portrait",  "Tall rounded 2 · 2:1" },
  { "roundsq3-32",   1.5, "portrait",  "Tall rounded 3 · 3:2" },
  { "roundsq3-21",   2,   "portrait",  "Tall rounded 3 · 2:1" },
  -- landscape-elongated (3:2 & 2:1) — no plate extension
  { "square32w",     1.5, "landscape", "Wide square 3:2" },
  { "square21w",     2,   "landscape", "Wide square 2:1" },
}
GB.HAND_SHAPES = {}   -- key → { aspect, orient, label }
GB.HAND_ORDER  = {}   -- ordered list of keys (picker order)
for _, d in ipairs(HAND_DEF) do
  GB.HAND_SHAPES[d[1]] = { aspect = d[2], orient = d[3], label = d[4] }
  GB.HAND_ORDER[#GB.HAND_ORDER + 1] = d[1]
end
-- Grouped for the Config picker (grouped thumbnail grid).
GB.HAND_GROUPS = {
  { title = "1:1", keys = { "circle", "square", "roundsq1", "roundsq2", "roundsq3",
                            "hexagon", "diamond", "tombstone", "tombstone-inv" } },
  { title = "Portrait", keys = { "pill32", "pill21", "square32", "square21",
                                 "roundsq1-32", "roundsq1-21", "roundsq2-32", "roundsq2-21",
                                 "roundsq3-32", "roundsq3-21" } },
  { title = "Landscape", keys = { "square32w", "square21w" } },
}

-- Media paths for a hand silhouette's three assets (base = icon mask; outer/inner
-- = the multi-part glow, wired to triggers in a later step).
function GB:HandAsset(key, part)
  return GB.MEDIA .. "art\\hand\\" .. key .. "-" .. (part or "base") .. ".png"
end

-- The active hand-shape key (db-backed) + its metadata; nil until first-run
-- migration sets it. Falls back to "circle" so callers never nil-index.
function GB:HandShapeKey() return GB.db and GB.db.handShape end
function GB:HandShapeInfo(key)
  key = key or (GB.db and GB.db.handShape)
  return (key and GB.HAND_SHAPES[key]) or GB.HAND_SHAPES.circle
end

-- ---------------------------------------------------------------------------
-- Style recipes — the DESIGN NORTH STAR (docs/HANDOFF.md): a style is DATA
-- (decoration layers + text overrides); the engine in Skin.lua interprets it.
-- v0 supports layer kind "gradient" (a shape-clipped gradient plate) and a
-- HotKey override (position on a layer, font/size/color). The Config UI will
-- eventually edit these recipes; /gb style <name> switches live meanwhile.
-- ---------------------------------------------------------------------------
GB.STYLES = {
  none = {},
  -- Jason's mockup (2026-07-18): the button is TALLER than the icon — extra
  -- real estate below it (the "extension"), an orange gradient filling the
  -- extension and fading up into the icon, keybind centered in the extension.
  -- The whole construction (icon + extension) is wrapped in one shape.
  plate = {
    construction = { extendBottomPct = 0.40 },   -- extension height, % of icon height
    layers = {
      -- Figma reference (2026-07-18): fade begins at the icon's vertical
      -- midpoint (bleedPct 0.5), full opacity at its bottom edge, solid below.
      { kind = "gradient", zone = "extension", bleedPct = 0.5,
        color = { 1, 0.47, 0.16 }, fromAlpha = 1, toAlpha = 0 },
    },
    hotkey = {
      zone = "extension",
      font = "label", size = 13, flags = "OUTLINE",
      color = { 1, 1, 1 },
    },
  },
}

-- A style is DATA. GB.STYLES are code starter-templates; the ACTIVE style is a
-- user document in SavedVariables (GB.db.styleData), edited by the Config UI.
local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end
GB.deepcopy = deepcopy

function GB:GetStyle()
  if GB.db and GB.db.styleData then return GB.db.styleData end
  return GB.STYLES[(GB.db and GB.db.style) or "none"] or GB.STYLES.none
end
local FONT_DIR = GB.MEDIA .. "fonts\\"
GB.FONT = {
  title = FONT_DIR .. "Khand-SemiBold.ttf",
  head  = FONT_DIR .. "Khand-Medium.ttf",
  body  = FONT_DIR .. "GeneralSans-Regular.ttf",
  bodyM = FONT_DIR .. "GeneralSans-Medium.ttf",
  label = FONT_DIR .. "GeneralSans-Semibold.ttf",
}

-- Our bundled fonts exposed to LibSharedMedia under friendly names, so they show
-- in GB's own font picker alongside every other addon's LSM fonts (and become
-- usable by other LSM-aware addons — same idea as StoneTweaks). Name → path.
GB.BUNDLED_FONTS = {
  ["Khand SemiBold"]       = FONT_DIR .. "Khand-SemiBold.ttf",
  ["Khand Medium"]         = FONT_DIR .. "Khand-Medium.ttf",
  ["GeneralSans"]          = FONT_DIR .. "GeneralSans-Regular.ttf",
  ["GeneralSans Medium"]   = FONT_DIR .. "GeneralSans-Medium.ttf",
  ["GeneralSans SemiBold"] = FONT_DIR .. "GeneralSans-Semibold.ttf",
}

-- LibSharedMedia-3.0 is a LibStub singleton shared across all addons; BugSack,
-- ArcUI, EnhanceQoL, ElvUI etc. all embed it, so it's effectively always loaded.
-- We consume it if present (nil if truly absent — the picker then falls back to
-- the bundled fonts). We do NOT embed our own copy (yet); see docs backlog.
function GB.GetLSM()
  return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end
-- Register our bundled fonts into LSM (call at login, when all addons are up).
-- Register returns false if the name is already taken by another addon — harmless.
local function RegisterMedia()
  local lsm = GB.GetLSM()
  if not lsm then return end
  for name, path in pairs(GB.BUNDLED_FONTS) do lsm:Register("font", name, path) end
end

function GB:Version()
  local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
  if type(v) ~= "string" or v == "" or v:find("@") then return "dev" end
  return v
end

-- Pre-warm the bundled TTF fonts at login so first-session labels never render
-- blank (same fix as GloomsAuras: WoW may not finish loading a runtime custom
-- font before the first frame that uses it is built).
local function PreloadFonts()
  local warmer = CreateFrame("Frame", nil, UIParent)
  warmer:SetPoint("TOPLEFT"); warmer:SetSize(1, 1); warmer:SetAlpha(0)
  GB._fontWarmer = warmer
  for _, path in pairs(GB.FONT) do
    local fs = warmer:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT")
    if fs:SetFont(path, 14, "") then
      fs:SetText("Ag")
      fs:GetStringWidth()
    end
  end
end

-- ---------------------------------------------------------------------------
-- The 8 Edit-Mode action bars and their button globals.
-- ⚠ HYPOTHESIS (verify via /gb debug in-game): these are the retail global
-- names as of Dragonflight+; confirm they still exist in Midnight 12.0.7.
-- ---------------------------------------------------------------------------
GB.BARS = {
  { key = "bar1", label = "Action Bar 1", buttonPrefix = "ActionButton" },
  { key = "bar2", label = "Action Bar 2", buttonPrefix = "MultiBarBottomLeftButton" },
  { key = "bar3", label = "Action Bar 3", buttonPrefix = "MultiBarBottomRightButton" },
  { key = "bar4", label = "Action Bar 4", buttonPrefix = "MultiBarRightButton" },
  { key = "bar5", label = "Action Bar 5", buttonPrefix = "MultiBarLeftButton" },
  { key = "bar6", label = "Action Bar 6", buttonPrefix = "MultiBar5Button" },
  { key = "bar7", label = "Action Bar 7", buttonPrefix = "MultiBar6Button" },
  { key = "bar8", label = "Action Bar 8", buttonPrefix = "MultiBar7Button" },
}
GB.BUTTONS_PER_BAR = 12

-- Iterate every existing action button: callback(button, barInfo, index).
function GB:ForEachButton(callback)
  for _, bar in ipairs(GB.BARS) do
    for i = 1, GB.BUTTONS_PER_BAR do
      local button = _G[bar.buttonPrefix .. i]
      if button then callback(button, bar, i) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------
local DB_DEFAULTS = {
  schema = 1,
  shape = "circle",        -- key into GB.SHAPES
  style = "none",          -- key into GB.STYLES
  zoom = 0.08,             -- icon zoom-crop (SetTexCoord inset); live via Skin:SetZoom
  -- Shaped-glow pivot (session 8): the icon is one of 21 preset silhouettes
  -- (handShape, a GB.HAND_SHAPES key) + a uniform size scale — free width/height
  -- is retired (it warped the silhouette/glow). iconW/iconH are still WRITTEN by
  -- the engine (derived from the shape's aspect × sizeScale) so downstream anchor
  -- math is unchanged; they're just no longer user-facing. handShape is seeded on
  -- first run from the legacy shape (migration below).
  sizeScale = 1,           -- uniform icon size multiplier (× the Edit-Mode button size)
  iconLockAspect = true,   -- keep the width:height RATIO while sizing (not force square)
  iconAspect = 1,          -- the locked height/width ratio (captured when lock is enabled)
  iconFill = "fill",       -- "fill" (cover: keep art aspect, crop) or "stretch"
  sweepOvershoot = 0.75,   -- px the cooldown sweep extends past the icon circle
  -- Empty-slot treatment (Config → Empty slots): "normal" | "dim" | "hide".
  -- Alpha-only — the secure button is never shown/hidden (pure-skin wall).
  emptySlots = "normal",
  emptySlotAlpha = 0.35,   -- button alpha in "dim" mode
  -- Cooldown sweep appearance (Config → Cooldown & availability).
  swipeColor = { 0, 0, 0 },        -- cooldown sweep tint (SetSwipeColor rgb)
  swipeAlpha = 0.8,                -- cooldown sweep opacity (SetSwipeColor alpha; template default)
  -- Finish flash: OUR OWN shape-masked burst on cooldown-end (Blizzard's square
  -- edge/bling are suppressed — they can't follow a non-square shape). Fired from
  -- the Cooldown's OnCooldownDone event (no secret read); GCD skipped by timing.
  finishFlash = false,             -- enable the shaped finish flash
  finishFlashColor = { 1, 0.9, 0.5 },   -- its tint
  -- Availability: restyle Blizzard's usable/unusable/out-of-mana icon tint. We
  -- REACT to the vertex colour Blizzard's UpdateUsable sets (usable 1,1,1 / OOM
  -- 0.5,0.5,1 / unusable 0.4,0.4,0.4) — never reading IsUsableAction ourselves.
  -- Defaults = Blizzard's own values, so nothing changes until edited.
  availDesaturate = false,         -- desaturate (grey out) unusable abilities
  availUnusable = { 0.4, 0.4, 0.4 },   -- icon tint when unusable
  availOOM = { 0.5, 0.5, 1 },          -- icon tint when out of mana/power
  -- Out-of-range: tint the icon to match Blizzard's red out-of-range keybind. We
  -- REACT to ActionButton_UpdateRangeIndicator (Blizzard passes us inRange) — no
  -- IsActionInRange call. Off by default; default tint ≈ Blizzard's RED_FONT_COLOR.
  rangeTint = false,
  rangeColor = { 1, 0.2, 0.2 },
  -- State-highlight tints (hover/selected/flash) + intensity + spread — Config-editable.
  stateColors = { hover = { 1, 0.82, 0.35 }, selected = { 0.45, 0.75, 1 }, flash = { 1, 0.25, 0.25 } },
  stateIntensity = 1,
  stateWidth = 0.5,        -- "Glow width": how far the highlight ring spreads (0..1 → anchor grow)
  -- Custom cast/channel fill (replaces Blizzard's square drain — pill-shaped).
  castFillColor = { 1, 0.85, 0.4 },   -- tint
  castFillAlpha = 0.55,               -- opacity
  castDrainDir = "up",                -- "up" | "down" | "left" | "right" (edge the fill grows from)
  castInterruptColor = { 1, 0.25, 0.25 },   -- interrupt/cancel burst tint (Blizzard's completion burst, replayed red)
  castInterruptSpeed = 0.6,                 -- cancel-burst speed vs Blizzard's default (<1 = slower)
  castCompleteColor = { 1, 0.9, 0.5 },      -- successful cast/channel completion burst tint (was native white)
  -- Proc glow (Glows.lua) — the shaped halo; controls to fight "hard to see".
  glowColor = { 1, 0.85, 0.35 },      -- standard proc tint (gold)
  glowAssistColor = { 0.4, 0.75, 1 }, -- assisted-highlight tint (blue)
  glowIntensity = 0.9,                -- PEAK glow alpha (Brightness); the pulse always dips below it
  glowScale = 128 / 80,               -- halo size × icon (matches Glows.GLOW_SCALE; wide bloom past the rim)
  glowPulseSpeed = 1,                 -- pulse speed multiplier (higher = faster)
}

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    GloomsBarsDB = GloomsBarsDB or {}
    for k, v in pairs(DB_DEFAULTS) do
      if GloomsBarsDB[k] == nil then GloomsBarsDB[k] = v end
    end
    GB.db = GloomsBarsDB
    -- Promote the active style to an editable saved document on first run (from
    -- the previously-selected starter template, so existing looks carry over).
    if GB.db.styleData == nil then
      GB.db.styleData = deepcopy(GB.STYLES[GB.db.style] or GB.STYLES.none)
    end
    -- Migrate legacy shape keys to the radius-suffixed scheme (r2 ≈ old 0.25).
    local sh = GB.db.shape
    if sh == "roundrect" then GB.db.shape = "corner-1111-r2"
    elseif sh == "square" then GB.db.shape = "corner-0000-r0"
    elseif type(sh) == "string" and sh:match("^corner%-%d%d%d%d$") then GB.db.shape = sh .. "-r2" end
    -- Per-corner MIXING removed (2026-07-19): a mixed pattern can't render cleanly
    -- on a non-square icon. Collapse any mixed shape to all-rounded at its radius
    -- (the pill); keep all-round and all-sharp (square) as they are.
    local pat, r = tostring(GB.db.shape):match("^corner%-(%d%d%d%d)%-r(%d)$")
    if pat and pat ~= "1111" and pat ~= "0000" then GB.db.shape = "corner-1111-r" .. r end
    -- Proc-glow art rebuilt with a WIDER bloom (2026-07-19): its natural size
    -- changed, so reset the saved glow Size ONCE to the new default (re-tunable).
    if not GB.db.glowWideBloom then GB.db.glowScale = 128 / 80; GB.db.glowWideBloom = true end
    -- Shaped-glow pivot (session 8): seed handShape from the legacy SDF shape so
    -- the look carries over (circle→circle, square→square, hexagon→hexagon, any
    -- rounded corner-shape→a medium rounded square, else circle). Only once.
    if GB.db.handShape == nil then
      local legacy = tostring(GB.db.shape)
      local seed = "circle"
      if legacy == "square" or legacy == "corner-0000-r0" then seed = "square"
      elseif legacy == "hexagon" then seed = "hexagon"
      elseif legacy:match("^corner%-%d%d%d%d%-r%d$") then seed = "roundsq2" end
      GB.db.handShape = seed
    end
    -- Per-trigger glow model (session 10): every button state that drives the
    -- multi-part shaped glow — proc / assist / cast / channel / hover / selected /
    -- flash — is now ONE uniform record { enabled, color, opacity, layers }, so each
    -- can be tuned (and its outer/inner layers toggled) independently. Seeded ONCE
    -- from the previous scattered fields (glowColor/glowIntensity/glowAssistColor +
    -- stateColors/stateIntensity) so the current look carries over exactly. The old
    -- fields are kept (dormant SDF fallback + preview) but no longer the source.
    do
      local sc = GB.db.stateColors or {}
      local gi = GB.db.glowIntensity or 0.9   -- proc/assist/cast/channel peak
      local si = GB.db.stateIntensity or 1    -- hover/selected/flash peak
      local seedT = {
        proc     = { enabled = true, color = GB.db.glowColor or { 1, 0.85, 0.35 },      opacity = gi, layers = "both" },
        highlight = { enabled = true, color = { 1, 0.93, 0.55 },                        opacity = gi, layers = "both" },   -- Blizzard's "press this" pulse (session 12)
        assist   = { enabled = true, color = GB.db.glowAssistColor or { 0.4, 0.75, 1 }, opacity = gi, layers = "both" },
        cast     = { enabled = true, color = { 1, 0.85, 0.4 },                          opacity = gi, layers = "both" },
        channel  = { enabled = true, color = { 0.6, 1, 0.4 },                           opacity = gi, layers = "both" },
        hover    = { enabled = true, color = sc.hover or { 1, 0.82, 0.35 },             opacity = si, layers = "both" },
        selected = { enabled = true, color = sc.selected or { 0.45, 0.75, 1 },          opacity = si, layers = "both" },
        flash    = { enabled = true, color = sc.flash or { 1, 0.25, 0.25 },             opacity = si, layers = "both" },
      }
      GB.db.triggers = GB.db.triggers or {}
      for key, def in pairs(seedT) do
        local t = GB.db.triggers[key]
        if not t then
          GB.db.triggers[key] = def
        else                      -- fill any missing field (forward-compat with partial saves)
          if t.enabled == nil then t.enabled = true end
          if t.color == nil then t.color = def.color end
          if t.opacity == nil then t.opacity = def.opacity end
          if t.layers == nil then t.layers = def.layers end
        end
      end
      for _, t in pairs(GB.db.triggers) do t.anims = t.anims or {} end   -- per-trigger animation configs (GB.Anims)
    end
  elseif event == "PLAYER_LOGIN" then
    PreloadFonts()
    RegisterMedia()
  end
end)

-- ---------------------------------------------------------------------------
-- Session-1 probes
-- ---------------------------------------------------------------------------

-- /gb debug — census of the 8 bars' button globals + subregions of a sample
-- button. Proves (or disproves) the naming hypothesis above before any
-- styling code is written against it.
local function DebugReport()
  msg("v" .. GB:Version() .. " — action button census:")
  local sample
  for _, bar in ipairs(GB.BARS) do
    local found = 0
    for i = 1, GB.BUTTONS_PER_BAR do
      local button = _G[bar.buttonPrefix .. i]
      if button then
        found = found + 1
        sample = sample or button
      end
    end
    print(("  %s (%s#): %d/%d buttons"):format(bar.label, bar.buttonPrefix, found, GB.BUTTONS_PER_BAR))
  end
  if not sample then
    msg("|cffc41e3aNo action buttons found — naming hypothesis is WRONG for this client.|r")
    return
  end
  -- Subregions we plan to restyle. Both cased variants probed: Blizzard has
  -- flip-flopped between .icon and .Icon across UI revisions.
  print("  Sample button: " .. sample:GetName())
  local regions = {
    { "icon",     sample.icon or sample.Icon },
    { "HotKey",   sample.HotKey },
    { "Name",     sample.Name },
    { "Count",    sample.Count },
    { "cooldown", sample.cooldown or sample.Cooldown },
    { "Border",   sample.Border },
    { "NormalTexture", sample.NormalTexture or (sample.GetNormalTexture and sample:GetNormalTexture()) },
    { "IconMask", sample.IconMask },
  }
  for _, r in ipairs(regions) do
    print(("    .%s: %s"):format(r[1], r[2] and "|cff20ba56found|r" or "|cffc41e3amissing|r"))
  end
  if sample.IconMask and sample.IconMask.GetAtlas then
    print("    IconMask atlas: " .. tostring(sample.IconMask:GetAtlas()))
  end
end

-- /gb mask — the ⚠ VERIFY that the whole differentiator rests on: does
-- MaskTexture render in Midnight AT ALL?
--
-- Probe history (2026-07-18):
--   v1: additive TempPortraitAlphaMask on button icons → "slightly more
--       rounded" (ambiguous; that's likely just Blizzard's default rounding).
--   v2: swapped Blizzard's own .IconMask atlas to CircleMaskScalable — swap
--       succeeded on 12/12, atlas exists, zero errors → NO visual change.
--       So either masks don't render, or the visible icon isn't masked by
--       IconMask (other addons — ArcUI — also restyle these buttons).
--   v3 (this): isolate the mechanism completely — our own frame, our own
--       texture, our own mask, screen center. No Blizzard buttons, no other
--       addons. Circle = masks work (gate 3 PASSES; the button path is the
--       problem). Square = masks are dead in Midnight (differentiator plan B).
local standaloneProbe
local function ToggleMaskProbe()
  if standaloneProbe then
    standaloneProbe:Hide()
    standaloneProbe = nil
    msg("mask probe OFF — test icon removed.")
    return
  end
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(96, 96)
  frame:SetPoint("CENTER", 0, 140)
  frame:SetFrameStrata("DIALOG")
  local tex = frame:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  local mask = frame:CreateMaskTexture()
  mask:SetTexture(GB.SHAPES.circle.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(tex)
  tex:AddMaskTexture(mask)
  standaloneProbe = frame
  msg("mask probe ON — a big question-mark icon is above your character, screen center. Is it a FULL CIRCLE (pass) or a SQUARE (fail)?")
end

-- /gb maskinfo — introspect ActionButton1's icon↔mask wiring, to explain the
-- v2 mystery: is IconMask actually attached to the texture the player SEES?
local function MaskInfo()
  local b = _G["ActionButton1"]
  local icon = b and (b.icon or b.Icon)
  if not icon then msg("ActionButton1 / .icon not found.") return end
  msg("ActionButton1 mask wiring:")
  print(("  .icon shown: %s, drawLayer: %s, texture: %s")
    :format(tostring(icon:IsShown()), tostring(icon:GetDrawLayer()), tostring(icon:GetTexture())))
  if icon.GetNumMaskTextures then
    local n = icon:GetNumMaskTextures()
    print(("  .icon mask count: %d"):format(n))
    for i = 1, n do
      local m = icon:GetMaskTexture(i)
      print(("    mask %d: %s (atlas: %s)"):format(i,
        m == b.IconMask and "IS .IconMask" or tostring(m),
        m and m.GetAtlas and tostring(m:GetAtlas()) or "?"))
    end
  else
    print("  GetNumMaskTextures API not present on this client")
  end
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
  print(("  Other bar addons loaded: ArcUI=%s Masque=%s")
    :format(loaded and tostring(loaded("ArcUI")) or "?", loaded and tostring(loaded("Masque")) or "?"))
end

-- /gb round — the first real mini-skin preview on ActionButton1, built from
-- what the probe series proved (see docs/API-NOTES.md): a FRESH circle mask
-- (mutating Blizzard's IconMask never re-renders) + suppression of the square
-- slot art behind the icon (SlotBackground/SlotArt/NormalTexture, identified
-- from the BugSack locals dump). Proper toggle — textures cap at 3 masks
-- (verified: AddMaskTexture throws), so ONE stored mask is reused forever.
local roundProbe
local function ToggleRoundProbe()
  if GB.Skin and GB.Skin.enabled then
    msg("skin is ON — turn it off first (/gb skin) before using the single-button probe.")
    return
  end
  local b = _G["ActionButton1"]
  local icon = b and (b.icon or b.Icon)
  if not icon then msg("ActionButton1 .icon not found.") return end
  if roundProbe and roundProbe.on then
    icon:RemoveMaskTexture(roundProbe.mask)
    if roundProbe.removedIconMask and b.IconMask then
      icon:AddMaskTexture(b.IconMask)
      roundProbe.removedIconMask = nil
    end
    if roundProbe.texCoord then icon:SetTexCoord(unpack(roundProbe.texCoord)) end
    for _, tex in ipairs(roundProbe.hidden) do tex:Show() end
    wipe(roundProbe.hidden)
    roundProbe.on = false
    msg("round probe OFF — ActionButton1 restored.")
    return
  end
  if not roundProbe then
    roundProbe = { hidden = {} }
    roundProbe.mask = b:CreateMaskTexture()
    -- Bundled PNG, not CircleMaskScalable: the scalable atlas 9-slices when
    -- stretched → flattened cardinal edges (observed twice in QA).
    roundProbe.mask:SetTexture(GB.SHAPES.circle.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    -- The circle art is padded to radius 240/256 of the canvas (transparent
    -- margin defeats edge-clamp filtering bleed — the blurred-flat-tangents
    -- artifact). Oversize the mask region by 256/240 so the circle itself
    -- still spans the icon exactly.
    local grow = icon:GetWidth() * (256 / 240 - 1) / 2
    roundProbe.mask:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
    roundProbe.mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
  end
  -- Masks INTERSECT: Blizzard's .IconMask (rounded square, soft edges) was
  -- still clipping our circle — the "flattened AND blurred cardinal edges,
  -- sharp round corners" QA observation. Remove it for the probe's duration
  -- (restored on toggle-off) so only our circle applies.
  if b.IconMask then
    icon:RemoveMaskTexture(b.IconMask)
    roundProbe.removedIconMask = true
  end
  icon:AddMaskTexture(roundProbe.mask)
  -- Zoom past the icon's baked-in square border so the circle's tangent points
  -- show art instead of border pixels.
  roundProbe.texCoord = { icon:GetTexCoord() }
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- Numbers for the size-mismatch theory (icon art bleeds under the border;
  -- IconMask crops it to the visible slot → smaller region than .icon).
  local function fmtSize(region)
    if not region then return "?" end
    local w, h = region:GetSize()
    return ("%.1fx%.1f"):format(w, h)
  end
  print(("  sizes — .icon: %s, IconMask: %s, SlotBackground: %s")
    :format(fmtSize(icon), fmtSize(b.IconMask), fmtSize(b.SlotBackground)))
  for _, key in ipairs({ "SlotBackground", "SlotArt", "NormalTexture" }) do
    local tex = b[key]
    if tex and tex.IsShown and tex:IsShown() then
      tex:Hide()
      roundProbe.hidden[#roundProbe.hidden + 1] = tex
    end
  end
  roundProbe.on = true
  msg("round probe ON — ActionButton1: circle mask + slot art hidden. Q1: clean round icon on a bare background? Q2: does any square art come back when you hover/press it?")
end

-- /gb fontinfo — what font is ACTUALLY on ActionButton1's text right now?
-- Distinguishes "our SetFont didn't take" from "took but got overridden by
-- another addon" (ArcUI styles keybind text — green color is theirs, not
-- Blizzard's) from "took but looks similar at 12px".
local function FontInfo()
  local b = _G["ActionButton1"]
  if not b then msg("ActionButton1 not found.") return end
  msg("ActionButton1 text fonts:")
  for _, key in ipairs({ "HotKey", "Count", "Name" }) do
    local fs = b[key]
    if fs and fs.GetFont then
      local face, size, flags = fs:GetFont()
      local r, g, bl = fs:GetTextColor()
      print(("  .%s: %s @ %.1f [%s] color %.2f,%.2f,%.2f text=%q shown=%s"):format(
        key, tostring(face), size or 0, tostring(flags),
        r or 0, g or 0, bl or 0, tostring(fs:GetText()), tostring(fs:IsShown())))
    end
  end
end

-- /gb glowinfo — does Blizzard's alert manager even KNOW about the visible
-- glow? If the manager reports no alerts while a glow is clearly visible,
-- that glow belongs to another addon (ArcUI?) and our hook is aimed at the
-- wrong system. Also reports whether our hook is installed + our glow states.
local function GlowInfo()
  local mgr = ActionButtonSpellAlertManager
  msg(("spell-alert census (manager=%s, ours: enabled=%s hooked=%s):")
    :format(mgr and "found" or "|cffc41e3aMISSING|r",
      tostring(GB.Glows and GB.Glows.enabled), tostring(GB.Glows and GB.Glows.hooked)))
  local count = 0
  GB:ForEachButton(function(btn, bar, i)
    local has, alertType
    if mgr and mgr.HasAlert then has, alertType = mgr:HasAlert(btn) end
    local alert = btn.SpellActivationAlert
      or (btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame.SpellActivationAlert)
    if has or alert then
      count = count + 1
      print(("  %s%d: HasAlert=%s type=%s blizzFrame=%s shown=%s alpha=%s altGlow=%s")
        :format(bar.buttonPrefix, i, tostring(has), tostring(alertType),
          alert and "yes" or "no",
          alert and tostring(alert:IsShown()) or "-",
          alert and ("%.2f"):format(alert:GetAlpha()) or "-",
          (alert and alert.ProcAltGlow) and tostring(alert.ProcAltGlow:IsShown()) or "-"))
    end
  end)
  if count == 0 then
    print("  |cffff7729No buttons have any Blizzard alert state. A visible glow = another addon's.|r")
  end
end

-- /gb pill — the deferred "clean pill" question (HANDOFF next-steps 1b): a
-- rounded mask stretched onto a non-square icon OVALIZES its corners. Candidate
-- cure = 9-slice the mask (SetTextureSliceMargins) so the corner cells stay
-- fixed and only the straight edges stretch. TWO unknowns in Midnight: does a
-- MaskTexture honor texture-slicing at all, and how do margins map to on-screen
-- corner size? This probe answers both with a direct A/B: two purple rounded
-- rectangles, same r1 mask source, both stretched ~3:1 —
--   TOP    = plain stretched mask (current behavior) → expect OVAL corners.
--   BOTTOM = 9-sliced mask                            → expect CIRCULAR corners.
-- r1's arc radius = 0.25*120 = 30 texels; +8 padding = 38-texel slice margin.
local pillProbe
local function TogglePillProbe()
  if pillProbe then
    pillProbe:Hide(); pillProbe = nil
    msg("pill probe OFF.")
    return
  end
  local host = CreateFrame("Frame", nil, UIParent)
  host:SetSize(320, 260); host:SetPoint("CENTER", 0, 170); host:SetFrameStrata("DIALOG")
  pillProbe = host
  local src = GB.SHAPES["corner-1111-r1"].mask   -- rounded rect, radius level 1
  local W, H, MARGIN = 300, 100, 38
  local sliceOK, sliceMissing = false, false
  local function panel(yOff, sliced, label)
    local f = CreateFrame("Frame", nil, host)
    f:SetSize(W, H); f:SetPoint("TOP", 0, yOff)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    -- White texture FILE + vertex color: masks clip this (not SetColorTexture — §4).
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(GB.COLOR.purple.r, GB.COLOR.purple.g, GB.COLOR.purple.b, 1)
    local m = f:CreateMaskTexture()
    m:SetTexture(src, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)
    if sliced then
      if m.SetTextureSliceMargins then
        m:SetTextureSliceMargins(MARGIN, MARGIN, MARGIN, MARGIN)
        if m.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
          m:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
        sliceOK = true
      else
        sliceMissing = true
        label = label .. "  |cffc41e3a[slicing API MISSING]|r"
      end
    end
    tex:AddMaskTexture(m)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(GB.FONT.body, 12, "OUTLINE"); fs:SetPoint("TOP", f, "BOTTOM", 0, -4); fs:SetText(label)
  end
  panel(0, false, "TOP — plain (expect OVAL corners)")
  panel(-150, true, "BOTTOM — 9-sliced (expect ROUND corners)")
  if sliceMissing then
    msg("pill probe ON, but |cffc41e3aSetTextureSliceMargins is MISSING on MaskTexture|r — 9-slice won't work; we'll fall back to per-aspect masks.")
  else
    msg("pill probe ON — two purple rounded rectangles above your character. Q1: does the BOTTOM one have rounder/more EVEN corners than the TOP (whose corners look squished/oval)? Q2: roughly how big are the BOTTOM corners — chunky (~40px) or smaller (~15px)?")
  end
end

-- /gb cdinfo — diagnose the cooldown swipe on a pill (session 4): is the aspect
-- swipe texture actually applied, and what shape is the cd frame? Explains the
-- "black rectangle, not clipped to the pill" symptom.
local function CooldownInfo()
  local b = _G["ActionButton1"]
  local icon = b and (b.icon or b.Icon)
  local cd = b and b.cooldown
  if not (icon and cd) then msg("ActionButton1 cooldown not found.") return end
  msg("ActionButton1 cooldown wiring:")
  print(("  db.shape=%s  iconW=%s iconH=%s"):format(
    tostring(GB.db and GB.db.shape), tostring(GB.db and GB.db.iconW), tostring(GB.db and GB.db.iconH)))
  print(("  icon size: %.1f x %.1f    cd frame size: %.1f x %.1f")
    :format(icon:GetWidth(), icon:GetHeight(), cd:GetWidth(), cd:GetHeight()))
  local tex = cd.GetSwipeTexture and cd:GetSwipeTexture()
  print("  swipe texture: " .. tostring(tex))
  if GB.Skin and GB.Skin.ShapeArt then
    print("  engine wants swipe: " .. tostring(GB.Skin:ShapeArt(icon).swipe))
  end
end

-- /gb castinfo — dump ActionButton1's SpellCastAnimFrame textures + their mask
-- counts, to find the "second, square" channel-drain overlay we're not shaping
-- (session 4). Cast/channel a spell on slot 1 once so the frame exists, then run.
local function CastInfo()
  local b = _G["ActionButton1"]
  local caf = b and b.SpellCastAnimFrame
  if not caf then msg("No .SpellCastAnimFrame yet — cast/channel a spell on slot 1 once, then rerun /gb castinfo.") return end
  msg("ActionButton1.SpellCastAnimFrame structure:")
  local function dump(frame, label)
    if not frame then print("  " .. label .. ": (nil)") return end
    print(("  %s [%s] shown=%s"):format(label, frame:GetObjectType(), tostring(frame:IsShown())))
    for _, r in ipairs({ frame:GetRegions() }) do
      local t = r.GetObjectType and r:GetObjectType()
      if t == "Texture" then
        local nm = r.GetNumMaskTextures and r:GetNumMaskTextures() or "?"
        print(("      TEX %s | atlas=%s | shown=%s | masks=%s")
          :format(tostring(r:GetDebugName()), tostring(r.GetAtlas and r:GetAtlas()), tostring(r:IsShown()), tostring(nm)))
      elseif t == "MaskTexture" then
        print(("      MASK %s | atlas=%s"):format(tostring(r:GetDebugName()), tostring(r.GetAtlas and r:GetAtlas())))
      end
    end
  end
  dump(caf, "SpellCastAnimFrame")
  dump(caf.Fill, ".Fill")
  dump(caf.EndBurst, ".EndBurst")
  -- EndBurst animation structure — to replay the completion burst on cancel.
  local eb = caf.EndBurst
  if eb then
    if eb.GetAnimationGroups then
      local ags = { eb:GetAnimationGroups() }
      print(("  .EndBurst animation groups: %d"):format(#ags))
      for _, ag in ipairs(ags) do
        print(("    AG name=%s playing=%s"):format(tostring(ag.GetName and ag:GetName()), tostring(ag.IsPlaying and ag:IsPlaying())))
      end
    end
    for _, k in ipairs({ "Anim", "Animation", "AnimIn", "Pulse", "Grow" }) do
      if eb[k] then print("    field .EndBurst." .. k .. " (" .. type(eb[k]) .. ")") end
    end
  end
  dump(caf.InterruptDisplay, "caf.InterruptDisplay")
  if b.InterruptDisplay then dump(b.InterruptDisplay, "btn.InterruptDisplay") end
  -- The cancel/interrupt red is a separate element — hunt any red-tinted texture.
  for _, sub in ipairs({ caf, caf.Fill, caf.InterruptDisplay, b.InterruptDisplay }) do
    if sub and sub.GetRegions then
      for _, r in ipairs({ sub:GetRegions() }) do
        if r.GetVertexColor then
          local rr, g, bl = r:GetVertexColor()
          if rr and rr > 0.6 and (g or 0) < 0.4 and (bl or 0) < 0.4 then
            print(("  |cffff7729RED tex: %s (atlas=%s)|r"):format(tostring(r:GetDebugName()), tostring(r.GetAtlas and r:GetAtlas())))
          end
        end
      end
    end
  end
end

-- /gb borderinfo — find the green equipped-item border we're failing to suppress
-- (session 4). Reports every button whose .Border is shown + its alpha/colour, so
-- we know if the green is .Border (and whether our SetAlpha(0) stuck) or another
-- element. Run with the trinket on a bar.
local function BorderInfo()
  msg("Equipped-border (.Border) census across the 8 bars:")
  local n = 0
  GB:ForEachButton(function(btn, bar, i)
    local b = btn.Border
    if b and b.IsShown and b:IsShown() then
      n = n + 1
      local r, g, bl, a = b:GetVertexColor()
      print(("  %s%d: .Border SHOWN alpha=%.2f vertex=%.2f,%.2f,%.2f,%.2f atlas=%s")
        :format(bar.buttonPrefix, i, b:GetAlpha(), r or 0, g or 0, bl or 0, a or 0, tostring(b.GetAtlas and b:GetAtlas())))
    end
  end)
  if n == 0 then print("  |cffff7729No .Border is shown — the green border is a DIFFERENT element.|r") end
end

-- /gb hunt — arm a one-shot capture on the next cast INTERRUPT/FAIL, then scan
-- EVERY action button's whole texture tree for the red cancel overlay and name
-- it (works regardless of which button/addon owns it). Flags red-tinted textures
-- OR ones whose atlas looks interrupt/fail-ish. Scans at a few delays to catch a
-- brief flash.
local huntFrame
local function scanInterrupt(tag)
  local n = 0
  local function walk(frame, depth)
    if not frame or depth > 5 then return end
    if frame.GetRegions then
      for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and r.IsShown and r:IsShown() and (r.GetAlpha and r:GetAlpha() > 0.15) then
          local rr, g, bl = r.GetVertexColor and r:GetVertexColor()
          local atlas = r.GetAtlas and r:GetAtlas()
          local redTint = rr and rr > 0.5 and (g or 0) < 0.5 and (bl or 0) < 0.5 and (rr - (g or 0)) > 0.2
          local badAtlas = atlas and atlas:lower():match("interrupt") or (atlas and atlas:lower():match("fail")) or (atlas and atlas:lower():match("cancel"))
          if redTint or badAtlas then
            n = n + 1
            print(("  [%s] %s | atlas=%s | a=%.2f | %s"):format(tag, tostring(r:GetDebugName()), tostring(atlas), r:GetAlpha(), redTint and "RED" or "atlas"))
          end
        end
      end
    end
    if frame.GetChildren then for _, c in ipairs({ frame:GetChildren() }) do walk(c, depth + 1) end end
  end
  GB:ForEachButton(function(btn) walk(btn, 0) end)
  if n == 0 then print(("  [%s] nothing flagged"):format(tag)) end
end
local function ArmHunt()
  huntFrame = huntFrame or CreateFrame("Frame")
  huntFrame:UnregisterAllEvents()
  huntFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
  huntFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
  huntFrame:SetScript("OnEvent", function(_, event, unit)
    if unit and unit ~= "player" then return end
    huntFrame:UnregisterAllEvents()
    msg(event .. " — scanning all buttons for the red overlay:")
    scanInterrupt("0.00s")
    if C_Timer then
      C_Timer.After(0.06, function() scanInterrupt("0.06s") end)
      C_Timer.After(0.15, function() scanInterrupt("0.15s") end)
      C_Timer.After(0.30, function() scanInterrupt("0.30s") end)
    end
  end)
  msg("hunt ARMED — now cancel a cast (start casting, then move/jump). The red element will be named.")
end

-- /gb hkinfo — dump the RAW keybind text on each button next to its binding key,
-- so we can map modifier abbreviations (m-/s-/c-/a-) → display exactly, incl. how
-- STACKED modifiers concatenate (e.g. Cmd+Shift). Read-only diagnostic.
local function HotkeyInfo()
  local RI = _G.RANGE_INDICATOR
  msg("keybind dump — 'display text' | binding key:")
  local seen, n = {}, 0
  for _, bar in ipairs(GB.BARS) do
    for i = 1, GB.BUTTONS_PER_BAR do
      local btn = _G[bar.buttonPrefix .. i]
      local hk = btn and btn.HotKey
      local disp = hk and hk:GetText()
      if disp and disp ~= "" and disp ~= RI then
        local key = btn.bindingAction and GetBindingKey(btn.bindingAction)
        local line = ("  '%s'  |  %s"):format(disp, key or "?")
        if not seen[line] then seen[line] = true; n = n + 1; print(line) end
      end
    end
  end
  if n == 0 then msg("no keybind text found (are keybinds shown on your bars?).") end
end

-- ---------------------------------------------------------------------------
-- /gb slash router
-- ---------------------------------------------------------------------------
SLASH_GLOOMSBARS1 = "/gb"
SLASH_GLOOMSBARS2 = "/gloomsbars"
SlashCmdList.GLOOMSBARS = function(input)
  local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(%S*)")
  if cmd == "" or cmd == "config" or cmd == "ui" then
    if GB.Config then GB.Config:Toggle() else msg("style editor not loaded.") end
  elseif cmd == "debug" then
    DebugReport()
  elseif cmd == "mask" then
    ToggleMaskProbe()
  elseif cmd == "maskinfo" then
    MaskInfo()
  elseif cmd == "round" then
    ToggleRoundProbe()
  elseif cmd == "pill" then
    TogglePillProbe()
  elseif cmd == "cdinfo" then
    CooldownInfo()
  elseif cmd == "castinfo" then
    CastInfo()
  elseif cmd == "borderinfo" then
    BorderInfo()
  elseif cmd == "hunt" then
    ArmHunt()
  elseif cmd == "skin" then
    GB.Skin:Toggle()
  elseif cmd == "sweep" then
    GB.Skin:SetSweepOvershoot(tonumber(arg))
  elseif cmd == "fontinfo" then
    FontInfo()
  elseif cmd == "hkinfo" then
    HotkeyInfo()
  elseif cmd == "glowinfo" then
    GlowInfo()
  -- (the /gb shine playground was removed — shine-chase is now a Config animation;
  --  /gb glowtest, /gb glowstyle, /gb handglow — the session-8/9 glow bake-off
  --  harness — were removed in session 12: the Config preview chips cover them.)
  elseif cmd == "handshape" then
    local key = (arg or ""):lower()
    if key == "" then
      msg(("hand-shape is '%s'. Set with /gb handshape <key> (persists). 21 keys in docs/ART-SPEC.md.")
        :format(tostring(GB.db and GB.db.handShape)))
    elseif GB.HAND_SHAPES[key] then
      if GB.Skin then GB.Skin:SetHandShape(key) else GB.db.handShape = key end
      msg(("hand-shape set to '%s' — icon, border & gradient masked to it (persists)."):format(key))
    else
      msg("unknown key '" .. key .. "'. See docs/ART-SPEC.md for the 21 keys (e.g. diamond, tombstone, roundsq2-32).")
    end
  elseif cmd == "size" then
    local v = tonumber(arg)
    if v then
      v = math.max(0.4, math.min(3, v))
      if GB.Skin then GB.Skin:SetSizeScale(v) else GB.db.sizeScale = v end
      msg(("icon size scale set to %.2f× (persists)."):format(v))
    else
      msg(("icon size scale is %.2f× (usage: /gb size 1.25 — × the Edit-Mode button size)."):format(GB.db and GB.db.sizeScale or 1))
    end
  elseif cmd == "shape" then
    if arg ~= "" and GB.SHAPES[arg] then
      GB.db.shape = arg
      msg(("shape set to '%s' — /reload to apply."):format(arg))
    else
      local names = {}
      for name in pairs(GB.SHAPES) do names[#names + 1] = name end
      table.sort(names)
      msg(("shape is '%s'. Available: %s (usage: /gb shape roundrect, then /reload)")
        :format(GB.db.shape or "circle", table.concat(names, ", ")))
    end
  elseif cmd == "style" then
    if arg ~= "" and GB.STYLES[arg] then
      GB.db.style = arg
      if GB.Skin and GB.Skin.enabled then GB.Skin:ReapplyDecor() end
      msg(("style set to '%s'%s."):format(arg,
        (GB.Skin and GB.Skin.enabled) and " — applied live" or " (enable the skin to see it)"))
    else
      local names = {}
      for name in pairs(GB.STYLES) do names[#names + 1] = name end
      table.sort(names)
      msg(("style is '%s'. Available: %s (usage: /gb style plate)")
        :format(GB.db.style or "none", table.concat(names, ", ")))
    end
  else
    msg("v" .. GB:Version() .. " — commands:")
    print("  /gb skin — toggle the skin on all 8 action bars (persists)")
    print("  /gb shape <name> — pick the icon shape (circle, roundrect, …); applies on /reload")
    print("  /gb style <name> — pick a decoration style (none, plate, …); applies live")
    print("  /gb sweep <px> — tune how far the cooldown sweep overshoots the icon edge")
    print("  /gb debug — census of action bar buttons + regions")
    print("  /gb mask — toggle the standalone MaskTexture render probe (screen center)")
    print("  /gb maskinfo — inspect ActionButton1's icon/mask wiring")
    print("  /gb round — single-button probe (only while skin is off)")
    print("  /gb pill — probe 9-slice masks for clean non-square rounded corners")
  end
end
