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
watcher:RegisterEvent("ACTIONBAR_SHOWGRID")
watcher:RegisterEvent("ACTIONBAR_HIDEGRID")
watcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
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
    end
  end
end
