-- Layout.lua — GB.Layout: the bar-layout engine (session 13, phase L1).
--
-- Gloom's Bars owns bar geometry PER BAR, opt-in (Config → Bar layout);
-- Edit Mode keeps owning any bar not flipped to us.
--
-- MECHANISM (source-verified, ActionBar.lua): Blizzard lays out each bar's
-- BUTTON CONTAINERS — plain unprotected Frames; the secure button sits
-- CENTER'ed inside its container (actionButton.container) — via
-- GridLayoutUtil in ActionBarMixin:UpdateGridLayout. We NEVER touch the
-- secure buttons: an owned bar's containers are re-anchored into OUR grid and
-- re-SCALED (scale inherits, so the button renders at the chosen size with
-- all its internal math intact — no SetSize on secure frames). Count hides
-- surplus CONTAINERS (out of combat, hiding an unprotected parent is the
-- sanctioned indirect route). Blizzard re-lays on its own triggers →
-- re-asserted in post-hooks of UpdateGridLayout/UpdateShownButtons.
--
-- HARD WALL: all geometry applies OUT OF COMBAT ONLY. In combat every apply
-- degrades to a queued flag, flushed on PLAYER_REGEN_ENABLED.
--
-- DATA: profile.barLayout[barKey] = { owned, size, gap, rows, horizontal,
-- count } — per bar, per PROFILE (settled with Jason: layout is bar geometry,
-- not part of a look preset; barKey = the bar's buttonPrefix, same key the
-- preset assignments use).

local GB = _G.GloomsBars

local Layout = {}
GB.Layout = Layout

local appliedBars = {}   -- [barKey] = true — bars whose containers we've re-laid (need Release when un-owned)
local pending = false    -- a combat-blocked apply; flushed when combat drops
local gridVisible = false   -- an action is on the cursor (SHOWGRID) — empty-button collapse suspends

-- Coalesce bursty triggers (a page flip fires ACTIONBAR_SLOT_CHANGED per slot)
-- into ONE ApplyAll next frame.
local applyQueued = false
local function queueApply()
  if applyQueued then return end
  applyQueued = true
  C_Timer.After(0, function() applyQueued = false; Layout:ApplyAll() end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("ACTIONBAR_SHOWGRID")
watcher:RegisterEvent("ACTIONBAR_HIDEGRID")
watcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    -- Combat starts → move mode closes itself (dragging + keyboard capture
    -- are combat-restricted; a half-open mode would just misbehave).
    if Layout.MoveModeOn and Layout:MoveModeOn() then Layout:SetMoveMode(false) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending then pending = false; Layout:ApplyAll() end
  elseif event == "ACTIONBAR_SHOWGRID" then gridVisible = true; queueApply()
  elseif event == "ACTIONBAR_HIDEGRID" then gridVisible = false; queueApply()
  elseif event == "ACTIONBAR_SLOT_CHANGED" then queueApply()   -- empty-collapse tracks slot contents
  end
end)

local function conf(barKey)
  local prof = GB.ActiveProfile and GB:ActiveProfile()
  local t = prof and prof.barLayout
  return t and t[barKey]
end

-- The MASTER switch (Jason: layout is all-or-nothing — one switch says
-- "Gloom's Bars arranges the bars", the per-bar tables below it are only
-- settings). Lives in the profile beside barLayout.
local function layoutOn()
  local prof = GB.ActiveProfile and GB:ActiveProfile()
  return (prof and prof.layoutEnabled) or false
end

-- The bar FRAME via its first button (Blizzard sets actionButton.bar at creation).
local function barFrameFor(barKey)
  local first = _G[barKey .. "1"]
  return first and first.bar
end

-- Re-lay one owned bar's containers into our grid. Offsets are computed in
-- BAR space then divided by the container scale (SetPoint offsets live in the
-- CHILD's scaled space).
local function applyBar(barKey)
  if not layoutOn() then return end
  local c = conf(barKey) or {}   -- an unconfigured bar lays out with the defaults
  local barFrame = barFrameFor(barKey)
  if not barFrame then return end
  -- Visibility override (c.vis): "show" forces a bar Edit Mode has disabled
  -- to appear, "hide" removes one, "combat"/"nocombat" show it only in/out of
  -- combat, nil leaves Blizzard's rules alone. Game-driven external hides
  -- (vehicles etc. — isShownExternal) always win on the show path.
  -- ★ Combat-conditional modes use RegisterStateDriver — the sanctioned
  -- secure API (nothing insecure may touch the bar once combat starts; the
  -- driver flips it inside the secure system at combat edges).
  -- ★ Static modes use the BASE (raw) show/hide: these bars OVERRIDE
  -- SetShown/Show/Hide to track external visibility — hiding through them
  -- poisoned isShownExternal, which then blocked our own show path (Jason's
  -- "can't show it again" bug). ShowBase/HideBase are what Blizzard's own
  -- UpdateVisibility uses.
  local vis = c.vis
  if vis == "combat" or vis == "nocombat" then
    if barFrame.gbVisDriver ~= vis then
      RegisterStateDriver(barFrame, "visibility",
        vis == "combat" and "[combat] show; hide" or "[nocombat] show; hide")
      barFrame.gbVisDriver = vis
    end
  else
    if barFrame.gbVisDriver then
      UnregisterStateDriver(barFrame, "visibility")
      barFrame.gbVisDriver = nil
      if barFrame.UpdateVisibility then pcall(barFrame.UpdateVisibility, barFrame) end
    end
    if vis == "hide" then
      if barFrame:IsShown() then (barFrame.HideBase or barFrame.Hide)(barFrame) end
    elseif vis == "show" and barFrame.isShownExternal ~= false then
      if not barFrame:IsShown() then (barFrame.ShowBase or barFrame.Show)(barFrame) end
    end
  end
  -- Position override (phase L3): c.posX/posY = the bar's CENTER in UIParent
  -- space; nil = Edit Mode's spot. SetPoint offsets live in the anchored
  -- frame's scaled space → divide by the relative scale.
  if c.posX ~= nil and c.posY ~= nil then
    local s = barFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if s > 0 then
      barFrame:ClearAllPoints()
      barFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", c.posX / s, c.posY / s)
    end
  end
  local count = math.max(1, math.min(12, c.count or 12))
  local rows = math.max(1, math.min(count, c.rows or 1))
  local gap = c.gap or 4              -- between adjacent buttons, along the bar's flow
  local gapCross = c.gapCross or gap  -- between rows (columns on a vertical bar); defaults to gap
  local horizontal = c.horizontal ~= false
  local stride = math.ceil(count / rows)
  local shown = {}
  for i = 1, 12 do
    local btn = _G[barKey .. i]
    local cont = btn and btn.container
    if cont then
      local inGrid = i <= count
      local show = inGrid
      -- Empty-button collapse (c.showEmpty == false, Jason: "or does it just
      -- disappear entirely"): react to the rendered icon — Blizzard Hide()s
      -- it when the slot has no action (the skin's empty-slot signal, no API
      -- read). Suspended while the pickup grid is out (drop targets stay).
      if show and c.showEmpty == false and not gridVisible then
        local ic = btn.icon or btn.Icon
        if not (ic and ic:IsShown()) then show = false end
      end
      cont:SetShown(show)
      local native = cont:GetWidth()   -- unscaled (SetScale never changes it)
      local scale = (c.size and native > 0) and (c.size / native) or 1
      cont:SetScale(scale)
      -- A collapsed empty KEEPS its grid slot (a hole, not a shuffle) so the
      -- other buttons never move as slots fill and empty.
      if inGrid then shown[#shown + 1] = { cont = cont, scale = scale, px = native * scale } end
    end
  end
  for idx, e in ipairs(shown) do
    local major = math.floor((idx - 1) / stride)   -- row (horizontal) / column (vertical)
    local minor = (idx - 1) % stride
    -- Gaps may be NEGATIVE (Jason: hex/circle silhouettes don't fill their
    -- square rects — overlap the frames so the shapes nestle). Clamp the step
    -- so extreme size+overlap combos can never stack buttons on one spot.
    local stepMain = math.max(e.px + gap, 4)
    local stepCross = math.max(e.px + gapCross, 4)
    local xBar, yBar
    if horizontal then xBar, yBar = minor * stepMain, -major * stepCross
    else xBar, yBar = major * stepCross, -minor * stepMain end
    e.cont:ClearAllPoints()
    e.cont:SetPoint("TOPLEFT", barFrame, "TOPLEFT", xBar / e.scale, yBar / e.scale)
  end
  -- Re-fit the bar frame to the new grid (ResizeLayoutFrame): keeps Edit
  -- Mode's selection box + the flyout-direction math honest. pcall = fail
  -- soft; we're out of combat by contract.
  if barFrame.Layout then pcall(barFrame.Layout, barFrame) end
  appliedBars[barKey] = true
end

-- Hand a bar BACK to Edit Mode: reset container scale and ask Blizzard to
-- re-lay with its own settings (cache invalidated so UpdateGridLayout
-- actually runs). Out-of-combat only, like every geometry path here.
local releasing = false   -- reentrancy guard: the Blizzard calls below fire OUR post-hooks
local function releaseBar(barKey)
  if not appliedBars[barKey] then return end
  local barFrame = barFrameFor(barKey)
  if not barFrame then return end
  -- Unmark FIRST + guard: UpdateShownButtons/UpdateGridLayout fire our own
  -- Reassert hooks, which must not re-enter release mid-revert (that recursed
  -- until the pcall swallowed a stack error, leaving the grid half-reverted —
  -- Jason's "Rows don't revert" bug).
  appliedBars[barKey] = nil
  releasing = true
  for i = 1, 12 do
    local btn = _G[barKey .. i]
    if btn and btn.container then btn.container:SetScale(1) end
  end
  if barFrame.gbVisDriver then   -- drop any combat-visibility driver
    UnregisterStateDriver(barFrame, "visibility")
    barFrame.gbVisDriver = nil
  end
  barFrame.oldGridSettings = nil   -- invalidate ShouldUpdateGrid's cache
  if barFrame.UpdateShownButtons then pcall(barFrame.UpdateShownButtons, barFrame) end
  if barFrame.UpdateGridLayout then pcall(barFrame.UpdateGridLayout, barFrame) end
  if barFrame.UpdateVisibility then pcall(barFrame.UpdateVisibility, barFrame) end   -- undo any vis override
  if barFrame.ApplySystemAnchor then pcall(barFrame.ApplySystemAnchor, barFrame) end -- undo any position override
  if barFrame.Layout then pcall(barFrame.Layout, barFrame) end
  releasing = false
end

-- Apply every owned bar; release bars we'd laid out that are no longer owned
-- (profile switch, un-own toggle). THE combat gate: in combat this only
-- queues, and the watcher re-runs it the moment combat drops.
function Layout:ApplyAll()
  if InCombatLockdown() then pending = true; return end
  local on = layoutOn()
  for _, bar in ipairs(GB.BARS) do
    local key = bar.buttonPrefix
    if on then applyBar(key)
    elseif appliedBars[key] then releaseBar(key) end
  end
end

-- Per-bar re-assert, used by the Blizzard-side post-hooks and Config setters.
function Layout:Reassert(barKey)
  if releasing then return end
  if not layoutOn() then
    if appliedBars[barKey] then
      if InCombatLockdown() then pending = true else releaseBar(barKey) end
    end
    return
  end
  if InCombatLockdown() then pending = true; return end
  applyBar(barKey)
end

-- ---------------------------------------------------------------------------
-- Move mode (phase L3): a translucent family-purple mover over every bar —
-- drag to position, click to select, arrow keys nudge 1px, Shift+arrow 10px
-- (Jason's spec). ESC or the Config button exits; entering combat exits
-- automatically (dragging + SetPropagateKeyboardInput are combat-restricted).
-- Movers are parented to UIParent, not the bars, so a hidden bar can still be
-- positioned. Positions save as c.posX/posY the moment a drag or nudge lands.
local movers = {}
local moveModeOn = false
local selectedMover

local function ensureConf(barKey)
  local prof = GB.ActiveProfile and GB:ActiveProfile()
  if not prof then return nil end
  prof.barLayout = prof.barLayout or {}
  prof.barLayout[barKey] = prof.barLayout[barKey] or
    { size = 45, gap = 4, rows = 1, horizontal = true, count = 12 }
  return prof.barLayout[barKey]
end

local function anchorMover(m)
  local bf = barFrameFor(m.barKey)
  if not bf then return end
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", bf, "TOPLEFT", -4, 4)
  m:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", 4, -4)
end

local function selectMover(m)
  selectedMover = m
  for _, e in pairs(movers) do e.fill:SetAlpha(e == m and 0.45 or 0.22) end
end

local function roundf(x) return math.floor(x + 0.5) end

-- Capture a bar's CURRENT centre into its conf (UIParent space, whole px) —
-- the first nudge of an Edit-Mode-positioned bar starts from where it is.
local function captureBarCenter(barKey, c)
  local bf = barFrameFor(barKey)
  if not (bf and c) then return false end
  local fx, fy = bf:GetCenter()
  if not fx then return false end
  local s = bf:GetEffectiveScale() / UIParent:GetEffectiveScale()
  c.posX, c.posY = roundf(fx * s), roundf(fy * s)
  return true
end

-- Live coordinates on the overlay, CENTER-RELATIVE (Jason: 0 on X = perfectly
-- centred; negative left / positive right; Y likewise from the vertical
-- midline). Updated on drag, nudge, and mode entry.
local function updateMoverCoord(m)
  local bf = barFrameFor(m.barKey)
  if not (bf and m.coord) then return end
  local fx, fy = bf:GetCenter()
  if not fx then return end
  local s = bf:GetEffectiveScale() / UIParent:GetEffectiveScale()
  m.coord:SetText(("%d, %d"):format(
    roundf(fx * s - UIParent:GetWidth() / 2),
    roundf(fy * s - UIParent:GetHeight() / 2)))
end

local function moverFor(barKey)
  local m = movers[barKey]
  if m then return m end
  m = CreateFrame("Frame", nil, UIParent)
  m.barKey = barKey
  m:SetFrameStrata("DIALOG")
  m:EnableMouse(true)
  m:SetMovable(true)
  m:RegisterForDrag("LeftButton")
  m.fill = m:CreateTexture(nil, "BACKGROUND")
  m.fill:SetAllPoints()
  m.fill:SetColorTexture(0.58, 0.42, 1, 1)
  m.fill:SetAlpha(0.22)
  m.label = m:CreateFontString(nil, "OVERLAY")
  m.label:SetFont(GB.FONT.label, 12, "OUTLINE")
  m.label:SetPoint("CENTER", 0, 7)
  m.coord = m:CreateFontString(nil, "OVERLAY")
  m.coord:SetFont(GB.FONT.label, 11, "OUTLINE")
  m.coord:SetPoint("TOP", m.label, "BOTTOM", 0, -2)
  m:SetScript("OnMouseDown", function(self) selectMover(self) end)
  m:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    selectMover(self)
    self:StartMoving()
    self.dragging = true
  end)
  m:SetScript("OnUpdate", function(self)
    if self.dragging and not InCombatLockdown() then
      -- The bar follows the mover live while dragging.
      local fx, fy = self:GetCenter()   -- mover sits at UIParent scale
      local bf = barFrameFor(self.barKey)
      if bf and fx then
        local s = bf:GetEffectiveScale() / UIParent:GetEffectiveScale()
        bf:ClearAllPoints()
        bf:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fx / s, fy / s)
        updateMoverCoord(self)
      end
    end
  end)
  m:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.dragging = nil
    local fx, fy = self:GetCenter()
    local c = ensureConf(self.barKey)
    if c and fx then
      c.posX, c.posY = roundf(fx), roundf(fy)   -- whole px, so exactly 0 is reachable
      Layout:Reassert(self.barKey)
    end
    anchorMover(self)   -- snap back over the (now-moved) bar
    updateMoverCoord(self)
  end)
  movers[barKey] = m
  return m
end

-- One keyboard catcher for the whole mode: arrows nudge the selected mover,
-- everything else passes through to the game. SetPropagateKeyboardInput is
-- combat-restricted — move mode exits on PLAYER_REGEN_DISABLED before it
-- could matter.
local keyCatcher = CreateFrame("Frame", nil, UIParent)
keyCatcher:Hide()
keyCatcher:SetFrameStrata("TOOLTIP")
keyCatcher:EnableKeyboard(true)
keyCatcher:SetPropagateKeyboardInput(true)
keyCatcher:SetScript("OnKeyDown", function(self, key)
  if InCombatLockdown() then return end   -- can't even change propagation in combat
  if key == "ESCAPE" then
    self:SetPropagateKeyboardInput(false)
    Layout:SetMoveMode(false)
    return
  end
  local dx, dy = 0, 0
  if key == "UP" then dy = 1 elseif key == "DOWN" then dy = -1
  elseif key == "LEFT" then dx = -1 elseif key == "RIGHT" then dx = 1
  else self:SetPropagateKeyboardInput(true); return end
  if not selectedMover then self:SetPropagateKeyboardInput(true); return end
  self:SetPropagateKeyboardInput(false)
  local mult = IsShiftKeyDown() and 10 or 1
  local barKey = selectedMover.barKey
  local c = ensureConf(barKey)
  if not c then return end
  if c.posX == nil and not captureBarCenter(barKey, c) then return end
  c.posX = c.posX + dx * mult
  c.posY = c.posY + dy * mult
  Layout:Reassert(barKey)
  anchorMover(selectedMover)
  updateMoverCoord(selectedMover)
end)

function Layout:SetMoveMode(on)
  if on and InCombatLockdown() then
    GB.msg("move mode needs you out of combat.")
    return
  end
  moveModeOn = on and true or false
  if moveModeOn then
    for _, bar in ipairs(GB.BARS) do
      if barFrameFor(bar.buttonPrefix) then
        local m = moverFor(bar.buttonPrefix)
        m.label:SetText(bar.label)
        anchorMover(m)
        updateMoverCoord(m)
        m:Show()
      end
    end
    selectMover(nil)
    keyCatcher:Show()
  else
    for _, m in pairs(movers) do m.dragging = nil; m:Hide() end
    selectedMover = nil
    keyCatcher:Hide()
  end
  local C = GB.Config
  if C and C.Refresh then C:Refresh() end   -- the Move-bars button reflects the mode
end
function Layout:MoveModeOn() return moveModeOn end

-- Reset one bar to Edit Mode's position (the Config button).
function Layout:ResetPosition(barKey)
  local c = conf(barKey)
  if c then c.posX, c.posY = nil, nil end
  local bf = barFrameFor(barKey)
  if bf and not InCombatLockdown() and bf.ApplySystemAnchor then
    releasing = true
    pcall(bf.ApplySystemAnchor, bf)
    releasing = false
  end
  local m = movers[barKey]
  if m and m:IsShown() then anchorMover(m); updateMoverCoord(m) end
end

-- Blizzard re-lays containers on Edit Mode changes, grid events, etc. →
-- re-assert ours right after, per bar. Installed once at login.
function Layout:Init()
  if self.hooked then return end
  self.hooked = true
  for _, bar in ipairs(GB.BARS) do
    local key = bar.buttonPrefix
    local bf = barFrameFor(key)
    if bf then
      if bf.UpdateGridLayout then
        hooksecurefunc(bf, "UpdateGridLayout", function() Layout:Reassert(key) end)
      end
      if bf.UpdateShownButtons then
        hooksecurefunc(bf, "UpdateShownButtons", function() Layout:Reassert(key) end)
      end
      if bf.UpdateVisibility then
        hooksecurefunc(bf, "UpdateVisibility", function() Layout:Reassert(key) end)
      end
      if bf.ApplySystemAnchor then   -- Edit Mode re-anchoring → re-assert our position
        hooksecurefunc(bf, "ApplySystemAnchor", function() Layout:Reassert(key) end)
      end
    end
  end
end
