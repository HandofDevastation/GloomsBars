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

-- The glow art's shape edge sits at 80/128 of its canvas (GLOW_EXTENT) so a WIDE
-- soft halo blooms OUTSIDE the icon rim. Size the glow region by 128/80 so the
-- art's edge lands exactly on the icon's edge (the wider bloom then fades out).
local GLOW_SCALE = 128 / 80

local TINT = {
  gold   = { 1, 0.85, 0.35 },   -- standard proc
  assist = { 0.4, 0.75, 1 },    -- assisted highlight / rotation suggestion
}

-- Live-tunable glow style (Config → Proc glow, stored in GB.db). Accessors so the
-- engine always reads the current value; GetGlow builds new halos from these and
-- the setters below re-apply to existing ones.
local function glowScale() return (GB.db and GB.db.glowScale) or GLOW_SCALE end
local PULSE_DEPTH = 0.5   -- the pulse always dips to this fraction of the peak, so it stays visible
local function glowPeak() return (GB.db and GB.db.glowIntensity) or 0.9 end   -- Brightness = PEAK alpha
local function glowSpeed() return math.max(0.1, (GB.db and GB.db.glowPulseSpeed) or 1) end
-- State-highlight default tints (mirror Core DB_DEFAULTS.stateColors) for before
-- the db is populated. hover/selected/flash read GB.db.stateColors.
local STATE_TINT = { hover = { 1, 0.82, 0.35 }, selected = { 0.45, 0.75, 1 }, flash = { 1, 0.25, 0.25 } }
local function tintFor(key)
  if key == "assist" then return (GB.db and GB.db.glowAssistColor) or TINT.assist end
  if STATE_TINT[key] then
    local sc = GB.db and GB.db.stateColors
    return (sc and sc[key]) or STATE_TINT[key]
  end
  return (GB.db and GB.db.glowColor) or TINT.gold
end

local glows = {}      -- [button] = { frame, tex, anim }
local sources = {}    -- [button] = { alert = "gold"|"assist"|nil, assist = true|nil, test = "gold"|nil }
local silenced = {}   -- [blizzard frame] = true — frames we alpha-0'd

-- DEV glow-comparison harness (session 8): /gb glowtest force-shows the halo out
-- of combat (procs are too fast to study live) and /gb glowstyle swaps in a
-- candidate profile PNG. testArt overrides the normal shape art while set.
local testArt
local forceScale   -- test: pin the glow scale to the candidates' design scale so
                   -- a stray Size-slider value can't throw off the shape fit
local function currentGlowTex()
  return testArt
    or (GB.Skin and GB.Skin.GlowArt and GB.Skin:GlowArt())
    or GB:GetShape().glow
end

-- The spell-alert manager ALSO fires for Midnight's Cooldown Viewer frames, whose
-- geometry is a SECRET combat value — reading it (e.g. Icon:GetWidth() * scale)
-- taints us and throws. So the glow engine is restricted to OUR action buttons;
-- this set is the authoritative gate (rebuilt whenever the engine (re)enables).
local ourSet
local function isOurs(btn)
  if not ourSet then
    ourSet = {}
    if GB.ForEachButton then GB:ForEachButton(function(b) ourSet[b] = true end) end
  end
  return btn ~= nil and ourSet[btn] == true
end

-- Anchor the halo over the whole CONSTRUCTION (icon + any plate extension),
-- oversized by the glow scale, so it tracks the icon's live size/aspect AND wraps
-- the extension — not just the icon. Reuses Skin's overlay anchoring (same math as
-- the ring/sweep); falls back to the icon alone if Skin isn't up yet.
local function anchorGlow(frame, icon)
  local ratio = ((forceScale or glowScale()) - 1) / 2
  if GB.Skin and GB.Skin.AnchorOverlay then
    GB.Skin:AnchorOverlay(frame, icon, ratio)
  else
    local ox, oy = icon:GetWidth() * ratio, icon:GetHeight() * ratio
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", icon, "TOPLEFT", -ox, oy)
    frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", ox, -oy)
  end
end

local function GetGlow(btn)
  if not isOurs(btn) then return nil end   -- action buttons only (Cooldown Viewer geometry is secret)
  local icon = btn.icon or btn.Icon
  if not icon then return nil end
  local g = glows[btn]
  if not g then
    local frame = CreateFrame("Frame", nil, btn)
    frame:SetFrameLevel(btn:GetFrameLevel() + 10)
    anchorGlow(frame, icon)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(currentGlowTex())
    tex:SetBlendMode("ADD")
    local anim = frame:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    local pulse = anim:CreateAnimation("Alpha")
    local peak = glowPeak()
    pulse:SetFromAlpha(peak)
    pulse:SetToAlpha(peak * PULSE_DEPTH)
    pulse:SetDuration(0.55 / glowSpeed())
    pulse:SetSmoothing("IN_OUT")
    frame:Hide()
    g = { frame = frame, tex = tex, anim = anim, pulse = pulse }
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

-- ---------------------------------------------------------------------------
-- Multi-part shaped glow (the session-8 architecture): a per-silhouette OUTER
-- glow UNDER the icon (perfect outward falloff — the opaque icon hides the solid
-- centre, only the bloom peeks out) + an INNER glow OVER the gradient (interior-
-- edge tint, fading to a clean centre) + the Border recoloured to the glow tint.
-- One tintable WHITE pair per shape (Media/art/hand/<key>-outer|-inner) serves
-- procs / hover / cast / finish, differing only by tint. Supersedes the old single
-- soft-bloom (GetGlow) + the SDF state ring; the bloom stays as the fallback for
-- when no hand shape is set (post-migration, that never happens).
-- ---------------------------------------------------------------------------
local handGlows = {}   -- [btn] = { outer, innerFrame, inner }

-- The current shape's outer/inner glow art (nil → no hand shape → bloom fallback).
local function handGlowArt()
  local key = GB.db and GB.db.handShape
  if not key then return nil end
  return GB:HandAsset(key, "outer"), GB:HandAsset(key, "inner")
end

-- Shared pulse driver: ONE OnUpdate animates every ACTIVE multi-part glow's alpha
-- between the peak (Brightness) and peak × PULSE_DEPTH, so Brightness + Pulse speed
-- are live and all procs pulse in sync. Runs only while ≥1 glow is active (a hidden
-- frame's OnUpdate is paused), so it's free at rest.
local activeGlows = {}   -- set: [hg] = true
local pulsePhase = 0
local pulseDriver = CreateFrame("Frame")
pulseDriver:Hide()
pulseDriver:SetScript("OnUpdate", function(_, dt)
  pulsePhase = pulsePhase + dt * glowSpeed()
  local peak = glowPeak()
  local a = peak * (PULSE_DEPTH + (1 - PULSE_DEPTH) * (0.5 + 0.5 * math.cos(pulsePhase * 5.7)))
  for hg in pairs(activeGlows) do hg.outer:SetAlpha(a); hg.inner:SetAlpha(a) end
end)
local function setGlowActive(hg, on)
  if on then activeGlows[hg] = true; pulseDriver:Show()
  else activeGlows[hg] = nil; if not next(activeGlows) then pulseDriver:Hide() end end
end

-- Create (once) the per-button glow textures: outer UNDER the icon (BACKGROUND -2,
-- blooms out from behind), inner on its OWN frame ABOVE the gradient plate (btn+5,
-- so it wins over the plate). Pixel-snapping off (as Blizzard does on glow art) so
-- the inner glow's hard outer edge can't seam on fractional pixels.
local function getHandGlow(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return nil end
  local hg = handGlows[btn]
  if not hg then
    hg = {}
    hg.outer = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
    hg.innerFrame = CreateFrame("Frame", nil, btn)
    hg.innerFrame:SetFrameLevel(btn:GetFrameLevel() + 3)   -- above the gradient plate (+2), BELOW text (+4)
    hg.inner = hg.innerFrame:CreateTexture(nil, "OVERLAY")
    hg.outer:SetBlendMode("BLEND"); hg.inner:SetBlendMode("BLEND")
    for _, t in ipairs({ hg.outer, hg.inner }) do t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
    hg.outer:Hide(); hg.inner:Hide()
    handGlows[btn] = hg
  end
  return hg
end

-- Anchor the glow to the icon: the outer blooms from OUTSIDE the border (grown by
-- the border thickness so a thick border can't bury it), the inner overshoots the
-- rim ~2px to hide the hard-edge seam. Per-axis hand anchor → caps stay round.
local function anchorHandGlow(hg, icon)
  local bg = (GB.Skin and GB.Skin.BorderGrow and GB.Skin:BorderGrow()) or 0
  if GB.Skin and GB.Skin.AnchorHandGrown then
    GB.Skin:AnchorHandGrown(hg.outer, icon, bg)
    GB.Skin:AnchorHandGrown(hg.inner, icon, 2)
  else
    local m = 0.5 * math.min(icon:GetWidth(), icon:GetHeight())
    for _, t in ipairs({ hg.outer, hg.inner }) do
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", icon, "TOPLEFT", -m, m); t:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", m, -m)
    end
  end
end

-- Show the multi-part glow on one button, tinted `tint` ({r,g,b}); recolours its
-- border to match. Returns false when there's no hand shape (caller falls back).
local function applyHandGlow(btn, tint, pulse, peak)
  if not isOurs(btn) then return false end
  local outerArt, innerArt = handGlowArt()
  if not outerArt then return false end
  local hg = getHandGlow(btn)
  if not hg then return false end
  anchorHandGlow(hg, btn.icon or btn.Icon)
  hg.outer:SetTexture(outerArt); hg.inner:SetTexture(innerArt)
  hg.outer:SetVertexColor(tint[1], tint[2], tint[3]); hg.inner:SetVertexColor(tint[1], tint[2], tint[3])
  peak = peak or glowPeak()
  hg.outer:SetAlpha(peak); hg.inner:SetAlpha(peak)     -- Brightness/intensity; the driver pulses it if `pulse`
  hg.outer:Show(); hg.inner:Show()
  setGlowActive(hg, pulse and true or false)           -- only pulsing sources join the driver (static otherwise)
  if GB.Skin and GB.Skin.RecolorBorder then GB.Skin:RecolorBorder(btn, tint) end
  return true
end

local function hideHandGlow(btn)
  local hg = handGlows[btn]
  if hg then hg.outer:Hide(); hg.inner:Hide(); setGlowActive(hg, false) end
  if GB.Skin and GB.Skin.RecolorBorder then GB.Skin:RecolorBorder(btn, nil) end
end

-- One shaped glow per button; sources set flags and this reconciles visibility +
-- tint + pulse. Priority (highest first): assist highlight > proc > flash >
-- selected (toggled) > hover > dev test. Procs/assist/flash/test PULSE; the steady
-- states (selected/hover) are static. State highlights take stateIntensity for
-- brightness, procs take the proc Brightness. Routes to the multi-part glow when a
-- hand shape is active (the norm), else the old single soft-bloom fallback.
local PULSING = { assist = true, gold = true, flash = true, test = true }
local STATE_KEY = { flash = true, selected = true, hover = true }
local function Refresh(btn)
  local s = sources[btn]
  local tintKey = s and ((s.assist and "assist") or s.alert or (s.flash and "flash")
    or (s.selected and "selected") or (s.hover and "hover") or s.test) or nil
  if GB.db and GB.db.handShape then
    if tintKey then
      local peak = STATE_KEY[tintKey] and ((GB.db and GB.db.stateIntensity) or 1) or glowPeak()
      applyHandGlow(btn, tintFor(tintKey), PULSING[tintKey], peak)
    else
      hideHandGlow(btn)
    end
    return
  end
  local g = GetGlow(btn)
  if not g then return end
  if tintKey then
    local tint = tintFor(tintKey)
    g.tex:SetVertexColor(tint[1], tint[2], tint[3])
    if not g.frame:IsShown() then g.frame:Show(); g.anim:Play() end
  elseif g.frame:IsShown() then
    g.anim:Stop()
    g.frame:Hide()
  end
end

local function SetSource(btn, key, value)
  local s = sources[btn]
  if not s then s = {}; sources[btn] = s end
  value = value or nil
  if s[key] == value then return end   -- unchanged → skip the refresh churn (esp. the frequent state event)
  s[key] = value
  Refresh(btn)
end

function Glows:Init()
  if self.hooked then return end
  local alertMgr = ActionButtonSpellAlertManager
  local assistMgr = AssistedCombatManager
  if not alertMgr then return end
  self.hooked = true
  hooksecurefunc(alertMgr, "ShowAlert", function(_, btn)
    if not (Glows.enabled and isOurs(btn)) then return end   -- skip Cooldown Viewer frames (secret geometry)
    Silence(BlizzAlertFor(btn))   -- frame exists now: ShowAlert just created it
    local _, alertType = alertMgr:HasAlert(btn)
    local isAssistType = alertType == alertMgr.SpellAlertType.AssistedCombatRotation
    SetSource(btn, "alert", isAssistType and "assist" or "gold")
  end)
  hooksecurefunc(alertMgr, "HideAlert", function(_, btn)
    if not (Glows.enabled and isOurs(btn)) then return end
    SetSource(btn, "alert", nil)
  end)
  if assistMgr and assistMgr.SetAssistedHighlightFrameShown then
    hooksecurefunc(assistMgr, "SetAssistedHighlightFrameShown", function(_, btn, shown)
      if not (Glows.enabled and isOurs(btn)) then return end
      Silence(btn.AssistedCombatHighlightFrame)
      SetSource(btn, "assist", shown and true or nil)
    end)
  end
  -- Selected/toggled state (stances, toggled auras): Blizzard updates the checked
  -- state on ACTIONBAR_UPDATE_STATE. We react to it (reading GetChecked is not a
  -- secret combat value) and drive the shaped "selected" glow. (Hover is hooked
  -- per-button in SetEnabled via OnEnter/OnLeave.)
  local stateWatcher = CreateFrame("Frame")
  stateWatcher:RegisterEvent("ACTIONBAR_UPDATE_STATE")
  stateWatcher:SetScript("OnEvent", function()
    if not Glows.enabled then return end
    GB:ForEachButton(function(btn)
      if isOurs(btn) then SetSource(btn, "selected", (btn.GetChecked and btn:GetChecked()) and true or nil) end
    end)
  end)
end

function Glows:SetEnabled(on)
  self:Init()
  self.enabled = on
  ourSet = nil   -- rebuild the action-button set on next use (all buttons exist by now)
  if on then
    -- Adopt glow state already active at enable time + hook hover once per button.
    GB:ForEachButton(function(btn)
      -- Hover → shaped state glow. OnEnter/OnLeave is a safe script hook (we only
      -- set our own glow source, never a protected action). Hooked once.
      if not btn.gbHoverHooked then
        btn.gbHoverHooked = true
        btn:HookScript("OnEnter", function() if Glows.enabled then SetSource(btn, "hover", true) end end)
        btn:HookScript("OnLeave", function() if Glows.enabled then SetSource(btn, "hover", nil) end end)
      end
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
      if btn.GetChecked then SetSource(btn, "selected", btn:GetChecked() and true or nil) end
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

-- ---------------------------------------------------------------------------
-- Live style setters (Config → Proc glow). Each writes GB.db and re-applies to
-- every already-created halo; new halos read the db in GetGlow. Safe whether or
-- not the engine is enabled — hidden halos just pick the change up when shown.
-- ---------------------------------------------------------------------------
function Glows:ApplyStyle()
  local peak, speed = glowPeak(), glowSpeed()
  for btn, g in pairs(glows) do
    if isOurs(btn) then   -- never read a Cooldown Viewer's (secret) geometry from insecure config code
      local icon = btn.icon or btn.Icon
      if icon then anchorGlow(g.frame, icon) end
      if g.pulse then g.pulse:SetFromAlpha(peak); g.pulse:SetToAlpha(peak * PULSE_DEPTH); g.pulse:SetDuration(0.55 / speed) end
      if g.frame:IsShown() then g.anim:Stop(); g.anim:Play() end   -- restart so new pulse values take
      Refresh(btn)                                                 -- re-tint the shown ones
    end
  end
end

-- Shape change: re-point every halo's texture at the new shape's glow art. Plain
-- SetTexture (no mask quirk), so it swaps live. Called from Skin:SetShape — the
-- glow texture was previously set only at creation, so it went stale on a reshape.
function Glows:RefreshShape()
  local tex = currentGlowTex()
  for btn, g in pairs(glows) do
    if isOurs(btn) then g.tex:SetTexture(tex) end
  end
  -- Multi-part glow: re-point art at the new shape + re-anchor any SHOWN glow.
  local outerArt, innerArt = handGlowArt()
  for btn, hg in pairs(handGlows) do
    if isOurs(btn) and outerArt then
      hg.outer:SetTexture(outerArt); hg.inner:SetTexture(innerArt)
      if hg.outer:IsShown() then
        local icon = btn.icon or btn.Icon
        if icon then anchorHandGlow(hg, icon) end
      end
    end
  end
end

-- DEV: force the halo on (or off) for every button so it can be studied out of
-- combat. Uses a dedicated "test" source so it never collides with real procs.
function Glows:ForceTest(on)
  self:Init()
  forceScale = on and GLOW_SCALE or nil   -- pin the design scale while previewing
  GB:ForEachButton(function(btn) SetSource(btn, "test", on and "gold" or nil) end)
  for btn, g in pairs(glows) do
    if isOurs(btn) then local ic = btn.icon or btn.Icon; if ic then anchorGlow(g.frame, ic) end end
  end
  return on
end

-- DEV: swap the glow art to a candidate profile ("0"/"A"/"B"/"C"), or nil to
-- restore the real shape art. Re-points every existing halo live.
function Glows:SetTestArt(key)
  testArt = key and (GB.MEDIA .. "art\\gbtest-glow-" .. key .. ".png") or nil
  local tex = currentGlowTex()
  for btn, g in pairs(glows) do
    if isOurs(btn) then g.tex:SetTexture(tex) end
  end
  return key
end

-- DEV: force the multi-part glow ON (via a dedicated "test" source, so it never
-- collides with real procs) for every button, using the CURRENT shape's art —
-- lets the finished proc look be studied out of combat. /gb handglow on|off.
function Glows:HandPreview(on)
  self:Init()
  GB:ForEachButton(function(btn) SetSource(btn, "test", on and "gold" or nil) end)
end

-- Icon resized → re-anchor every shown glow so it keeps the icon's new size/aspect.
function Glows:RefreshSize()
  for btn, g in pairs(glows) do
    if isOurs(btn) then
      local icon = btn.icon or btn.Icon
      if icon then anchorGlow(g.frame, icon) end
    end
  end
  for btn, hg in pairs(handGlows) do
    if isOurs(btn) and hg.outer:IsShown() then
      local icon = btn.icon or btn.Icon
      if icon then anchorHandGlow(hg, icon) end
    end
  end
end

function Glows:SetColor(which, c)
  if not (GB.db and c) then return end
  if which == "assist" then GB.db.glowAssistColor = c else GB.db.glowColor = c end
  for btn in pairs(glows) do Refresh(btn) end
  for btn in pairs(handGlows) do Refresh(btn) end   -- re-tint an active multi-part glow live
end

-- Re-tint/re-brighten any ACTIVE state glow (hover/selected/flash) after a State-
-- highlight colour or intensity change in Config. Only touches shown state glows.
function Glows:RefreshState()
  for btn, s in pairs(sources) do
    if isOurs(btn) and (s.hover or s.selected or s.flash) then Refresh(btn) end
  end
end
function Glows:SetIntensity(v) if GB.db then GB.db.glowIntensity = v end; self:ApplyStyle() end
function Glows:SetSize(v) if GB.db then GB.db.glowScale = v end; self:ApplyStyle() end
function Glows:SetPulseSpeed(v) if GB.db then GB.db.glowPulseSpeed = v end; self:ApplyStyle() end
