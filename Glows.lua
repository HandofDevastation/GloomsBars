-- Glows.lua — Gloom's Bars shaped proc glows (GB.Glows) — THE differentiator.
--
-- Every other restyle addon leaves Blizzard's square proc glow (or a square
-- LibCustomGlow tracer) floating around shaped icons. We substitute our own
-- shape-matched halo, driven by Blizzard's OWN alert decisions — no secret
-- combat data is ever read.
--
-- Hook point (source-verified, docs/API-NOTES.md §3): the global table
-- ActionButtonSpellAlertManager routes ALL spell alerts — gold procs, the
-- blue assisted highlight (ProcAltGlow "downgrade"), and the one-button
-- rotation variant — through :ShowAlert(btn)/:HideAlert(btn). Alert frames
-- are per-button (btn.SpellActivationAlert, created on demand, never pooled).
-- We post-hook the manager, alpha-0 Blizzard's alert frame (Show/Hide cycles
-- never touch alpha — proven pattern), and drive our own glow.

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
local silenced = {}   -- [alertFrame] = true — Blizzard alerts we alpha-0'd

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

local function BlizzAlertFor(btn)
  return btn.SpellActivationAlert
    or (btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame.SpellActivationAlert)
end

local function SilenceBlizzAlert(btn)
  local alert = BlizzAlertFor(btn)
  if alert and not silenced[alert] then
    alert:SetAlpha(0)
    silenced[alert] = true
  end
end

local function ShowOurGlow(btn)
  local g = GetGlow(btn)
  if not g then return end
  local alert = BlizzAlertFor(btn)
  local _, alertType = ActionButtonSpellAlertManager:HasAlert(btn)
  local isAssist = (alertType == ActionButtonSpellAlertManager.SpellAlertType.AssistedCombatRotation)
    or (alert and alert.ProcAltGlow and alert.ProcAltGlow.IsShown and alert.ProcAltGlow:IsShown())
  local tint = isAssist and TINT.assist or TINT.gold
  g.tex:SetVertexColor(tint[1], tint[2], tint[3])
  if not g.frame:IsShown() then
    g.frame:Show()
    g.anim:Play()
  end
end

local function HideOurGlow(btn)
  local g = glows[btn]
  if g and g.frame:IsShown() then
    g.anim:Stop()
    g.frame:Hide()
  end
end

function Glows:Init()
  if self.hooked or not ActionButtonSpellAlertManager then return end
  self.hooked = true
  hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, btn)
    if not Glows.enabled then return end
    SilenceBlizzAlert(btn)   -- frame exists now: ShowAlert just created it
    ShowOurGlow(btn)
  end)
  hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, btn)
    if not Glows.enabled then return end
    HideOurGlow(btn)
  end)
end

function Glows:SetEnabled(on)
  self:Init()
  self.enabled = on
  if not ActionButtonSpellAlertManager then return end
  if on then
    -- Adopt alerts already active at enable time.
    GB:ForEachButton(function(btn)
      if ActionButtonSpellAlertManager:HasAlert(btn) then
        SilenceBlizzAlert(btn)
        ShowOurGlow(btn)
      end
    end)
  else
    for alert in pairs(silenced) do alert:SetAlpha(1) end
    wipe(silenced)
    for btn in pairs(glows) do HideOurGlow(btn) end
  end
end
