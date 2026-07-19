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
}

function GB:GetShape()
  return GB.SHAPES[(GB.db and GB.db.shape) or "circle"] or GB.SHAPES.circle
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
  -- Jason's mockup (2026-07-18): orange gradient plate over the icon's bottom,
  -- keybind bold white centered ON the plate.
  plate = {
    layers = {
      { kind = "gradient", side = "BOTTOM", sizePct = 0.42,
        color = { 1, 0.47, 0.16 }, fromAlpha = 1, toAlpha = 0 },
    },
    hotkey = {
      layer = 1, offsetY = 0,
      font = "label", size = 13, flags = "OUTLINE",
      color = { 1, 1, 1 },
    },
  },
}

function GB:GetStyle()
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
  sweepOvershoot = 0.75,   -- px the cooldown sweep extends past the icon circle
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
  elseif event == "PLAYER_LOGIN" then
    PreloadFonts()
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

-- ---------------------------------------------------------------------------
-- /gb slash router
-- ---------------------------------------------------------------------------
SLASH_GLOOMSBARS1 = "/gb"
SLASH_GLOOMSBARS2 = "/gloomsbars"
SlashCmdList.GLOOMSBARS = function(input)
  local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(%S*)")
  if cmd == "debug" then
    DebugReport()
  elseif cmd == "mask" then
    ToggleMaskProbe()
  elseif cmd == "maskinfo" then
    MaskInfo()
  elseif cmd == "round" then
    ToggleRoundProbe()
  elseif cmd == "skin" then
    GB.Skin:Toggle()
  elseif cmd == "sweep" then
    GB.Skin:SetSweepOvershoot(tonumber(arg))
  elseif cmd == "fontinfo" then
    FontInfo()
  elseif cmd == "glowinfo" then
    GlowInfo()
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
  end
end
