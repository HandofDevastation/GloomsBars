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

-- Live-tunable pulse values (Config → Glows, stored in GB.db). Accessors so the
-- engine always reads the current value; the shared pulse driver uses each active
-- glow's OWN peak (per-trigger opacity), glowPeak is its fallback.
local PULSE_DEPTH = 0.5   -- the pulse always dips to this fraction of the peak, so it stays visible
local function glowPeak() return (GB.db and GB.db.glowIntensity) or 0.9 end   -- fallback PEAK alpha
local function glowSpeed() return math.max(0.1, (GB.db and GB.db.glowPulseSpeed) or 1) end

local sources = {}    -- [button] = { alert = "gold"|"assist"|nil, assist/highlight/cast/flash/selected/hover flags }
local silenced = {}   -- [blizzard frame] = true — frames we alpha-0'd

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
-- procs / hover / cast / finish, differing only by tint. (The pre-hand SDF
-- soft-bloom fallback was unreachable — db.handShape is always seeded — and was
-- removed in session 12 along with the /gb glowtest bake-off harness.)
-- ---------------------------------------------------------------------------
local handGlows = {}   -- [btn] = { outer, innerFrame, inner }

-- The current shape's outer/inner glow art.
local function handGlowArt()
  local key = (GB.Skin and GB.Skin.PV) and GB.Skin:PV("handShape") or (GB.db and GB.db.handShape)
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
  local wave = PULSE_DEPTH + (1 - PULSE_DEPTH) * (0.5 + 0.5 * math.cos(pulsePhase * 5.7))
  for hg in pairs(activeGlows) do
    local a = (hg.peak or glowPeak()) * wave    -- each active glow pulses about ITS trigger's opacity
    if hg.showOuter then hg.outer:SetAlpha(a) end
    if hg.showInner then hg.inner:SetAlpha(a) end
  end
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

-- Show the multi-part glow on one button, tinted `tint` ({r,g,b}) at `peak` opacity;
-- `layers` ("both"/"inner"/"outer") gates which of the two glow textures show, and
-- recolours its border to match. Returns false when there's no hand shape (fallback).
local function applyHandGlow(btn, tint, pulse, peak, layers)
  if not isOurs(btn) then return false end
  local outerArt, innerArt = handGlowArt()
  if not outerArt then return false end
  local hg = getHandGlow(btn)
  if not hg then return false end
  -- In plate mode the glow spans the full 2:1 plate (ConstructRef), not the half-height icon.
  anchorHandGlow(hg, (GB.Skin and GB.Skin.ConstructRef and GB.Skin:ConstructRef(btn)) or (btn.icon or btn.Icon))
  hg.outer:SetTexture(outerArt); hg.inner:SetTexture(innerArt)
  hg.outer:SetVertexColor(tint[1], tint[2], tint[3]); hg.inner:SetVertexColor(tint[1], tint[2], tint[3])
  peak = peak or glowPeak()
  local showOuter = layers ~= "inner"                  -- per-trigger layer choice
  local showInner = layers ~= "outer"
  hg.peak, hg.showOuter, hg.showInner = peak, showOuter, showInner
  hg.outer:SetAlpha(peak); hg.inner:SetAlpha(peak)     -- Opacity; the driver pulses it if `pulse`
  hg.outer:SetShown(showOuter); hg.inner:SetShown(showInner)
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
-- tint + opacity + layers + pulse. Each button state is a TRIGGER record in
-- GB.db.triggers { enabled, color, opacity, layers }; the winning trigger is chosen
-- by priority (highest first): assist highlight > proc > spell-highlight > cast/channel > flash >
-- selected (toggled) > hover — SKIPPING any the user disabled, so turning
-- off e.g. Hover still lets a checked button show its Selected glow. Procs/assist/
-- flash/highlight pulse; cast/channel/hover/selected are steady. Always the
-- multi-part hand glow (db.handShape is always seeded).
local PULSING = { proc = true, assist = true, flash = true, highlight = true }   -- which triggers pulse
-- Stage-3 per-bar presets: reads funnel through Skin's PV (ONE ctx, owned by
-- Skin — see Skin:EnterButtonCtx), so a bar wearing another preset resolves
-- ITS triggers/shape. Outside any ctx this is exactly the old working-copy read.
local function skinPV(field)
  local S = GB.Skin
  if S and S.PV then return S:PV(field) end
  return GB.db and GB.db[field]
end
local function trig(key) local ts = skinPV("triggers"); return ts and ts[key] end
local function enabledTrig(key) local t = trig(key); if t and t.enabled ~= false then return t end end

-- The winning trigger key + record for a button's live sources, in priority order,
-- skipping disabled triggers. Returns (triggerKey, record) or nil.
local function winningTrigger(s)
  if not s then return nil end
  if s.assist then local t = enabledTrig("assist"); if t then return "assist", t end end
  if s.alert == "assist" then local t = enabledTrig("assist"); if t then return "assist", t end
  elseif s.alert == "gold" then local t = enabledTrig("proc"); if t then return "proc", t end end
  if s.highlight then local t = enabledTrig("highlight"); if t then return "highlight", t end end   -- "press this"
  if s.cast then local t = enabledTrig(s.cast); if t then return s.cast, t end end   -- s.cast = "cast"|"channel"
  if s.flash then local t = enabledTrig("flash"); if t then return "flash", t end end
  if s.selected then local t = enabledTrig("selected"); if t then return "selected", t end end
  if s.hover then local t = enabledTrig("hover"); if t then return "hover", t end end
  return nil
end
-- Resolve a winning trigger's tint / pulse / peak / layers from its record.
local function resolveGlow(triggerKey, t)
  return (t.color or { 1, 1, 1 }), (PULSING[triggerKey] and true or false), (t.opacity or 1), (t.layers or "both")
end
local function Refresh(btn)
  local s = sources[btn]
  local triggerKey, t = winningTrigger(s)
  if triggerKey then applyHandGlow(btn, resolveGlow(triggerKey, t))   -- (tint, pulse, peak, layers)
  else hideHandGlow(btn) end
  if GB.Anims then GB.Anims:Reconcile(btn, triggerKey, t) end   -- per-trigger animations track the winning glow
end

local function SetSource(btn, key, value)
  local s = sources[btn]
  if not s then s = {}; sources[btn] = s end
  value = value or nil
  if s[key] == value then return end   -- unchanged → skip the refresh churn (esp. the frequent state event)
  s[key] = value
  Refresh(btn)
end

-- Stage-3: enter the button's preset ctx around the reconciler, so trig()/
-- handGlowArt() AND any Skin-side math in the chain (anchor growth, hand
-- art) resolve this button's preset. Closures capture the local → every
-- caller above gets the wrapped version.
do
  local inner = Refresh
  Refresh = function(btn)
    local S = GB.Skin
    if not (S and S.EnterButtonCtx) then return inner(btn) end
    local pP, pS = S:EnterButtonCtx(btn)
    inner(btn)
    S:LeaveButtonCtx(pP, pS)
  end
end

-- Cast / channel source. Blizzard's PlaySpellCastAnim (hooked in Skin.lua's decoration
-- engine) starts it; the CastFill end-hook clears it (kind = nil). PUBLIC because those
-- hooks live in Skin.lua. kind = "cast" | "channel" | nil — winningTrigger uses the string
-- as BOTH the presence flag and the trigger key, so it drives the matching glow + animation.
function Glows:SetCast(btn, kind)
  if not (Glows.enabled and isOurs(btn)) then return end   -- our action buttons only (skip Cooldown Viewer)
  SetSource(btn, "cast", kind)
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
  -- Spell highlight ("you should press this", EFFECTS-MATRIX §B gap): Blizzard pulses
  -- a square mouseover frame via SharedActionButton_RefreshSpellHighlight(button,
  -- shown). Post-hook: kill the square (STOP the looping alpha anim — it re-drives
  -- the texture alpha every frame, so a one-shot alpha-0 loses — then hide) and
  -- route the state to the shaped "highlight" glow trigger instead.
  if type(SharedActionButton_RefreshSpellHighlight) == "function" then
    hooksecurefunc("SharedActionButton_RefreshSpellHighlight", function(btn, shown)
      if not (Glows.enabled and isOurs(btn)) then return end
      if btn.SpellHighlightAnim then btn.SpellHighlightAnim:Stop() end
      if btn.SpellHighlightTexture then btn.SpellHighlightTexture:Hide() end
      SetSource(btn, "highlight", shown and true or nil)
    end)
  end
  -- Selected/toggled state (stances, toggled auras): Blizzard updates the checked
  -- state on ACTIONBAR_UPDATE_STATE. We react to it (reading GetChecked is not a
  -- secret combat value) and drive the shaped "selected" glow. (Hover is hooked
  -- per-button in SetEnabled via OnEnter/OnLeave.)
  -- ★ Pet/stance checked state (assist/passive/defensive, shapeshift form) is
  -- driven by PetActionBar/StanceBar :Update on their OWN events — NOT
  -- ACTIONBAR_UPDATE_STATE. Without these, switching pet stance left our Selected
  -- glow stuck on the previously-checked button (Jason: assist→passive kept the
  -- glow on assist). Re-read GetChecked on the same events the skin re-decors on.
  local stateWatcher = CreateFrame("Frame")
  stateWatcher:RegisterEvent("ACTIONBAR_UPDATE_STATE")
  stateWatcher:RegisterEvent("PET_BAR_UPDATE")
  stateWatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
  stateWatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
  -- The "selected" glow faithfully mirrors Blizzard's checked state. ★ Verified
  -- against the native pet bar (GB fully disabled): Blizzard KEEPS the stance
  -- button (e.g. Passive) checked even while the pet is actively attacking — Kill
  -- Command does not change the stance, so Passive stays selected. That's odd but
  -- it IS Blizzard's behavior (Jason confirmed), and their own glow is just so
  -- subtle it's easy to miss. We mirror it — and the "selected" trigger defaults
  -- to a SOFT-BLUE INNER-ONLY glow (Core seed) so a persistently-lit stance reads
  -- as a quiet indicator, not a shout. Tunable per-trigger in the Glows section.
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
        -- Flash (auto-attack / auto-shot active): StartFlash/StopFlash toggle the
        -- flashing STATE (not each blink), so drive the shaped flash glow off them.
        if btn.StartFlash then hooksecurefunc(btn, "StartFlash", function(b) if Glows.enabled then SetSource(b, "flash", true) end end) end
        if btn.StopFlash then hooksecurefunc(btn, "StopFlash", function(b) if Glows.enabled then SetSource(b, "flash", nil) end end) end
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
      if btn.IsFlashing then SetSource(btn, "flash", btn:IsFlashing() == 1 and true or nil) end
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

-- Shape change: re-point the multi-part glow art at the new shape + re-anchor any
-- SHOWN glow. Plain SetTexture (no mask quirk), so it swaps live.
function Glows:RefreshShape()
  local S = GB.Skin
  for btn, hg in pairs(handGlows) do
    if isOurs(btn) then
      -- Art + anchors resolve PER BUTTON now (bars can wear different presets).
      local pP, pS; if S and S.EnterButtonCtx then pP, pS = S:EnterButtonCtx(btn) end
      local outerArt, innerArt = handGlowArt()
      if outerArt then
        hg.outer:SetTexture(outerArt); hg.inner:SetTexture(innerArt)
        if hg.outer:IsShown() then
          local icon = btn.icon or btn.Icon
          if icon then anchorHandGlow(hg, icon) end
        end
      end
      if S and S.LeaveButtonCtx then S:LeaveButtonCtx(pP, pS) end
    end
  end
end

-- Icon resized → re-anchor every shown glow so it keeps the icon's new size/aspect.
function Glows:RefreshSize()
  local S = GB.Skin
  for btn, hg in pairs(handGlows) do
    if isOurs(btn) and hg.outer:IsShown() then
      local icon = btn.icon or btn.Icon
      if icon then
        local pP, pS; if S and S.EnterButtonCtx then pP, pS = S:EnterButtonCtx(btn) end
        anchorHandGlow(hg, icon)
        if S and S.LeaveButtonCtx then S:LeaveButtonCtx(pP, pS) end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Per-trigger live setters (Config → Glows matrix). Each writes the trigger's
-- record in GB.db.triggers and re-applies to the buttons currently showing it.
-- Colour/opacity/layers only affect a shown glow of that trigger; enable can change
-- the WINNER on any button (a disabled trigger drops to the next), so it refreshes all.
-- ---------------------------------------------------------------------------
function Glows:RefreshTrigger(key)
  local S = GB.Skin
  for btn, s in pairs(sources) do
    if isOurs(btn) then
      -- The winner check reads trig() → resolve it under the button's ctx too.
      local pP, pS; if S and S.EnterButtonCtx then pP, pS = S:EnterButtonCtx(btn) end
      local isWinner = winningTrigger(s) == key
      if S and S.LeaveButtonCtx then S:LeaveButtonCtx(pP, pS) end
      if isWinner then Refresh(btn) end
    end
  end
end
function Glows:SetTriggerColor(key, c)
  local t = trig(key); if not (t and c) then return end
  t.color = c; self:RefreshTrigger(key)
end
function Glows:SetTriggerOpacity(key, v)
  local t = trig(key); if not t then return end
  t.opacity = v; self:RefreshTrigger(key)
end
function Glows:SetTriggerLayers(key, mode)
  local t = trig(key); if not t then return end
  t.layers = mode; self:RefreshTrigger(key)
end
function Glows:SetTriggerEnabled(key, on)
  local t = trig(key); if not t then return end
  t.enabled = on and true or false
  for btn in pairs(sources) do if isOurs(btn) then Refresh(btn) end end   -- winner may change on any button
end

-- Re-tint/re-brighten any ACTIVE state glow (hover/selected/flash) after a State-
-- highlight colour or intensity change in Config. Only touches shown state glows.
function Glows:RefreshState()
  for btn, s in pairs(sources) do
    if isOurs(btn) and (s.hover or s.selected or s.flash) then Refresh(btn) end
  end
end
