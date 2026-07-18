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

-- /gb mask2 — button-level probe v4, after /gb maskinfo showed IconMask IS
-- attached to the visible .icon (so v2's no-change result is unexplained).
-- Two suspects: (a) something re-asserts the atlas right after we set it
-- (ArcUI re-skin or Blizzard update cycle), (b) another texture is drawn over
-- the masked icon. This swaps the atlas on ActionButton1 ONLY, re-checks the
-- atlas at 0/1/3 seconds (a revert = suspect a), and dumps the button's shown
-- texture stack (an overlay icon = suspect b). /reload to revert.
local function ButtonMaskProbe()
  local b = _G["ActionButton1"]
  local icon = b and (b.icon or b.Icon)
  local m = b and b.IconMask
  if not (icon and m) then msg("ActionButton1 .icon/.IconMask not found.") return end
  msg("button mask probe (ActionButton1 only):")
  print("  atlas before: " .. tostring(m:GetAtlas()))
  m:SetAtlas(CIRCLE_ATLAS)
  -- Force the masked texture to re-evaluate, in case mask edits don't dirty it.
  icon:RemoveMaskTexture(m)
  icon:AddMaskTexture(m)
  print("  atlas set to: " .. tostring(m:GetAtlas()))
  print("  shown textures on the button (layer / atlas-or-fileID):")
  for _, region in ipairs({ b:GetRegions() }) do
    if region.IsShown and region:IsShown() and region.GetDrawLayer then
      local kind = region:GetObjectType()
      if kind == "Texture" or kind == "MaskTexture" then
        local what = (region.GetAtlas and region:GetAtlas())
          or (region.GetTexture and tostring(region:GetTexture())) or "?"
        local tag = (region == icon) and " <== .icon" or (region == m and " <== .IconMask" or "")
        print(("    %s %s: %s%s"):format(kind, tostring(region:GetDrawLayer()), tostring(what), tag))
      end
    end
  end
  for _, delay in ipairs({ 0, 1, 3 }) do
    C_Timer.After(delay, function()
      print(("  atlas after %ds: %s"):format(delay, tostring(m:GetAtlas())))
      if delay == 3 then
        msg("Done. Did ActionButton1 (first button, bar 1) LOOK circular at any point? (/reload to revert)")
      end
    end)
  end
end

-- /gb tint — discriminator after v4 (2026-07-18): the atlas swap persists, the
-- mask is attached to the shown .icon, no overdraw among the button's own
-- regions — yet no visual change. Either the VISIBLE icon isn't Blizzard's
-- .icon (an addon overlay living in a child frame — ArcUI), or mask changes
-- don't propagate to an already-rendered texture. This (a) tints .icon RED —
-- if the visible icon doesn't go red, we've never been looking at it; (b) adds
-- a FRESH additive circle mask (the exact config the standalone probe proved
-- renders); (c) dumps the button's child frames. /reload reverts.
local function TintProbe()
  local b = _G["ActionButton1"]
  local icon = b and (b.icon or b.Icon)
  if not icon then msg("ActionButton1 .icon not found.") return end
  icon:SetVertexColor(1, 0.15, 0.15)
  local mask = b:CreateMaskTexture()
  mask:SetAtlas(CIRCLE_ATLAS)
  mask:SetAllPoints(icon)
  icon:AddMaskTexture(mask)
  msg("tint probe ON — Blizzard's real icon on ActionButton1 is now RED + freshly circle-masked.")
  print("  child frames of the button (an overlay icon would live here):")
  local kids = { b:GetChildren() }
  if #kids == 0 then print("    (none)") end
  for _, kid in ipairs(kids) do
    local shownTex = 0
    for _, r in ipairs({ kid:GetRegions() }) do
      if r.IsShown and r:IsShown() and r:GetObjectType() == "Texture" then shownTex = shownTex + 1 end
    end
    print(("    %s (%s, level %d, shown=%s, %d shown textures)")
      :format(tostring(kid:GetName() or "<unnamed>"), kid:GetObjectType(),
        kid:GetFrameLevel(), tostring(kid:IsShown()), shownTex))
  end
  C_Timer.After(1, function()
    local r, g = icon:GetVertexColor()
    print(("  vertex color after 1s: r=%.2f g=%.2f (reverted: %s)"):format(r, g, tostring(r < 0.9 or g > 0.5)))
    msg("Q: Is the FIRST icon on bar 1 now (a) RED and (b) CIRCULAR? (/reload to revert)")
  end)
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
  elseif cmd == "mask2" then
    ButtonMaskProbe()
  elseif cmd == "tint" then
    TintProbe()
  else
    msg("v" .. GB:Version() .. " — commands:")
    print("  /gb debug — census of action bar buttons + regions")
    print("  /gb mask — toggle the standalone MaskTexture render probe (screen center)")
    print("  /gb maskinfo — inspect ActionButton1's icon/mask wiring")
    print("  /gb mask2 — instrumented atlas swap on ActionButton1 (re-assert + overdraw check)")
    print("  /gb tint — red-tint the real icon + fresh circle mask + child-frame dump")
  end
end
