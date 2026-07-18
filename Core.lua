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
local CIRCLE_ATLAS = "CircleMaskScalable"
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
  mask:SetAtlas(CIRCLE_ATLAS)
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
  local b = _G["ActionButton1"]
  local icon = b and (b.icon or b.Icon)
  if not icon then msg("ActionButton1 .icon not found.") return end
  if roundProbe and roundProbe.on then
    icon:RemoveMaskTexture(roundProbe.mask)
    for _, tex in ipairs(roundProbe.hidden) do tex:Show() end
    wipe(roundProbe.hidden)
    roundProbe.on = false
    msg("round probe OFF — ActionButton1 restored.")
    return
  end
  if not roundProbe then
    roundProbe = { hidden = {} }
    roundProbe.mask = b:CreateMaskTexture()
    roundProbe.mask:SetAtlas(CIRCLE_ATLAS)
    roundProbe.mask:SetAllPoints(icon)
  end
  icon:AddMaskTexture(roundProbe.mask)
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

-- ---------------------------------------------------------------------------
-- /gb slash router
-- ---------------------------------------------------------------------------
SLASH_GLOOMSBARS1 = "/gb"
SLASH_GLOOMSBARS2 = "/gloomsbars"
SlashCmdList.GLOOMSBARS = function(input)
  local cmd = (input or ""):lower():match("^%s*(%S*)")
  if cmd == "debug" then
    DebugReport()
  elseif cmd == "mask" then
    ToggleMaskProbe()
  elseif cmd == "maskinfo" then
    MaskInfo()
  elseif cmd == "round" then
    ToggleRoundProbe()
  else
    msg("v" .. GB:Version() .. " — commands:")
    print("  /gb debug — census of action bar buttons + regions")
    print("  /gb mask — toggle the standalone MaskTexture render probe (screen center)")
    print("  /gb maskinfo — inspect ActionButton1's icon/mask wiring")
    print("  /gb round — toggle the mini-skin preview on ActionButton1 (circle mask + slot art hidden)")
  end
end
