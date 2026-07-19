-- Glows.lua — Gloom's Bars shaped proc glows (GB.Glows) — THE differentiator.
--
-- Every other restyle addon leaves Blizzard's square glow art floating around
-- shaped icons. We substitute our own shape-matched halo, driven by Blizzard's
-- OWN decisions — no secret combat data is ever read.
--
-- Blizzard has THREE glow mechanisms (all source-verified, API-NOTES §3):
--   1. Spell alerts (gold procs + variants) — ActionButtonSpellAlertManager
--      :ShowAlert/:HideAlert, per-button frames (btn.SpellActivationAlert).
--   2. The assisted HIGHLIGHT — AssistedCombatManager
--      :SetAssistedHighlightFrameShown(btn, shown) parenting a 66×66 blue
--      "marching ants" flipbook (btn.AssistedCombatHighlightFrame; anim only
--      plays IN COMBAT — frozen single frame out of combat).
--   3. The rotation-helper ActiveFrame (only when the one-button rotation
--      feature is on) — reskinned separately in Skin.lua.
-- We post-hook 1 and 2, alpha-0 Blizzard's frames (Show/Hide cycles never
-- touch alpha — proven pattern), and drive one shaped halo per button.

local GB = _G.GloomsBars

local Glows = { enabled = false }
GB.Glows = Glows

-- The glow art's shape edge sits at 96/128 of its canvas so the halo blooms
-- OUTSIDE the icon rim (tools/generate-art.py GLOW_EXTENT). Size the glow
-- region by 128/96 so the art's edge lands exactly on the icon's edge.
local GLOW_SCALE = 128 / 96

local TINT = {
  gold   = { 1, 0.85, 0.35 },   -- standard proc
  assist = { 0.4, 0.75, 1 },    -- assisted highlight / rotation suggestion
}

local glows = {}      -- [button] = { frame, tex, anim }
local sources = {}    -- [button] = { alert = "gold"|"assist"|nil, assist = true|nil }
local silenced = {}   -- [blizzard frame] = true — frames we alpha-0'd

local function GetGlow(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return nil end
  local g = glows[btn]
  if not g then
    local frame = CreateFrame("Frame", nil, btn)
    frame:SetPoint("CENTER", icon, "CENTER")
    frame:SetSize(icon:GetWidth() * GLOW_SCALE, icon:GetHeight() * GLOW_SCALE)
    frame:SetFrameLevel(btn:GetFrameLevel() + 10)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(GB:GetShape().glow)
    tex:SetBlendMode("ADD")
    local anim = frame:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    local pulse = anim:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.45)
    pulse:SetDuration(0.55)
    pulse:SetSmoothing("IN_OUT")
    frame:Hide()
    g = { frame = frame, tex = tex, anim = anim }
    glows[btn] = g
  end
  return g
end

local function Silence(frame)
  if frame and not silenced[frame] then
    frame:SetAlpha(0)
    silenced[frame] = true
  end
end

local function BlizzAlertFor(btn)
  return btn.SpellActivationAlert
    or (btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame.SpellActivationAlert)
end

-- One shaped halo per button; sources (alert / assist highlight) set flags and
-- this reconciles visibility + tint. Assist blue wins when both are active
-- (mirrors Blizzard's own downgrade logic).
local function Refresh(btn)
  local s = sources[btn]
  local g = GetGlow(btn)
  if not g then return end
  local tintKey = s and (s.assist and "assist" or s.alert) or nil
  if tintKey then
    local tint = TINT[tintKey] or TINT.gold
    g.tex:SetVertexColor(tint[1], tint[2], tint[3])
    if not g.frame:IsShown() then
      g.frame:Show()
      g.anim:Play()
    end
  elseif g.frame:IsShown() then
    g.anim:Stop()
    g.frame:Hide()
  end
end

local function SetSource(btn, key, value)
  local s = sources[btn]
  if not s then s = {}; sources[btn] = s end
  s[key] = value or nil
  Refresh(btn)
end

function Glows:Init()
  if self.hooked then return end
  local alertMgr = ActionButtonSpellAlertManager
  local assistMgr = AssistedCombatManager
  if not alertMgr then return end
  self.hooked = true
  hooksecurefunc(alertMgr, "ShowAlert", function(_, btn)
    if not Glows.enabled then return end
    Silence(BlizzAlertFor(btn))   -- frame exists now: ShowAlert just created it
    local _, alertType = alertMgr:HasAlert(btn)
    local isAssistType = alertType == alertMgr.SpellAlertType.AssistedCombatRotation
    SetSource(btn, "alert", isAssistType and "assist" or "gold")
  end)
  hooksecurefunc(alertMgr, "HideAlert", function(_, btn)
    if not Glows.enabled then return end
    SetSource(btn, "alert", nil)
  end)
  if assistMgr and assistMgr.SetAssistedHighlightFrameShown then
    hooksecurefunc(assistMgr, "SetAssistedHighlightFrameShown", function(_, btn, shown)
      if not Glows.enabled then return end
      Silence(btn.AssistedCombatHighlightFrame)
      SetSource(btn, "assist", shown and true or nil)
    end)
  end
end

function Glows:SetEnabled(on)
  self:Init()
  self.enabled = on
  if on then
    -- Adopt glow state already active at enable time.
    GB:ForEachButton(function(btn)
      if ActionButtonSpellAlertManager and select(1, ActionButtonSpellAlertManager:HasAlert(btn)) then
        Silence(BlizzAlertFor(btn))
        local _, alertType = ActionButtonSpellAlertManager:HasAlert(btn)
        local isAssistType = alertType == ActionButtonSpellAlertManager.SpellAlertType.AssistedCombatRotation
        SetSource(btn, "alert", isAssistType and "assist" or "gold")
      end
      local hf = btn.AssistedCombatHighlightFrame
      if hf then
        Silence(hf)
        SetSource(btn, "assist", hf:IsShown() and true or nil)
      end
    end)
  else
    for frame in pairs(silenced) do frame:SetAlpha(1) end
    wipe(silenced)
    for btn in pairs(sources) do
      sources[btn] = nil
      Refresh(btn)
    end
  end
end
