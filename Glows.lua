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
local function tintFor(key)
  if key == "assist" then return (GB.db and GB.db.glowAssistColor) or TINT.assist end
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

-- One shaped halo per button; sources (alert / assist highlight) set flags and
-- this reconciles visibility + tint. Assist blue wins when both are active
-- (mirrors Blizzard's own downgrade logic).
local function Refresh(btn)
  local s = sources[btn]
  local g = GetGlow(btn)
  if not g then return end
  local tintKey = s and (s.assist and "assist" or s.alert or s.test) or nil
  if tintKey then
    local tint = tintFor(tintKey)
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
end

function Glows:SetEnabled(on)
  self:Init()
  self.enabled = on
  ourSet = nil   -- rebuild the action-button set on next use (all buttons exist by now)
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

-- DEV (Phase 3 milestone 1): draw Jason's hand-authored MULTI-PART glow — outer
-- UNDER the icon (perfect outward falloff) + inner OVER it (interior tint) — tinted,
-- on every button. Isolated from the proc engine so it can't destabilize it. Anchored
-- per the hand-asset canvas convention: the shape sits in a 256-of-512 reference rect
-- with a 128px margin, so the glow frame = icon expanded by 0.5x the icon's short side
-- on every side (which maps the reference rect onto the icon). Set the matching icon
-- shape first so the silhouettes line up. /gb handglow <square|pill32|off>.
local handGlows = {}   -- [btn] = { outer, innerFrame, inner }
function Glows:HandPreview(shape, color)
  local art = shape and {
    outer = GB.MEDIA .. "art\\hand\\" .. shape .. "-outer.png",
    inner = GB.MEDIA .. "art\\hand\\" .. shape .. "-inner.png",
  }
  local c = color or { 1, 0.82, 0.3 }   -- gold, like a proc
  GB:ForEachButton(function(btn)
    local icon = btn.icon or btn.Icon
    if not icon then return end
    local hg = handGlows[btn]
    if not art then
      if hg then hg.outer:Hide(); hg.inner:Hide() end
      return
    end
    if not hg then
      hg = {}
      -- Outer: a texture UNDER the icon (blooms out from behind). Inner: on its OWN
      -- frame ABOVE the gradient plate (rec.decorFrame = btn+2), so the glow wins over
      -- any gradient. (Text lives at frameLevel 500, so +5 stays below the keybind/count.)
      hg.outer = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
      hg.innerFrame = CreateFrame("Frame", nil, btn)
      hg.innerFrame:SetFrameLevel(btn:GetFrameLevel() + 5)
      hg.inner = hg.innerFrame:CreateTexture(nil, "OVERLAY")
      hg.outer:SetBlendMode("BLEND")   -- colored glow (matches the approved preview)
      hg.inner:SetBlendMode("BLEND")
      -- Blizzard disables pixel snapping on their glow/highlight textures to avoid
      -- sub-pixel edge seams (see the TargetReticle Highlight in the template); the
      -- inner glow's hard outer edge needs the same or it seams on fractional pixels.
      for _, t in ipairs({ hg.outer, hg.inner }) do
        t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0)
      end
      handGlows[btn] = hg
    end
    -- Outer glow blooms from OUTSIDE the border (grown by the border thickness) so a
    -- thick border can't bury the glow's brightest edge. Inner glow overshoots the icon
    -- rim by ~2px to hide the hard-edge seam. Both use the per-axis hand anchor so caps
    -- stay round on elongated shapes.
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
    hg.outer:SetTexture(art.outer); hg.inner:SetTexture(art.inner)
    hg.outer:SetVertexColor(c[1], c[2], c[3]); hg.inner:SetVertexColor(c[1], c[2], c[3])
    hg.outer:Show(); hg.inner:Show()
  end)
  if GB.Skin and GB.Skin.RecolorBorders then
    GB.Skin:RecolorBorders(art and c or nil)   -- border adopts the glow colour when present
  end
end

-- Icon resized → re-anchor every halo so it keeps the icon's new size + aspect.
function Glows:RefreshSize()
  for btn, g in pairs(glows) do
    if isOurs(btn) then
      local icon = btn.icon or btn.Icon
      if icon then anchorGlow(g.frame, icon) end
    end
  end
end

function Glows:SetColor(which, c)
  if not (GB.db and c) then return end
  if which == "assist" then GB.db.glowAssistColor = c else GB.db.glowColor = c end
  for btn in pairs(glows) do Refresh(btn) end
end
function Glows:SetIntensity(v) if GB.db then GB.db.glowIntensity = v end; self:ApplyStyle() end
function Glows:SetSize(v) if GB.db then GB.db.glowScale = v end; self:ApplyStyle() end
function Glows:SetPulseSpeed(v) if GB.db then GB.db.glowPulseSpeed = v end; self:ApplyStyle() end
