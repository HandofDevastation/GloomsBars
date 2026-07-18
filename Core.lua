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
-- MaskTexture render in Midnight? Probe v2 after v1's ambiguous "slightly more
-- rounded" result (2026-07-18): the buttons likely already carry Blizzard's own
-- .IconMask, so v1's added mask may never have loaded its texture. v2 prefers
-- swapping the atlas on Blizzard's OWN IconMask to a dramatic full circle —
-- an unmistakable pass/fail. Falls back to v1's additive mask (with a
-- did-it-load report) if .IconMask is gone. Run again to restore.
local CIRCLE_ATLAS = "CircleMaskScalable"
local maskProbe = { swapped = {}, added = {} }
local function ToggleMaskProbe()
  if #maskProbe.swapped > 0 or #maskProbe.added > 0 then
    for _, entry in ipairs(maskProbe.swapped) do
      if entry.atlas then
        entry.mask:SetAtlas(entry.atlas)
      else
        -- No atlas to restore (mask used a plain texture we can't cheaply
        -- stash) — a /reload fully resets Blizzard's state.
        entry.mask:SetAtlas(nil)
      end
    end
    for _, entry in ipairs(maskProbe.added) do
      entry.icon:RemoveMaskTexture(entry.mask)
      entry.mask:Hide()
    end
    wipe(maskProbe.swapped); wipe(maskProbe.added)
    msg("mask probe OFF — bar 1 restored (if anything looks off, /reload fully resets).")
    return
  end
  if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CIRCLE_ATLAS)) then
    msg(("|cffff7729atlas '%s' not found in this client|r — falling back to file-path mask."):format(CIRCLE_ATLAS))
  end
  local swapped, added, loadFailures = 0, 0, 0
  for i = 1, GB.BUTTONS_PER_BAR do
    local button = _G["ActionButton" .. i]
    local icon = button and (button.icon or button.Icon)
    if icon then
      local blizzMask = button.IconMask
      if blizzMask and C_Texture.GetAtlasInfo(CIRCLE_ATLAS) then
        maskProbe.swapped[#maskProbe.swapped + 1] = { mask = blizzMask, atlas = blizzMask:GetAtlas() }
        blizzMask:SetAtlas(CIRCLE_ATLAS)
        swapped = swapped + 1
      else
        local mask = button:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
          "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if not mask:GetTexture() then loadFailures = loadFailures + 1 end
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        maskProbe.added[#maskProbe.added + 1] = { icon = icon, mask = mask }
        added = added + 1
      end
    end
  end
  msg(("mask probe ON — %d Blizzard IconMasks swapped to '%s', %d additive masks added (%d texture load failures). Are bar-1 icons FULL circles now?")
    :format(swapped, CIRCLE_ATLAS, added, loadFailures))
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
  else
    msg("v" .. GB:Version() .. " — commands:")
    print("  /gb debug — census of action bar buttons + regions")
    print("  /gb mask — toggle the MaskTexture render probe on bar 1")
  end
end
