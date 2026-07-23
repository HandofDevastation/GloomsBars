-- Config.lua — Gloom's Bars: the style editor (Config UI)
--
-- The product's front end (docs/HANDOFF.md ★ NORTH STAR): author button styles
-- through the UI, not baked-in recipes. Built in the GloomsAuras family design
-- language (docs/CLAUDE.md): flat SQUARED chrome, near-black navy plate, bright
-- purple #936BFF accents, deep-purple low-alpha fills, orange #FF7729 carets +
-- bottom glow, Khand uppercase headers + GeneralSans body, sliding toggles. The
-- toolkit mirrors GloomsAuras/Config.lua so the siblings feel identical.
--
-- Increment 1 (this file): the window shell + toolkit + one-open accordion, the
-- master Enable switch (wired live to GB.Skin), and a working shape picker. The
-- remaining sections are stubbed headers — each gets wired to the skin engine in
-- following passes. Opens with /gb.

local GB = _G.GloomsBars

local C = {}
GB.Config = C

local COLOR, FONT = GB.COLOR, GB.FONT
local TEXT = { r = 0.90, g = 0.92, b = 0.96 }   -- body text
local MUTE = { r = 0.55, g = 0.57, b = 0.63 }   -- hints / secondary
local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CARET_TEX = GB.MEDIA .. "ui\\caret.png"
local CARET_DOWN = -math.pi / 2                 -- rotate right-pointing source to point down (open)
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- --------------------------------------------------------------------------
-- Skin toolkit (ported from GloomsAuras/Config.lua — same primitives).
-- --------------------------------------------------------------------------
local function setFont(fs, path, size, flags)
  if not fs:SetFont(path, size, flags or "") then fs:SetFont(DEFAULT_FONT, size, flags or "") end
end

local function newText(parent, font, size, cc, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  setFont(fs, font, size)
  if cc then fs:SetTextColor(cc.r, cc.g, cc.b) end
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

-- Four 1px edge textures forming a squared border.
local function addEdges(f, cc, thick)
  thick = thick or 1
  local function edge(p1, p2, w, h)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(cc.r, cc.g, cc.b, cc.a or 1)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    return t
  end
  edge("TOPLEFT", "TOPRIGHT", nil, thick)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, thick)
  edge("TOPLEFT", "BOTTOMLEFT", thick, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", thick, nil)
end

-- Flat dark fill (renders #060714 on screen; the pre-compensated token is in Core.lua).
local function skinPlate(f)
  local base = f:CreateTexture(nil, "BACKGROUND")
  base:SetAllPoints()
  base:SetColorTexture(COLOR.dark.r, COLOR.dark.g, COLOR.dark.b, COLOR.dark.a or 1)
  return base
end

-- 1px rim line (horizontal divider by default).
local function hLine(parent, yFromTop)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  t:SetHeight(1)
  return t
end

-- Flat, alpha-driven button. Opacity is the only state: _base (50%) vs active
-- (100%); hover brightens. Colour stays fully opaque.
local function flatButton(parent, w, h, cc, label, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b._base, b._active = 0.5, false
  b.fill = b:CreateTexture(nil, "BACKGROUND")
  b.fill:SetAllPoints(); b.fill:SetColorTexture(cc.r, cc.g, cc.b, 1); b.fill:SetAlpha(b._base)
  b.text = newText(b, FONT.bodyM, size or 12, { r = 1, g = 1, b = 1 }, "CENTER")
  b.text:SetPoint("CENTER")
  b:SetFontString(b.text)
  if label then b.text:SetText(label) end
  local function level() return b._active and 1 or b._base end
  b:SetScript("OnEnter", function(self) if self:IsEnabled() and not self._active then self.fill:SetAlpha(math.min(1, self._base + 0.25)) end end)
  b:SetScript("OnLeave", function(self) self.fill:SetAlpha(level()) end)
  b:SetScript("OnDisable", function(self) self.fill:SetAlpha(0.2); self.text:SetTextColor(0.5, 0.5, 0.5) end)
  b:SetScript("OnEnable", function(self) self.fill:SetAlpha(level()); self.text:SetTextColor(1, 1, 1) end)
  function b:SetActive(a) self._active = a and true or false; self.fill:SetAlpha(level()) end
  function b:SetBase(a) self._base = a; self.fill:SetAlpha(level()) end
  return b
end

-- Sliding on/off toggle — 40x20, white-10% track, square purple knob that snaps
-- flush-left (off) / flush-right (on). Position is the only state signal.
local function makeToggle(parent, get, set)
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(40, 20)
  local track = t:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(1, 1, 1, 0.10)
  local knob = t:CreateTexture(nil, "ARTWORK"); knob:SetSize(20, 20)
  knob:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1)
  function t:refresh() knob:ClearAllPoints(); knob:SetPoint(get() and "RIGHT" or "LEFT", 0, 0) end
  t:SetScript("OnClick", function() set(not get()); t:refresh() end)
  t:refresh()
  return t
end

-- A labelled slider row: label (left) + value (right) over a thin purple-bar
-- thumb on a heroic-20 track (the family look). get/set drive it live; fmt
-- renders the value text. Returns { refresh } for C:Refresh.
local function sliderRow(parent, yTop, labelText, minV, maxV, step, get, set, fmt, sub)
  local lab = newText(parent, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, yTop); lab:SetText(labelText)
  local val = newText(parent, FONT.label, 11, TEXT, "RIGHT"); val:SetPoint("TOPRIGHT", -18, yTop)
  -- Optional muted sub-label under the title (mock detail, e.g. "how far the
  -- highlight spreads") — when present the slider drops below it (taller row).
  local subLab
  local sliderY = yTop - 15
  if sub then
    subLab = newText(parent, FONT.body, 10.5, MUTE, "LEFT")
    subLab:SetPoint("TOPLEFT", 18, yTop - 15); subLab:SetText(sub)
    sliderY = yTop - 30
  end
  -- The Slider FRAME is a tall, full-width hit area (easy to grab); the visible
  -- track is a thin bar centered in it, so the look is unchanged but the grab
  -- target isn't just the 5px thumb (Jason QA 2026-07-19).
  local sl = CreateFrame("Slider", nil, parent)
  sl:SetPoint("TOPLEFT", 18, sliderY); sl:SetPoint("TOPRIGHT", -18, sliderY); sl:SetHeight(16)
  sl:EnableMouse(true)
  sl:SetOrientation("HORIZONTAL"); sl:SetMinMaxValues(minV, maxV); sl:SetValueStep(step); sl:SetObeyStepOnDrag(true)
  local track = sl:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(6)   -- thin visual bar, vertically centered
  track:SetColorTexture(COLOR.heroic.r, COLOR.heroic.g, COLOR.heroic.b, 0.20)
  local thumb = sl:CreateTexture(nil, "ARTWORK"); thumb:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1)
  thumb:SetSize(5, 20); sl:SetThumbTexture(thumb)
  local applying = false
  local function show(v) val:SetText(fmt and fmt(v) or tostring(v)) end
  sl:SetScript("OnValueChanged", function(_, v) if not applying then set(v) end; show(v) end)
  -- Click / drag ANYWHERE on the row seeks the value (map cursor X → min..max,
  -- snap to step) — so you never have to land on the thin thumb.
  local function seek(self)
    local left, w = self:GetLeft(), self:GetWidth()
    if not (left and w and w > 0) then return end
    local frac = (GetCursorPosition() / self:GetEffectiveScale() - left) / w
    frac = math.max(0, math.min(1, frac))
    local v = minV + frac * (maxV - minV)
    if step and step > 0 then v = minV + math.floor((v - minV) / step + 0.5) * step end
    self:SetValue(v)
  end
  -- A drag STARTING ON THE THUMB belongs to the native slider alone: with our
  -- seek also writing every frame, the two quantize the cursor differently
  -- near step boundaries and the value flickers between neighbours (Jason:
  -- "blurs" — worst on wide ranges like Gap's 0–64). Off-thumb, seek owns it.
  sl:SetScript("OnMouseDown", function(self)
    if not self:IsEnabled() then return end
    local left, w = self:GetLeft(), self:GetWidth()
    if left and w and w > 0 then
      local cx = GetCursorPosition() / self:GetEffectiveScale()
      local mn, mx = self:GetMinMaxValues()
      local tx = left + ((self:GetValue() - mn) / math.max(mx - mn, 1e-6)) * w
      if math.abs(cx - tx) <= 8 then return end   -- on the thumb → native drag
    end
    self._seek = true; seek(self)
  end)
  sl:SetScript("OnMouseUp", function(self) self._seek = false end)
  sl:SetScript("OnUpdate", function(self)
    if self._seek then
      if self:IsEnabled() and IsMouseButtonDown("LeftButton") then seek(self) else self._seek = false end
    end
  end)
  local row = {}
  function row:refresh() applying = true; local v = get() or minV; sl:SetValue(v); show(v); applying = false end
  function row:setEnabled(on) sl:SetEnabled(on); sl:SetAlpha(on and 1 or 0.35) end
  function row:SetShown(on) lab:SetShown(on); val:SetShown(on); sl:SetShown(on); if subLab then subLab:SetShown(on) end end
  row:refresh()
  return row
end

-- Color swatch — a solid button that opens the game ColorPickerFrame (modern
-- SetupColorPickerAndShow API, present on this client, with a fallback). Returns
-- { swatch, refresh }.
local function colorSwatch(parent, get, set, withAlpha)
  local sw = CreateFrame("Button", nil, parent); sw:SetSize(28, 20)
  local tex = sw:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints()
  addEdges(sw, COLOR.rim, 1)
  -- The swatch shows the hue at full opacity (its alpha lives on the target, e.g.
  -- the border) so a near-transparent colour stays visible/clickable here.
  local function update() local c = get() or { 1, 1, 1 }; tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1) end
  sw:SetScript("OnClick", function()
    local c = get() or { 1, 1, 1 }
    local function apply()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      if withAlpha then
        local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
        set({ r, g, b, a })
      else
        set({ r, g, b })
      end
      update()
    end
    local info = { hasOpacity = withAlpha or false, opacity = withAlpha and (c[4] or 1) or nil,
      r = c[1], g = c[2], b = c[3], swatchFunc = apply, opacityFunc = apply }
    if ColorPickerFrame.SetupColorPickerAndShow then ColorPickerFrame:SetupColorPickerAndShow(info)
    else ColorPickerFrame.func = apply; ColorPickerFrame:SetColorRGB(c[1], c[2], c[3]); ColorPickerFrame:Show() end
  end)
  update()
  local row = { swatch = sw }
  function row:refresh() update() end
  return row
end

-- A 4-way direction picker: label (left) + Up/Down/Left/Right buttons (right),
-- the current one highlighted (flatButton active = full opacity). get() returns
-- "up"|"down"|"left"|"right"; set(dir) writes it. Reused by the gradient fill and
-- the two-tone border (and, later, the cast-fill direction). Returns { refresh, setEnabled }.
local DIR_CHOICES = { { "up", "Up" }, { "down", "Down" }, { "left", "Left" }, { "right", "Right" } }
local function dirRow(parent, yTop, labelText, get, set)
  local lab = newText(parent, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, yTop); lab:SetText(labelText)
  local btns, prev = {}, nil
  for i = #DIR_CHOICES, 1, -1 do            -- lay out right-to-left so Up is leftmost
    local d = DIR_CHOICES[i]
    local b = flatButton(parent, 40, 22, COLOR.heroic, d[2], 11)
    if prev then b:SetPoint("TOPRIGHT", prev, "TOPLEFT", -4, 0)
    else b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, yTop + 1) end
    b:SetScript("OnClick", function() set(d[1]); for _, e in ipairs(btns) do e.b:SetActive(e.d == get()) end end)
    btns[#btns + 1] = { b = b, d = d[1] }
    prev = b
  end
  local row = {}
  function row:refresh() local cur = get(); for _, e in ipairs(btns) do e.b:SetActive(e.d == cur) end end
  function row:setEnabled(on) for _, e in ipairs(btns) do e.b:SetEnabled(on) end; lab:SetAlpha(on and 1 or 0.35) end
  row:refresh()
  return row
end

-- A thin custom scrollbar for a ScrollFrame (family look; no Blizzard widget) with
-- the ORANGE section-caret thumb. Track + draggable thumb + click/drag-anywhere-on-
-- the-track to jump (the same QOL the sliders got) + wheel over the bar. The thumb
-- auto-sizes to the live scroll range via OnUpdate — which pauses while the parent
-- is hidden, so it costs nothing when the window/flyout is closed. `place(sb)` lets
-- the caller anchor + inset the bar. Returns the bar frame with :Sync() to force an
-- immediate thumb refresh (for opening pre-scrolled). Reuse this for every scrollbar.
local function makeScrollbar(parent, scroll, place)
  local sb = CreateFrame("Frame", nil, parent)
  place(sb); sb:SetWidth(4)
  local track = sb:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(1, 1, 1, 0.06)
  local thumb = CreateFrame("Button", nil, sb); thumb:SetWidth(4); thumb:SetPoint("TOP", 0, 0)
  local thumbTex = thumb:CreateTexture(nil, "ARTWORK"); thumbTex:SetAllPoints()
  local ALPHA = 0.85
  thumbTex:SetColorTexture(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, ALPHA)
  thumb:SetScript("OnEnter", function() thumbTex:SetAlpha(1) end)
  thumb:SetScript("OnLeave", function() thumbTex:SetAlpha(ALPHA) end)

  local function syncThumb()
    local range = scroll:GetVerticalScrollRange()
    local trackH = sb:GetHeight()
    if range <= 0.5 or trackH <= 0 then thumb:Hide(); return end
    thumb:Show()
    local visible = scroll:GetHeight()
    local th = math.max(24, trackH * visible / (visible + range))
    thumb:SetHeight(th)
    local scrolled = math.min(range, math.max(0, scroll:GetVerticalScroll()))
    thumb:ClearAllPoints(); thumb:SetPoint("TOP", sb, "TOP", 0, -(scrolled / range) * (trackH - th))
  end
  -- Map the cursor's Y within the track → scroll fraction (click-to-jump).
  local function seek()
    local range = scroll:GetVerticalScrollRange()
    local top, trackH = sb:GetTop(), sb:GetHeight()
    if range <= 0 or not top or trackH <= 0 then return end
    local _, cy = GetCursorPosition(); cy = cy / sb:GetEffectiveScale()
    scroll:SetVerticalScroll(math.max(0, math.min(1, (top - cy) / trackH)) * range)
  end

  sb:EnableMouse(true); sb:EnableMouseWheel(true)
  sb:SetScript("OnMouseWheel", function(_, delta)
    local range = scroll:GetVerticalScrollRange()
    scroll:SetVerticalScroll(math.max(0, math.min(range, scroll:GetVerticalScroll() - delta * 42)))
  end)
  sb:SetScript("OnMouseDown", function(self) self._seeking = true; seek() end)
  sb:SetScript("OnMouseUp", function(self) self._seeking = false end)
  sb:SetScript("OnUpdate", function(self)
    if self._seeking then
      if IsMouseButtonDown("LeftButton") then seek() else self._seeking = false end
    end
    syncThumb()
  end)

  thumb:SetScript("OnMouseDown", function(self)
    local _, cy = GetCursorPosition()
    self.grabY, self.grabScroll, self.grabbing = cy, scroll:GetVerticalScroll(), true
  end)
  thumb:SetScript("OnMouseUp", function(self) self.grabbing = false end)
  thumb:SetScript("OnUpdate", function(self)
    if not self.grabbing then return end
    if not IsMouseButtonDown("LeftButton") then self.grabbing = false; return end
    local range = scroll:GetVerticalScrollRange()
    local usable = sb:GetHeight() - self:GetHeight()
    if usable <= 0 or range <= 0 then return end
    local _, cy = GetCursorPosition()
    local dy = (self.grabY - cy) / sb:GetEffectiveScale()
    scroll:SetVerticalScroll(math.max(0, math.min(range, self.grabScroll + (dy / usable) * range)))
  end)

  sb.Sync = syncThumb
  return sb
end

-- --------------------------------------------------------------------------
-- Window shell + one-open accordion
-- --------------------------------------------------------------------------
-- Three panels (Jason, session 14): profile + preset selection on the LEFT
-- (always visible — it decides what everything else edits), the control
-- accordion in the MIDDLE (widest), the preview pane on the RIGHT.
local RAIL_W = 200               -- left rail: profile + preset selection
local PREVIEW_W = 210            -- right preview pane width
local PANEL_W, PANEL_H = RAIL_W + 410 + PREVIEW_W, 640   -- middle = 401 body + 9 scrollbar gutter
local TITLE_DIV_Y = -48          -- title bar divider
local FOOTER_H = 52              -- footer strip height (divider sits here above bottom)
local SECTION_HDR_H = 36
-- Padding-compensation for our masks (matches Skin.lua GROW_RATIO / the 240/256
-- edge-padding rule) + the state-ring inset fit; kept local so the preview uses
-- exactly the engine's geometry.
local GROW_RATIO = (256 / 240 - 1) / 2
-- The construction (icon + extension) is centered vertically at this pane-Y so a
-- plate growing above OR below stays put and never rides into the state chips or
-- the caption (max construction ≈ 104 + 0.9·104 ≈ 198px, so ±99 clears both).
local PREVIEW_CENTER_Y = -290    -- pushed down for the 7-row state-chip grid (session 12)

local panel, bodyContainer, contentScroll   -- contentScroll: the middle accordion's scroll frame (for scroll-to-top on open)
local sections = {}
local previewFrame, previewIcon, previewMask, previewGlow, previewRing, previewCD
local previewBorder, previewBorderMask, previewCaption, previewCaptionHead, previewCaptionLinks
local previewCastFillFrame               -- looping cast/channel drain (Cast / Channel chips)
local previewPlateOn = false             -- plate mode live in the preview (set by RefreshPreview)
local previewOuter, previewInner          -- multi-part shaped glow (hand shapes; mirrors the bars)
local previewFlashFrame, previewFlash, previewFlashAnim   -- finish-flash preview
local previewPlates = {}                 -- pooled gradient-plate textures (created lazily)
local previewPlateFresh, previewRetryPending
local previewExtH, previewExtT, previewExtB = 0, 0, 0   -- live extension px (magnitude + top/bottom split)
local previewChips, previewState = {}, "idle"
-- Live pulse for the multi-part preview glow: mirrors the bars' pulse driver so the
-- Pulse-speed slider is visible on the pulsing chips (proc / flash). previewPulsePeak
-- = the trigger opacity to breathe about; the OnUpdate on previewFrame drives alpha.
local previewPulsing, previewPulsePeak, previewPulsePhase = false, 0.9, 0
local PREVIEW_PULSE_DEPTH = 0.5

-- --------------------------------------------------------------------------
-- Font picker — a dropdown whose label is drawn IN the current font; clicking
-- opens a scrollable flyout of every LibSharedMedia font (our bundled ones + all
-- other addons', incl. StoneTweaks), or just the bundled set if LSM is absent.
-- --------------------------------------------------------------------------
local function fontChoices()
  local lsm = GB.GetLSM and GB.GetLSM()
  if lsm and lsm.List then
    local shared, t = lsm:List("font"), {}   -- LSM hands back its own array; copy it
    for i = 1, #shared do t[i] = shared[i] end
    return t
  end
  local t = {}
  for n in pairs(GB.BUNDLED_FONTS or {}) do t[#t + 1] = n end
  table.sort(t)
  return t
end
local function fontPath(name)
  local lsm = GB.GetLSM and GB.GetLSM()
  if lsm and name then local p = lsm:Fetch("font", name, true); if p then return p end end
  return (GB.BUNDLED_FONTS and GB.BUNDLED_FONTS[name]) or GB.FONT.label
end

local fontFlyout
local function fontFlyoutFrame()
  if fontFlyout then return fontFlyout end
  -- Full-screen catcher (child of the panel, so it auto-hides with it) at a
  -- strata ABOVE the DIALOG panel → any click outside the flyout closes it.
  local catcher = CreateFrame("Button", nil, panel)
  catcher:SetFrameStrata("FULLSCREEN"); catcher:SetAllPoints(UIParent); catcher:Hide()
  local fly = CreateFrame("Frame", nil, catcher)
  fly:SetFrameStrata("FULLSCREEN_DIALOG"); fly:SetSize(210, 300)
  skinPlate(fly); addEdges(fly, COLOR.rim, 1)
  local scroll = CreateFrame("ScrollFrame", nil, fly)
  scroll:SetPoint("TOPLEFT", 5, -5); scroll:SetPoint("BOTTOMRIGHT", -13, 5)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll); child:SetSize(190, 10)
  scroll:SetScrollChild(child)

  -- Custom thin scrollbar (shared helper): orange thumb + click-to-jump + drag + wheel.
  local sb = makeScrollbar(fly, scroll, function(b) b:SetPoint("TOPRIGHT", -5, -6); b:SetPoint("BOTTOMRIGHT", -5, 6) end)
  fly.updateThumb = sb.Sync
  -- Content wheel (over the rows) scrolls the list; the bar syncs via its OnUpdate.
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 34)))
  end)

  catcher:SetScript("OnClick", function() catcher:Hide() end)
  fly.catcher, fly.scroll, fly.child, fly.rows = catcher, scroll, child, {}
  fontFlyout = fly
  return fly
end

local function openFontFlyout(anchor, current, onPick)
  local fly = fontFlyoutFrame()
  local names, rows = fontChoices(), fly.rows
  local ROW_H, y = 22, -2
  for i, name in ipairs(names) do
    local row = rows[i]
    if not row then
      row = CreateFrame("Button", nil, fly.child); row:SetHeight(ROW_H)
      row.hl = row:CreateTexture(nil, "BACKGROUND"); row.hl:SetAllPoints()
      row.hl:SetColorTexture(1, 1, 1, 0.07); row.hl:Hide()
      row:SetScript("OnEnter", function(self) self.hl:Show() end)
      row:SetScript("OnLeave", function(self) self.hl:Hide() end)
      row.text = newText(row, FONT.body, 13, TEXT, "LEFT"); row.text:SetWordWrap(false)
      row.text:SetPoint("LEFT", 8, 0); row.text:SetPoint("RIGHT", -8, 0)
      rows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
    row.text:SetText(name)
    if not row.text:SetFont(fontPath(name), 14, "") then row.text:SetFont(GB.FONT.body, 13, "") end
    if name == current then row.text:SetTextColor(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b)
    else row.text:SetTextColor(1, 1, 1) end
    row:SetScript("OnClick", function() fly.catcher:Hide(); onPick(name) end)
    row:Show()
    y = y - ROW_H
  end
  for i = #names + 1, #rows do rows[i]:Hide() end
  fly.child:SetHeight(math.max(10, #names * ROW_H + 4))
  fly:SetHeight(math.min(300, #names * ROW_H + 10))   -- snug for short lists, scroll past ~13
  fly:ClearAllPoints(); fly:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  -- Open scrolled so the CURRENT font sits mid-view (not always the top of a long list).
  local sel = 1
  for i, name in ipairs(names) do if name == current then sel = i; break end end
  local sh = fly:GetHeight() - 10
  local range = math.max(0, fly.child:GetHeight() - sh)
  local target = (sel - 1) * ROW_H - (sh - ROW_H) / 2
  fly.scroll:SetVerticalScroll(math.max(0, math.min(range, target)))
  fly.updateThumb()
  fly.catcher:Show()
end

-- Dropdown button: label drawn in the current font; click opens the flyout.
-- get() → current LSM font name, set(name) writes it. Returns the button (+:refresh).
local function fontDropdown(parent, w, get, set)
  local b = flatButton(parent, w, 22, COLOR.heroic, "", 11); b:SetBase(0.2)
  b.text:SetWordWrap(false)
  function b:refresh()
    local n = get() or "GeneralSans SemiBold"
    self.text:SetText(n)
    if not self.text:SetFont(fontPath(n), 11, "") then self.text:SetFont(FONT.bodyM, 11, "") end
  end
  b:SetScript("OnClick", function() openFontFlyout(b, get(), function(name) set(name); b:refresh() end) end)
  b:refresh()
  return b
end

local function relayout()
  local prevBottom
  local total = 0
  for _, s in ipairs(sections) do
    s.header:ClearAllPoints()
    if prevBottom then
      s.header:SetPoint("TOPLEFT", prevBottom, "BOTTOMLEFT", 0, 0)
      s.header:SetPoint("TOPRIGHT", prevBottom, "BOTTOMRIGHT", 0, 0)
    else
      s.header:SetPoint("TOPLEFT", bodyContainer, "TOPLEFT", 0, 0)
      s.header:SetPoint("TOPRIGHT", bodyContainer, "TOPRIGHT", 0, 0)
    end
    s.caret:SetRotation(s.open and CARET_DOWN or 0)
    total = total + SECTION_HDR_H
    if s.open then
      s.bodyFrame:ClearAllPoints()
      s.bodyFrame:SetPoint("TOPLEFT", s.header, "BOTTOMLEFT", 0, 0)
      s.bodyFrame:SetPoint("TOPRIGHT", s.header, "BOTTOMRIGHT", 0, 0)
      s.bodyFrame:Show()
      prevBottom = s.bodyFrame
      total = total + (s.bodyFrame:GetHeight() or 0)
    else
      s.bodyFrame:Hide()
      prevBottom = s.header
    end
  end
  if bodyContainer then bodyContainer:SetHeight(math.max(total + 4, 10)) end
end

-- Preview caption: the default explainer line, swapped by the Animations section for a
-- one-line description of the state being edited (what triggers it / what it means) —
-- contextual help right in the preview pane. Reset on every section toggle so it never
-- lingers into a section that has no "state" concept.
local PREVIEW_CAPTION_DEFAULT = "Sample of the visible skin. Your clickable hit area stays Edit Mode's size."
-- Section-name hyperlink: |Hgbsec:<title>|h in caret orange (#FF7729); the caption
-- frame's OnHyperlinkClick opens that accordion section. Display = the title in caps.
local function secLink(title)
  return ("|Hgbsec:%s|h|cffFF7729%s|r|h"):format(title, title:upper())
end
-- The "Styled in:" bullet list under a state description (Jason: inline links were
-- hard to follow). Items: a title string, or { title, note } where the note (in the
-- muted body colour) marks which PART of the state that section covers.
local function linkList(items)
  local out = { "Styled in:" }
  for _, it in ipairs(items) do
    local title, note = it, nil
    if type(it) == "table" then title, note = it[1], it[2] end
    out[#out + 1] = "• " .. secLink(title) .. (note and (" — " .. note) or "")
  end
  return table.concat(out, "\n")
end
local LL_GLOW = linkList({ "Glows", "Animations" })
local LL_CDA = linkList({ "Cooldown & availability" })
local LL_CAST = linkList({ "Glows", "Animations", { "Cast & channel", "fill & bursts" } })
-- Each entry = { HEADING, body, links }: the state name (bold Semibold line), what
-- triggers it in-game (plain prose), then the clickable "Styled in:" bullet list.
local STATE_DESC = {
  idle      = { "IDLE", "The button's resting/default look with nothing active.",
                linkList({ "Shape & icon", "Plate", "Decoration layers", "Text" }) },
  proc      = { "PROC", "Triggered when an ability procs (a free or empowered cast becomes ready).", LL_GLOW },
  highlight = { "HIGHLIGHT", "Indicates the current location (if any) on your action bars when hovering over an ability or talent in your spellbook or talent tree.", LL_GLOW },
  assist    = { "ASSIST", "Triggered by Blizzard's Combat Assistant/Assisted Highlight feature to indicate the suggested next rotation ability.", LL_GLOW },
  cast      = { "CAST", "Shows while activating an ability with a cast time.", LL_CAST },
  channel   = { "CHANNEL", "Shows while activating a channeled ability.", LL_CAST },
  hover     = { "HOVER", "Shows while hovering your pointer over an icon in your action bars.", LL_GLOW },
  selected  = { "SELECTED", "Displays when a button is toggled on (a stance, form or aura).", LL_GLOW },
  flash     = { "FLASH", "Appears when auto-attack or auto-shot is active — typically needs the related auto-attack ability to be on the action bar. Not commonly seen.", LL_GLOW },
  cooldown  = { "COOLDOWN", "A swipe animation and finish flash to indicate that an ability is recharging or ready.",
                linkList({ "Cooldown & availability", { "Text", "countdown numbers" } }) },
  unusable  = { "UNUSABLE", "Indicates an ability is unusable due to wrong talent, form/stance, weapon type, silenced, missing resource, etc.", LL_CDA },
  oom       = { "OUT OF MANA", "Indicates you have insufficient mana or other resource/power to cast.", LL_CDA },
  range     = { "OUT OF RANGE", "Shows when the target is too far for the ability to be cast. Tints the icon and recolors the keybind text (if shown).",
                linkList({ { "Cooldown & availability", "enable & style" } }) },
}
-- Set the caption trio: a STATE_DESC entry, or nil → the default explainer only.
local function setCaption(entry)
  if not (previewCaption and previewCaptionHead) then return end
  if type(entry) == "table" then
    previewCaptionHead:SetText(entry[1])
    previewCaption:SetText(entry[2])
    if previewCaptionLinks then previewCaptionLinks:SetText(entry[3] or "") end
  else
    previewCaptionHead:SetText("")
    previewCaption:SetText(PREVIEW_CAPTION_DEFAULT)
    if previewCaptionLinks then previewCaptionLinks:SetText("") end
  end
end

function C:ToggleSection(s)
  setCaption(nil)   -- Animations re-sets it in s.refresh
  local wasOpen = s.open
  for _, x in ipairs(sections) do x.open = false end
  local opening = not wasOpen
  if opening then s.open = true; if s.refresh then s.refresh() end end   -- reflect current state on open
  relayout()
  -- Surface as much of a freshly-opened section as possible: scroll its header
  -- NEAR the top of the pane, leaving just ONE collapsed header visible above it
  -- (Jason) so the opened content fills the view. Deferred a frame so the scroll
  -- range reflects the new bodyContainer height relayout() just set. Only sections
  -- ABOVE the opened one collapse above it — every one is closed now, so the
  -- opened header's offset = (its index - 1) collapsed headers tall.
  if opening and contentScroll then
    local idx
    for i, x in ipairs(sections) do if x == s then idx = i; break end end
    if idx then
      -- Leave one collapsed header visible above → target the header one slot up.
      local target = (idx - 2) * SECTION_HDR_H   -- idx-1 headers above; minus one to keep visible
      C_Timer.After(0, function()
        if not contentScroll then return end
        local range = contentScroll:GetVerticalScrollRange()
        contentScroll:SetVerticalScroll(math.max(0, math.min(range, target)))
      end)
    end
  end
end

-- Open (never close) the section with this title — the caption's section links.
function C:OpenSection(title)
  for _, s in ipairs(sections) do
    if s.title == title then
      if not s.open then self:ToggleSection(s) end
      return
    end
  end
end

-- A section = an accordion header (orange caret + purple Khand title) over a
-- body frame. `build(bodyFrame, section)` fills the body and sets its height.
local function makeSection(title, build)
  local s = { title = title, open = false }

  local header = CreateFrame("Button", nil, bodyContainer)
  header:SetHeight(SECTION_HDR_H)
  local hover = header:CreateTexture(nil, "BACKGROUND"); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.05); hover:Hide()
  header:SetScript("OnEnter", function() hover:Show() end)
  header:SetScript("OnLeave", function() hover:Hide() end)
  local caret = header:CreateTexture(nil, "ARTWORK"); caret:SetTexture(CARET_TEX)
  caret:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b)
  caret:SetSize(9, 9); caret:SetPoint("LEFT", 18, 0)
  local h = newText(header, FONT.head, 16, COLOR.purple, "LEFT")
  h:SetPoint("LEFT", caret, "RIGHT", 11, -1); h:SetText(title:upper())
  local div = header:CreateTexture(nil, "ARTWORK"); div:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  div:SetHeight(1); div:SetPoint("BOTTOMLEFT", 0, 0); div:SetPoint("BOTTOMRIGHT", 0, 0)

  local bodyFrame = CreateFrame("Frame", nil, bodyContainer)
  bodyFrame:SetHeight(10)

  s.header, s.caret, s.bodyFrame = header, caret, bodyFrame
  header:SetScript("OnClick", function() C:ToggleSection(s) end)
  if build then build(bodyFrame, s) end
  sections[#sections + 1] = s
  return s
end

-- Flat text input (ported from GloomsAuras Config.lua — the family pattern):
-- no Blizzard template, faint purple fill + brighter fill on focus, no border.
local function flatEditBox(parent, w, h)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, h); e:SetAutoFocus(false)
  setFont(e, FONT.body, 12); e:SetTextColor(TEXT.r, TEXT.g, TEXT.b)
  e:SetTextInsets(6, 6, 0, 0)
  local bg = e:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
  bg:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.10)
  e:SetScript("OnEditFocusGained", function() bg:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.22) end)
  e:SetScript("OnEditFocusLost",  function() bg:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.10) end)
  return e
end

-- Small skinned text-entry dialog (GloomsAuras pattern — avoids StaticPopup's
-- default chrome). onAccept(name) fires on OK / Enter; ESC closes.
local nameDlgFrame, nameDlgBox, nameDlgTitle, nameDlgOnAccept
local function BuildNameDialog()
  local W, H = 300, 132
  local f = CreateFrame("Frame", "GloomsBarsNameDialog", UIParent)
  f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true)
  skinPlate(f)
  nameDlgTitle = newText(f, FONT.title, 17, COLOR.purple, "CENTER")
  nameDlgTitle:SetPoint("TOP", 0, -14)
  nameDlgBox = flatEditBox(f, W - 48, 24); nameDlgBox:SetPoint("TOP", 0, -50)
  local okB = flatButton(f, 100, 26, COLOR.purple, "OK", 13); okB:SetPoint("BOTTOMLEFT", 26, 16)
  local cancelB = flatButton(f, 100, 26, COLOR.heroic, "Cancel", 13); cancelB:SetPoint("BOTTOMRIGHT", -26, 16)
  local function accept()
    local name = nameDlgBox:GetText()
    local cb = nameDlgOnAccept; nameDlgOnAccept = nil
    f:Hide()
    if cb then cb(name) end
  end
  local function cancel() nameDlgOnAccept = nil; f:Hide() end
  okB:SetScript("OnClick", accept)
  cancelB:SetScript("OnClick", cancel)
  nameDlgBox:SetScript("OnEnterPressed", accept)
  nameDlgBox:SetScript("OnEscapePressed", cancel)
  tinsert(UISpecialFrames, "GloomsBarsNameDialog")
  f:Hide()
  nameDlgFrame = f
end
local function OpenNameDialog(titleText, initial, onAccept)
  if not nameDlgFrame then BuildNameDialog() end
  nameDlgOnAccept = onAccept
  nameDlgTitle:SetText(titleText or "Name")
  nameDlgBox:SetText(initial or ""); nameDlgBox:SetCursorPosition(0)
  nameDlgFrame:Show(); nameDlgFrame:Raise()
  nameDlgBox:SetFocus(); nameDlgBox:HighlightText()
end

-- Family-styled hover tooltip (dark plate, purple title, GeneralSans body —
-- the name-dialog language; GameTooltip's Blizzard chrome clashes with the
-- panel). One shared frame; attachTip(frame, title, body) wires OnEnter/
-- OnLeave via HookScript so it coexists with existing hover scripts.
local tipFrame, tipTitle, tipBody
local function showTip(owner, title, body)
  if not tipFrame then
    tipFrame = CreateFrame("Frame", nil, UIParent)
    tipFrame:SetFrameStrata("TOOLTIP")
    skinPlate(tipFrame)
    tipTitle = newText(tipFrame, FONT.bodyM, 12, COLOR.purple, "LEFT")
    tipTitle:SetPoint("TOPLEFT", 10, -8)
    tipBody = newText(tipFrame, FONT.body, 11, TEXT, "LEFT")
    tipBody:SetPoint("TOPLEFT", 10, -26); tipBody:SetWidth(220); tipBody:SetJustifyH("LEFT")
  end
  tipTitle:SetText(title or "")
  tipBody:SetText(body or "")
  tipFrame:ClearAllPoints()
  tipFrame:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 4)
  tipFrame:SetSize(240, 34 + tipBody:GetStringHeight())
  tipFrame:Show()
end
local function attachTip(f, title, body)
  f:HookScript("OnEnter", function() showTip(f, title, body) end)
  f:HookScript("OnLeave", function() if tipFrame then tipFrame:Hide() end end)
end

-- ---------------------------------------------------------------------------
-- Quick keybind launcher (phase L4) — opens Blizzard's quick-bind flow (their
-- BINDING logic untouched), reskinned to the family language on first open.
-- Shared by the Bar-layout section button and the footer button. Every styled
-- region is guarded: if a patch renames a piece it keeps its stock look.
local qkFromUs = false
local function flatifyBlizzButton(b)
  if not b or b.gbStyled then return end
  b.gbStyled = true
  for _, k in ipairs({ "Left", "Right", "Middle", "Center" }) do
    local tex = b[k]
    if tex and tex.SetAlpha then tex:SetAlpha(0) end
  end
  for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
    local tex = b[get] and b[get](b)
    if tex then tex:SetAlpha(0) end
  end
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(COLOR.heroic.r, COLOR.heroic.g, COLOR.heroic.b, 1)
  fill:SetAlpha(0.5)
  b:HookScript("OnEnter", function() fill:SetAlpha(0.8) end)
  b:HookScript("OnLeave", function() fill:SetAlpha(0.5) end)
  local fs = b.GetFontString and b:GetFontString()
  if fs then setFont(fs, FONT.bodyM, 12); fs:SetTextColor(1, 1, 1) end
end
local function styleQuickKeybind()
  local f = QuickKeybindFrame
  if not f or f.gbStyled then return end
  f.gbStyled = true
  if f.BG then f.BG:SetAlpha(0) end         -- their dialog border + fill
  skinPlate(f)
  addEdges(f, COLOR.rim, 1)
  if f.Header then
    f.Header:SetAlpha(0)                    -- their gold header art (text included)
    local title = f:CreateFontString(nil, "OVERLAY")
    setFont(title, FONT.title, 18)
    title:SetTextColor(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b)
    title:SetPoint("TOP", 0, -14)
    title:SetText((f.Header.Text and f.Header.Text:GetText()) or "Quick Keybind Mode")
  end
  for _, key in ipairs({ "InstructionText", "CancelDescriptionText", "OutputText" }) do
    local fs = f[key]
    if fs and fs.SetFont then setFont(fs, FONT.body, 13) end   -- faces only; OutputText's colour is Blizzard's live status
  end
  flatifyBlizzButton(f.OkayButton)
  flatifyBlizzButton(f.CancelButton)
  flatifyBlizzButton(f.DefaultsButton)
  -- Character-specific checkbox: GloomsAuras's flatCheck look (20px box, 10%
  -- white fill, orange checkmark — same asset, copied to GB media), applied
  -- over Blizzard's CheckButton so its bindings mechanics stay theirs.
  local cb = f.UseCharacterBindingsButton
  if cb then
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
      local tex = cb[get] and cb[get](cb)
      if tex then tex:SetAlpha(0) end
    end
    local box = cb:CreateTexture(nil, "ARTWORK")
    box:SetSize(20, 20); box:SetPoint("CENTER")
    box:SetColorTexture(1, 1, 1, 0.10)
    local mark = cb:CreateTexture(nil, "OVERLAY")
    mark:SetSize(20, 20); mark:SetPoint("CENTER")
    mark:SetTexture(GB.MEDIA .. "ui\\checkmark.png")
    mark:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, 1)
    local function sync() mark:SetShown(cb:GetChecked()) end
    cb:HookScript("OnClick", sync)
    cb:HookScript("OnShow", sync)
    sync()
    local cbText = cb.Text or cb.text
    if cbText and cbText.SetFont then setFont(cbText, FONT.body, 12) end
  end
end
local function openQuickKeybind()
  if InCombatLockdown() then GB.msg("quick keybind needs you out of combat."); return end
  if GB.Layout and GB.Layout.MoveModeOn and GB.Layout:MoveModeOn() then GB.Layout:SetMoveMode(false) end
  if panel then panel:Hide() end
  local f = QuickKeybindFrame
  if not f then GB.msg("Quick keybind isn't available in this client."); return end
  if not f.gbHideHooked then
    f.gbHideHooked = true
    f:HookScript("OnHide", function()
      if not qkFromUs then return end
      qkFromUs = false
      -- Blizzard's OnHide reopens the SETTINGS panel (their flow assumes you
      -- came from it — Jason: "make that not happen"): close it again in the
      -- same frame, before it ever renders. Launches from Settings itself
      -- (qkFromUs false) keep Blizzard's return-trip behaviour.
      if SettingsPanel then
        if SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true)
        else HideUIPanel(SettingsPanel) end
      end
    end)
  end
  qkFromUs = true
  f:Show()
  styleQuickKeybind()
end

-- Placeholder body for sections not yet wired (increment 1).
local function stubBody(bf)
  local t = newText(bf, FONT.body, 11, MUTE, "LEFT")
  t:SetPoint("TOPLEFT", 18, -12)
  t:SetText("Controls for this section land in the next pass.")
  bf:SetHeight(38)
end

-- Shape & icon — the 21 preset silhouettes as a grouped thumbnail grid, plus a
-- uniform size scale, icon zoom, and crop-to-fill. The shaped-glow pivot (session
-- 8, docs/SHAPE-CATALOG.md) retired free width/height + the SDF corner presets: the
-- icon is ONE baked silhouette so it can't warp, and Size scales every icon
-- together (aspect fixed by the shape). Picking a thumbnail calls Skin:SetHandShape
-- (persists + applies live); Size → Skin:SetSizeScale. Each thumbnail draws the
-- shape's own <key>-base.png (white on transparent), tinted grey / purple-selected.
local function buildShapeSection(bf, s)
  local CELL, GAP, COLS, ROWGAP = 46, 6, 7, 8
  local thumbs = {}   -- shape key → thumbnail button (for the selection refresh)

  -- One shape thumbnail: the silhouette's own -base.png (white on transparent),
  -- fit to the shape's aspect inside the cell, tinted grey (purple when selected,
  -- brightening on hover). Clicking sets the persistent hand shape live.
  local function makeThumb(key)
    local info = GB.HAND_SHAPES[key] or GB.HAND_SHAPES.circle
    local b = CreateFrame("Button", nil, bf)
    b:SetSize(CELL, CELL)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
    -- silhouette fit-to-aspect inside a padded box (portrait taller, landscape wider)
    local box = CELL - 12
    local w, h = box, box
    if info.orient == "portrait" then w = box / info.aspect
    elseif info.orient == "landscape" then h = box / info.aspect end
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetSize(w, h); tex:SetPoint("CENTER"); tex:SetTexture(GB:HandAsset(key, "base"))
    -- purple selection edges (hidden until active)
    local edges = {}
    local function edge(p1, p2, vertical)
      local e = b:CreateTexture(nil, "OVERLAY")
      e:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1)
      e:SetPoint(p1); e:SetPoint(p2)
      if vertical then e:SetWidth(2) else e:SetHeight(2) end
      e:Hide(); edges[#edges + 1] = e
    end
    edge("TOPLEFT", "TOPRIGHT"); edge("BOTTOMLEFT", "BOTTOMRIGHT")
    edge("TOPLEFT", "BOTTOMLEFT", true); edge("TOPRIGHT", "BOTTOMRIGHT", true)
    function b:SetSelected(on)
      self._sel = on and true or false
      tex:SetVertexColor(on and COLOR.purple.r or 0.62, on and COLOR.purple.g or 0.64, on and COLOR.purple.b or 0.70)
      bg:SetColorTexture(1, 1, 1, on and 0.10 or 0.04)
      for _, e in ipairs(edges) do e:SetShown(on) end
    end
    b:SetScript("OnEnter", function(self)
      if not self._sel then tex:SetVertexColor(0.88, 0.90, 0.95) end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(info.label, 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
      if not self._sel then tex:SetVertexColor(0.62, 0.64, 0.70) end
      GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
      if GB.Skin then GB.Skin:SetHandShape(key) else GB.db.handShape = key end
      s.refresh(); C:RefreshPreview()
    end)
    b:SetSelected(false)
    return b
  end

  -- Lay the groups out top-to-bottom: a muted group title, then a wrapping grid.
  -- yCursor tracks the running vertical position (0 at the section top, negative down).
  local yCursor = -12
  local function groupTitle(text)
    local t = newText(bf, FONT.label, 10, MUTE, "LEFT")
    t:SetPoint("TOPLEFT", 18, yCursor); t:SetText(text:upper())
    yCursor = yCursor - 16
  end
  local function grid(keys)
    for i, key in ipairs(keys) do
      local col, rowIdx = (i - 1) % COLS, math.floor((i - 1) / COLS)
      local th = makeThumb(key); thumbs[key] = th
      th:SetPoint("TOPLEFT", 18 + col * (CELL + GAP), yCursor - rowIdx * (CELL + ROWGAP))
    end
    local rows = math.max(1, math.ceil(#keys / COLS))
    yCursor = yCursor - rows * CELL - (rows - 1) * ROWGAP - 14
  end
  for _, g in ipairs(GB.HAND_GROUPS) do groupTitle(g.title); grid(g.keys) end

  -- Uniform size scale (× the Edit-Mode button size) — replaces free width/height.
  local sizeRow = sliderRow(bf, yCursor, "Size", 0.5, 2.0, 0.05,
    function() return GB.db and GB.db.sizeScale end,
    function(v) if GB.Skin then GB.Skin:SetSizeScale(v) else GB.db.sizeScale = v end; C:RefreshPreview() end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  yCursor = yCursor - 34

  -- Icon zoom (live SetTexCoord) + crop-to-fill (kept from the old section).
  local zoomRow = sliderRow(bf, yCursor, "Icon zoom", 0, 0.30, 0.01,
    function() return GB.db and GB.db.zoom end,
    function(v) if GB.Skin then GB.Skin:SetZoom(v) end; C:PreviewZoom(v) end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  yCursor = yCursor - 34

  local fillLbl = newText(bf, FONT.body, 12, TEXT, "LEFT"); fillLbl:SetPoint("TOPLEFT", 18, yCursor); fillLbl:SetText("Crop to fill")
  local fillTog = makeToggle(bf,
    function() return not (GB.db and GB.db.iconFill == "stretch") end,
    function(v)
      if GB.Skin then GB.Skin:SetIconFill(v and "fill" or "stretch") else GB.db.iconFill = v and "fill" or "stretch" end
      C:RefreshPreview()
    end)
  fillTog:SetPoint("TOPRIGHT", -18, yCursor + 2)
  yCursor = yCursor - 26

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, yCursor); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Pick a silhouette; Size scales every icon together. The clickable hit area stays Edit Mode's.")
  yCursor = yCursor - 40

  bf:SetHeight(-yCursor + 8)

  s.refresh = function()
    local active = GB.db and GB.db.handShape
    for key, th in pairs(thumbs) do th:SetSelected(key == active) end
    sizeRow:refresh(); zoomRow:refresh(); fillTog:refresh()
    relayout()
  end
end

-- The active style's first gradient layer (the "plate" fill), creating one if
-- the style has none. Edits go straight into GB.db.styleData (a saved document).
local function gradLayer()
  local st = GB.db and GB.db.styleData
  if not (st and st.layers) then return nil end
  for _, l in ipairs(st.layers) do if l.kind == "gradient" then return l end end
  return nil
end
local function ensureGradLayer()
  local st = GB.db and GB.db.styleData; if not st then return nil end
  st.layers = st.layers or {}
  local l = gradLayer()
  if not l then
    l = { kind = "gradient", zone = "extension", bleedPct = 0.5, color = { 1, 0.47, 0.16 }, fromAlpha = 1, toAlpha = 0 }
    st.layers[#st.layers + 1] = l
  end
  return l
end

-- The border decoration (a colored frame around ANY shape). Stored as its own
-- styleData field; the engine draws a shape-copy behind the icon, oversized by
-- `thickness`. Absent = no border.
local function borderData() local st = GB.db and GB.db.styleData; return st and st.border end
local function ensureBorder()
  local st = GB.db and GB.db.styleData; if not st then return nil end
  st.border = st.border or { enabled = true, color = { 0.58, 0.42, 1 }, thickness = 3, alpha = 1 }
  return st.border
end

-- The "plate" look for 2:1 portrait shapes: a square icon in one half, a solid-colour
-- plate in the other, the colour fading up over the icon. styleData.plate; absent = off.
local function plateData() local st = GB.db and GB.db.styleData; return st and st.plate end
local function ensurePlate()
  local st = GB.db and GB.db.styleData; if not st then return nil end
  st.plate = st.plate or { enabled = false, iconSide = "top", color = { 0.1, 0.1, 0.13 }, fadeStart = 0.5 }
  return st.plate
end
-- Plate only makes sense on a 2:1 portrait shape (the halves are then two squares).
local function plateShapeOK()
  local hk = GB.db and GB.db.handShape
  local info = hk and GB.HAND_SHAPES and GB.HAND_SHAPES[hk]
  return (info and info.orient == "portrait" and info.aspect == 2) or false
end

-- The keybind (HotKey) override. Present = the engine restyles/repositions the
-- keybind text (ApplyHotkeyOverride reads styleData.hotkey: zone/offset/size/
-- font/flags/color); absent = Blizzard's default (top-right). `font` is a GB.FONT
-- key. Default = the reference look (bold white centered in the extension).
local function hotkeyData() local st = GB.db and GB.db.styleData; return st and st.hotkey end
local function ensureHotkey()
  local st = GB.db and GB.db.styleData; if not st then return nil end
  st.hotkey = st.hotkey or { enabled = true, zone = "extension", offsetX = 0, offsetY = 0, size = 13, font = "GeneralSans SemiBold", flags = "OUTLINE", color = { 1, 1, 1 } }
  return st.hotkey
end
-- Custom-keybind ON = the table exists AND enabled ~= false. Toggling off keeps
-- the styling table (enabled=false) so the user's font/size/color/position all
-- persist and come back when re-enabled. Legacy tables (no `enabled`) read as on.
local function hotkeyOn() local h = hotkeyData(); return h ~= nil and h.enabled ~= false end

-- Charge/stack count override (styleData.count) — same pattern as the keybind.
-- Engine: Skin's ApplyCountOverride. Absent/off = Blizzard's default look.
local function countData() local st = GB.db and GB.db.styleData; return st and st.count end
local function ensureCount()
  local st = GB.db and GB.db.styleData; if not st then return nil end
  st.count = st.count or { enabled = true, zone = "corner", offsetX = 0, offsetY = 0, size = 14, font = "GeneralSans SemiBold", flags = "OUTLINE", color = { 1, 1, 1 } }
  return st.count
end
local function countOn() local c = countData(); return c ~= nil and c.enabled ~= false end

-- Cooldown countdown text (styleData.cdtext) — show/hide + restyle/reposition the
-- number Blizzard's Cooldown widget draws. ABSENT = untouched (the game's own
-- countdownForCooldowns CVar stays in charge). Engine: Skin.styleCooldownText.
local function cdtextData() local st = GB.db and GB.db.styleData; return st and st.cdtext end
local function ensureCdtext()
  local st = GB.db and GB.db.styleData; if not st then return nil end
  st.cdtext = st.cdtext or { enabled = true, size = 16, font = "GeneralSans SemiBold", flags = "OUTLINE", color = { 1, 1, 1 }, offsetX = 0, offsetY = 0 }
  return st.cdtext
end
local function cdtextOn() local c = cdtextData(); return c ~= nil and c.enabled ~= false end

-- Macro-name override (styleData.name) — same styling pattern as the count, but
-- THREE modes (default = Blizzard's stock label / custom = styled / hidden =
-- no label). Engine: Skin's ApplyNameOverride. Absent = default. Legacy tables
-- (no mode) read the old enabled flag: true = custom, false = default.
local function nameData() local st = GB.db and GB.db.styleData; return st and st.name end
local function ensureName()
  local st = GB.db and GB.db.styleData; if not st then return nil end
  st.name = st.name or { mode = "custom", zone = "bottom", offsetX = 0, offsetY = 0, size = 10, font = "GeneralSans Medium", flags = "OUTLINE", color = { 1, 1, 1 } }
  return st.name
end
local function nameMode()
  local c = nameData()
  if not c then return "default" end
  return c.mode or (c.enabled ~= false and "custom" or "default")
end

-- Plate — the 2:1-shape "plate" look: a SQUARE icon fills one half, a solid-colour plate
-- fills the other, and that colour fades up over the icon. Only meaningful on a 2:1
-- portrait shape (its halves are two squares); greyed with a hint on any other shape.
local function buildPlateSection(bf, s)
  local function on() local p = plateData(); return p and p.enabled and true or false end
  local function curSide() return (plateData() and plateData().iconSide) or "top" end

  local enLbl = newText(bf, FONT.body, 12, TEXT, "LEFT"); enLbl:SetPoint("TOPLEFT", 18, -14); enLbl:SetText("Plate")
  local enTog = makeToggle(bf, on, function(v)
    local p = ensurePlate(); if p then p.enabled = v and true or false end
    if GB.Skin then GB.Skin:RefreshPlate() end
    C:RefreshPreview(); s.refresh()
  end)
  enTog:SetPoint("TOPRIGHT", -18, -12)

  -- Icon side: which half the square icon fills (the plate fills the other).
  local sideLbl = newText(bf, FONT.body, 12, TEXT, "LEFT"); sideLbl:SetPoint("TOPLEFT", 18, -46); sideLbl:SetText("Icon side")
  local sideBtns, prev = {}, nil
  local function setSide(v)
    local p = ensurePlate(); if p then p.iconSide = v end
    for _, e in ipairs(sideBtns) do e.b:SetActive(e.v == v) end
    if GB.Skin then GB.Skin:RefreshPlate() end
    C:RefreshPreview()
  end
  for _, opt in ipairs({ { "bottom", "Bottom" }, { "top", "Top" } }) do   -- reverse → Top ends up leftmost
    local b = flatButton(bf, 52, 20, COLOR.heroic, opt[2], 11)
    if prev then b:SetPoint("TOPRIGHT", prev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -45) end
    b:SetScript("OnClick", function() setSide(opt[1]) end)
    sideBtns[#sideBtns + 1] = { b = b, v = opt[1] }; prev = b
  end

  local colLbl = newText(bf, FONT.body, 12, TEXT, "LEFT"); colLbl:SetPoint("TOPLEFT", 18, -78); colLbl:SetText("Plate color")
  local cs = colorSwatch(bf, function() local p = plateData(); return p and p.color end,
    function(c) local p = ensurePlate(); if p then p.color = c end; local l = gradLayer(); if l then l.color = c end; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)
  cs.swatch:SetPoint("TOPRIGHT", -18, -77)

  -- Fade start: how far the plate colour bleeds up over the icon. Kept in sync with the
  -- Decoration Layers gradient fade (bleedPct) when a gradient layer exists.
  local fadeRow = sliderRow(bf, -104, "Fade start", 0, 1, 0.05,
    function() local p = plateData(); return (p and p.fadeStart) or 0.5 end,
    function(v)
      local p = ensurePlate(); if p then p.fadeStart = v end
      local l = gradLayer(); if l then l.bleedPct = v end
      if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview()
    end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)

  -- Dim on cooldown: the plate colour darkens while the action's REAL (non-GCD)
  -- cooldown runs — the icon half already darkens under the sweep; this carries
  -- the "on cooldown" read across the plate half. Engine: Skin's dim proxy.
  local dimLbl = newText(bf, FONT.body, 12, TEXT, "LEFT"); dimLbl:SetPoint("TOPLEFT", 18, -152); dimLbl:SetText("Dim on cooldown")
  local dimTog = makeToggle(bf,
    function() local p = plateData(); return p and p.dimCD and true or false end,
    function(v)
      local p = ensurePlate(); if p then p.dimCD = v and true or false end
      if GB.Skin and GB.Skin.RefreshPlateDim then GB.Skin:RefreshPlateDim() end
    end)
  dimTog:SetPoint("TOPRIGHT", -18, -150)

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -184); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  bf:SetHeight(214)
  s.refresh = function()
    local ok = plateShapeOK()
    enTog:EnableMouse(ok); enTog:SetAlpha(ok and 1 or 0.35); enTog:refresh()
    local live = ok and on()
    sideLbl:SetAlpha(live and 1 or 0.4)
    for _, e in ipairs(sideBtns) do e.b:SetActive(e.v == curSide()); e.b:SetEnabled(live) end
    colLbl:SetAlpha(live and 1 or 0.4)
    cs.swatch:SetEnabled(live); cs.swatch:SetAlpha(live and 1 or 0.4); cs:refresh()
    fadeRow:setEnabled(live); fadeRow:refresh()
    dimLbl:SetAlpha(live and 1 or 0.4)
    dimTog:EnableMouse(live); dimTog:SetAlpha(live and 1 or 0.35); dimTog:refresh()
    hint:SetText(ok
      and "Square icon in one half, solid plate + colour-fade in the other. Side picks which half."
      or "Plate needs a 2:1 shape — pick Pill 2:1, Tall square 2:1, or a Tall rounded ·2:1 in Shape & icon.")
  end
end

-- Decoration — the gradient plate that fills the extension and fades up into the
-- icon. One layer for now (color + fade + on/off); multiple layers come later.
local function buildDecorSection(bf, s)
  local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, -14); lab:SetText("Gradient fill")
  local en = makeToggle(bf,
    function() local l = gradLayer(); return l and l.enabled ~= false end,
    function(v) local l = ensureGradLayer(); l.enabled = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)
  en:SetPoint("TOPRIGHT", -18, -12)

  local clab = newText(bf, FONT.body, 12, TEXT, "LEFT"); clab:SetPoint("TOPLEFT", 18, -46); clab:SetText("Color")
  local cs = colorSwatch(bf,
    function() local l = gradLayer(); return l and l.color end,
    function(c) local l = ensureGradLayer(); l.color = c; if plateData() then plateData().color = c end; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)
  cs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local bleedRow = sliderRow(bf, -78, "Fade start", 0, 1, 0.05,
    function() local l = gradLayer(); return (l and l.bleedPct) or 0.5 end,
    function(v) local l = ensureGradLayer(); l.bleedPct = v; if plateData() then plateData().fadeStart = v end; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)

  -- Direction — which edge the fill is solid at and which way it fades. Works on
  -- every shape (incl. hexagon); "Fade start" sets how far the fade reaches.
  local dirR = dirRow(bf, -128, "Direction",
    function() local l = gradLayer(); return (l and l.dir) or "up" end,
    function(d) local l = ensureGradLayer(); l.dir = d; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)

  -- Border — a colored frame around ANY shape (a shape-copy behind the icon,
  -- peeking out by the thickness). On/off + color(s) + thickness + opacity.
  local blab = newText(bf, FONT.head, 13, COLOR.purple, "LEFT"); blab:SetPoint("TOPLEFT", 18, -168); blab:SetText("BORDER")
  local ben = makeToggle(bf,
    function() local b = borderData(); return b and b.enabled end,
    function(v) local b = ensureBorder(); b.enabled = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)
  ben:SetPoint("TOPRIGHT", -18, -166)

  local bclab = newText(bf, FONT.body, 12, TEXT, "LEFT"); bclab:SetPoint("TOPLEFT", 18, -198); bclab:SetText("Color")
  local bcs = colorSwatch(bf,
    function() local b = borderData(); return b and b.color end,
    function(c) local b = ensureBorder(); b.color = c; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end, true)
  bcs.swatch:SetPoint("TOPRIGHT", -18, -196)

  -- Two-tone: a second colour turns the border into a gradient (only the rim
  -- shows → a colour transition around the frame). Off clears color2.
  local twoLab = newText(bf, FONT.body, 12, TEXT, "LEFT"); twoLab:SetPoint("TOPLEFT", 18, -228); twoLab:SetText("Two-tone")
  local twoTog = makeToggle(bf,
    function() local b = borderData(); return b and b.color2 ~= nil end,
    function(v)
      local b = ensureBorder()
      b.color2 = v and (b.color2 or { 1, 1, 1 }) or nil
      if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview(); s.refresh()
    end)
  twoTog:SetPoint("TOPRIGHT", -18, -226)

  local bc2lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); bc2lab:SetPoint("TOPLEFT", 18, -258); bc2lab:SetText("Color 2")
  local bcs2 = colorSwatch(bf,
    function() local b = borderData(); return b and b.color2 end,
    function(c) local b = ensureBorder(); b.color2 = c; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end, true)
  bcs2.swatch:SetPoint("TOPRIGHT", -18, -256)

  local bdirR = dirRow(bf, -288, "Blend dir",
    function() local b = borderData(); return (b and b.gradDir) or "up" end,
    function(d) local b = ensureBorder(); b.gradDir = d; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)

  local thickRow = sliderRow(bf, -328, "Thickness", 1, 12, 1,
    function() local b = borderData(); return (b and b.thickness) or 3 end,
    function(v) local b = ensureBorder(); b.thickness = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end,
    function(v) return v .. "px" end)

  local bopRow = sliderRow(bf, -372, "Opacity", 0, 1, 0.05,
    function() local b = borderData(); return (b and b.alpha) or 1 end,
    function(v) local b = ensureBorder(); b.alpha = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -416); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Direction sets the solid edge; Fade start its reach. Two-tone makes the border a gradient.")
  bf:SetHeight(440)
  s.refresh = function()
    en:refresh(); cs:refresh(); bleedRow:refresh(); dirR:refresh()
    ben:refresh(); bcs:refresh(); twoTog:refresh(); bcs2:refresh(); bdirR:refresh(); thickRow:refresh(); bopRow:refresh()
    -- Grey Color 2 + Blend dir unless two-tone is on.
    local two = (function() local b = borderData(); return b and b.color2 ~= nil end)()
    bc2lab:SetAlpha(two and 1 or 0.35)
    bcs2.swatch:EnableMouse(two); bcs2.swatch:SetAlpha(two and 1 or 0.35)
    bdirR:setEnabled(two)
  end
end

-- Text — ONE home for every text element (Jason, session 12: keybind / charge
-- count / countdown styling were scattered over three sections). A chip row picks
-- the element (the Animations-section pattern); each element's block shows below,
-- and the section resizes to the selected block (bf:SetHeight + relayout).
-- Engines: ApplyHotkeyOverride (styleData.hotkey, UpdateHotkeys re-assert),
-- ApplyCountOverride (styleData.count), styleCooldownText (styleData.cdtext).
-- OUTLINE & SHADOW group (session 14) — one identical block for every Text
-- element. Outline = WoW's font flag (None / Outline / Thick); Shadow = the
-- separate FontString shadow property the engine now owns (toggle + colour with
-- opacity + X/Y offset). `defOn` mirrors the engine's legacy default when the
-- element has no saved shadow yet (Blizzard bakes one on name/countdown, not
-- keybind/count). `onFn` = whether the element's styling is active (greying).
-- Occupies 216px from `y`; returns { refresh(on) }.
local function textStyleGroup(parent, y, dataFn, ensureFn, applyFn, defOn, onFn)
  local g = {}
  local hdr = newText(parent, FONT.head, 13, COLOR.purple, "LEFT"); hdr:SetPoint("TOPLEFT", 18, y); hdr:SetText("OUTLINE & SHADOW")

  local olab = newText(parent, FONT.body, 12, TEXT, "LEFT"); olab:SetPoint("TOPLEFT", 18, y - 30); olab:SetText("Outline")
  local obtns, oPrev = {}, nil
  for i = 3, 1, -1 do   -- reverse → None ends up leftmost
    local oc = ({ { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" } })[i]
    local b = flatButton(parent, 60, 22, COLOR.heroic, oc[2], 11)
    if oPrev then b:SetPoint("TOPRIGHT", oPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, y - 28) end
    b:SetScript("OnClick", function()
      local c = ensureFn(); if not c then return end
      c.flags = oc[1]
      for _, e in ipairs(obtns) do e.b:SetActive(e.f == c.flags) end
      applyFn()
    end)
    obtns[#obtns + 1] = { b = b, f = oc[1] }; oPrev = b
  end

  local function shadow() local c = dataFn(); return c and c.shadow end
  local function shadowOn()
    local sh = shadow()
    if sh == nil then return defOn end   -- legacy: mirror the engine's fallback
    return sh.enabled and true or false
  end
  local function ensureShadow()
    local c = ensureFn(); if not c then return nil end
    c.shadow = c.shadow or { enabled = defOn, color = { 0, 0, 0, 1 }, x = 1, y = -1 }
    return c.shadow
  end

  local slab = newText(parent, FONT.body, 12, TEXT, "LEFT"); slab:SetPoint("TOPLEFT", 18, y - 62); slab:SetText("Shadow")
  local sTog = makeToggle(parent, shadowOn,
    function(v)
      local sh = ensureShadow(); if sh then sh.enabled = v and true or false end
      applyFn(); g.refresh(onFn())
    end)
  sTog:SetPoint("TOPRIGHT", -18, y - 60)

  local sclab = newText(parent, FONT.body, 12, TEXT, "LEFT"); sclab:SetPoint("TOPLEFT", 18, y - 94); sclab:SetText("Shadow color")
  local scs = colorSwatch(parent,
    function() local sh = shadow(); return sh and sh.color end,
    function(col) local sh = ensureShadow(); if sh then sh.color = col end; applyFn() end,
    true)   -- opacity-enabled — a soft shadow is half the point
  scs.swatch:SetPoint("TOPRIGHT", -18, y - 92)

  local sxRow = sliderRow(parent, y - 126, "Shadow offset X", -8, 8, 1,
    function() local sh = shadow(); return (sh and sh.x) or 1 end,
    function(v) local sh = ensureShadow(); if sh then sh.x = v end; applyFn() end,
    function(v) return v .. "px" end)
  local syRow = sliderRow(parent, y - 170, "Shadow offset Y", -8, 8, 1,
    function() local sh = shadow(); return (sh and sh.y) or -1 end,
    function(v) local sh = ensureShadow(); if sh then sh.y = v end; applyFn() end,
    function(v) return v .. "px" end)

  g.refresh = function(on)
    local c = dataFn()
    local shOn = on and shadowOn()
    for _, e in ipairs(obtns) do e.b:SetActive(on and ((c and c.flags) or "OUTLINE") == e.f); e.b:SetEnabled(on) end
    sTog:refresh(); sTog:SetEnabled(on); sTog:SetAlpha(on and 1 or 0.35)
    scs:refresh(); scs.swatch:EnableMouse(shOn); scs.swatch:SetAlpha(shOn and 1 or 0.35)
    sxRow:refresh(); syRow:refresh()
    sxRow:setEnabled(shOn); syRow:setEnabled(shOn)
  end
  return g
end

local function buildTextSection(bf, s)
  local function reapply() if GB.Skin then GB.Skin:ReapplyDecor() end end
  local function reCD() if GB.Skin and GB.Skin.RefreshCooldownText then GB.Skin:RefreshCooldownText() end end

  local TEXT_TABS = { { "keybind", "Keybind" }, { "count", "Charge count" }, { "cdtext", "Countdown" }, { "name", "Name" } }
  local tab = "keybind"
  local BLOCK_TOP = -44                   -- blocks hang below the chip row
  local blocks, chips = {}, {}
  local selectTab                         -- fwd-declared (chip handlers + s.refresh)

  local function newBlock(key, height)
    local f = CreateFrame("Frame", nil, bf)
    f:SetPoint("TOPLEFT", 0, BLOCK_TOP); f:SetPoint("TOPRIGHT", 0, BLOCK_TOP)
    f:SetHeight(height); f.height = height
    f:Hide()
    blocks[key] = f
    return f
  end

  -- ------------------------------------------------------------------ KEYBIND
  local kb = newBlock("keybind", 620)
  local lab = newText(kb, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, -14); lab:SetText("Custom keybind")
  local en = makeToggle(kb,
    hotkeyOn,
    function(v) local h = ensureHotkey(); if h then h.enabled = v and true or false end; reapply(); if GB.Skin then GB.Skin:RefreshHotkeyText() end; kb.refresh() end)
  en:SetPoint("TOPRIGHT", -18, -12)

  local clab = newText(kb, FONT.body, 12, TEXT, "LEFT"); clab:SetPoint("TOPLEFT", 18, -46); clab:SetText("Color")
  local cs = colorSwatch(kb,
    function() local h = hotkeyData(); return h and h.color end,
    function(c) local h = ensureHotkey(); h.color = c; reapply() end)
  cs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local sizeRow = sliderRow(kb, -78, "Size", 6, 28, 1,
    function() local h = hotkeyData(); return (h and h.size) or 13 end,
    function(v) local h = ensureHotkey(); h.size = v; reapply() end,
    function(v) return v .. "px" end)

  -- Font — a dropdown of every LibSharedMedia font (bundled + other addons').
  local flab = newText(kb, FONT.body, 12, TEXT, "LEFT"); flab:SetPoint("TOPLEFT", 18, -122); flab:SetText("Font")
  local fontBtn = fontDropdown(kb, 150,
    function() local h = hotkeyData(); return h and h.font end,
    function(name) local h = ensureHotkey(); h.font = name; reapply() end)
  fontBtn:SetPoint("TOPRIGHT", -18, -120)

  -- POSITION — zone (over the icon vs. in the extension plate) + nudge offsets.
  -- POSITION sits ABOVE Outline & shadow (Jason: shadow offset was above text
  -- position, "bonkers"); the OUTLINE & SHADOW group now follows it below.
  local phdr = newText(kb, FONT.head, 13, COLOR.purple, "LEFT"); phdr:SetPoint("TOPLEFT", 18, -160); phdr:SetText("POSITION")
  local zlab = newText(kb, FONT.body, 12, TEXT, "LEFT"); zlab:SetPoint("TOPLEFT", 18, -190); zlab:SetText("Zone")
  local zoneBtns, zPrev = {}, nil
  for i = 2, 1, -1 do
    local zc = ({ { "center", "Center" }, { "extension", "Extension" } })[i]
    local b = flatButton(kb, 80, 22, COLOR.heroic, zc[2], 11)
    if zPrev then b:SetPoint("TOPRIGHT", zPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -188) end
    b:SetScript("OnClick", function()
      local h = ensureHotkey(); h.zone = zc[1]
      for _, e in ipairs(zoneBtns) do e.b:SetActive(e.z == h.zone) end; reapply()
    end)
    zoneBtns[#zoneBtns + 1] = { b = b, z = zc[1] }; zPrev = b
  end

  local oxRow = sliderRow(kb, -222, "Offset X", -40, 40, 1,
    function() local h = hotkeyData(); return (h and h.offsetX) or 0 end,
    function(v) local h = ensureHotkey(); h.offsetX = v; reapply() end,
    function(v) return v .. "px" end)
  local oyRow = sliderRow(kb, -266, "Offset Y", -40, 40, 1,
    function() local h = hotkeyData(); return (h and h.offsetY) or 0 end,
    function(v) local h = ensureHotkey(); h.offsetY = v; reapply() end,
    function(v) return v .. "px" end)

  -- OUTLINE & SHADOW now follows POSITION (was at -160, above it).
  local kbStyle = textStyleGroup(kb, -304, hotkeyData, ensureHotkey, reapply, false, hotkeyOn)

  -- Modifiers — a SUB-feature of Custom keybind: swap the keybind's modifier
  -- prefixes (m-/s-/c-/a-) for Mac symbols (⌘⇧⌃⌥), hyphen removed. Only renders
  -- while Custom keybind is on (greyed + inert when off); stored per style
  -- (keybindMods) so the choice persists across the master toggle.
  local mhdr = newText(kb, FONT.head, 13, COLOR.purple, "LEFT"); mhdr:SetPoint("TOPLEFT", 18, -522); mhdr:SetText("MODIFIERS")
  local mlab = newText(kb, FONT.body, 12, TEXT, "LEFT"); mlab:SetPoint("TOPLEFT", 18, -552); mlab:SetText("Mac symbol icons")
  local modTog = makeToggle(kb,
    function() local st = GB.db and GB.db.styleData; return st and st.keybindMods == "symbols" end,
    function(v)
      local st = GB.db and GB.db.styleData; if st then st.keybindMods = v and "symbols" or "default" end
      if GB.Skin then GB.Skin:RefreshHotkeyText() end
    end)
  modTog:SetPoint("TOPRIGHT", -18, -550)

  local kbHint = newText(kb, FONT.body, 11, MUTE, "LEFT")
  kbHint:SetPoint("TOPLEFT", 18, -582); kbHint:SetPoint("RIGHT", kb, "RIGHT", -16, 0); kbHint:SetJustifyH("LEFT")
  kbHint:SetText("Everything here needs Custom keybind on. Mac symbol icons replace m-/s-/c-/a- prefixes with ⌘/⇧/⌃/⌥ (macOS binds).")
  kb.refresh = function()
    local h = hotkeyData()
    local on = hotkeyOn()
    en:refresh(); cs:refresh(); sizeRow:refresh(); oxRow:refresh(); oyRow:refresh()
    fontBtn:refresh(); modTog:refresh()
    -- Grey the styling controls when the override is off (Mac symbols gate on it too now).
    cs.swatch:EnableMouse(on); cs.swatch:SetAlpha(on and 1 or 0.35)
    sizeRow:setEnabled(on); oxRow:setEnabled(on); oyRow:setEnabled(on)
    fontBtn:SetEnabled(on)
    modTog:SetEnabled(on); modTog:SetAlpha(on and 1 or 0.35)
    for _, e in ipairs(zoneBtns) do e.b:SetActive(on and ((h and h.zone) or "extension") == e.z); e.b:SetEnabled(on) end
    kbStyle.refresh(on)
  end

  -- ------------------------------------------------------------- CHARGE COUNT
  local ct = newBlock("count", 560)
  local ctlab = newText(ct, FONT.body, 12, TEXT, "LEFT"); ctlab:SetPoint("TOPLEFT", 18, -14); ctlab:SetText("Custom count")
  local cten = makeToggle(ct, countOn,
    function(v) local c = ensureCount(); if c then c.enabled = v and true or false end; reapply(); ct.refresh() end)
  cten:SetPoint("TOPRIGHT", -18, -12)

  local ctclab = newText(ct, FONT.body, 12, TEXT, "LEFT"); ctclab:SetPoint("TOPLEFT", 18, -46); ctclab:SetText("Color")
  local ctcs = colorSwatch(ct,
    function() local c = countData(); return c and c.color end,
    function(col) local c = ensureCount(); c.color = col; reapply() end)
  ctcs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local ctSize = sliderRow(ct, -78, "Size", 6, 28, 1,
    function() local c = countData(); return (c and c.size) or 14 end,
    function(v) local c = ensureCount(); c.size = v; reapply() end,
    function(v) return v .. "px" end)

  local ctflab = newText(ct, FONT.body, 12, TEXT, "LEFT"); ctflab:SetPoint("TOPLEFT", 18, -122); ctflab:SetText("Font")
  local ctFont = fontDropdown(ct, 150,
    function() local c = countData(); return c and c.font end,
    function(name) local c = ensureCount(); c.font = name; reapply() end)
  ctFont:SetPoint("TOPRIGHT", -18, -120)

  -- POSITION — zone (Blizzard's corner / centred on the icon / in the plate half).
  -- POSITION sits ABOVE Outline & shadow (Jason); OUTLINE & SHADOW follows below.
  local ctphdr = newText(ct, FONT.head, 13, COLOR.purple, "LEFT"); ctphdr:SetPoint("TOPLEFT", 18, -160); ctphdr:SetText("POSITION")
  local ctzlab = newText(ct, FONT.body, 12, TEXT, "LEFT"); ctzlab:SetPoint("TOPLEFT", 18, -190); ctzlab:SetText("Zone")
  local ctZone, ctzPrev = {}, nil
  for i = 3, 1, -1 do   -- reverse → Corner ends up leftmost
    local zc = ({ { "corner", "Corner" }, { "center", "Center" }, { "extension", "Plate" } })[i]
    local b = flatButton(ct, 60, 22, COLOR.heroic, zc[2], 11)
    if ctzPrev then b:SetPoint("TOPRIGHT", ctzPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -188) end
    b:SetScript("OnClick", function()
      local c = ensureCount(); c.zone = zc[1]
      for _, e in ipairs(ctZone) do e.b:SetActive(e.z == c.zone) end; reapply()
    end)
    ctZone[#ctZone + 1] = { b = b, z = zc[1] }; ctzPrev = b
  end

  local ctOx = sliderRow(ct, -222, "Offset X", -40, 40, 1,
    function() local c = countData(); return (c and c.offsetX) or 0 end,
    function(v) local c = ensureCount(); c.offsetX = v; reapply() end,
    function(v) return v .. "px" end)
  local ctOy = sliderRow(ct, -266, "Offset Y", -40, 40, 1,
    function() local c = countData(); return (c and c.offsetY) or 0 end,
    function(v) local c = ensureCount(); c.offsetY = v; reapply() end,
    function(v) return v .. "px" end)

  -- OUTLINE & SHADOW now follows POSITION (was at -160, above it).
  local ctStyle = textStyleGroup(ct, -304, countData, ensureCount, reapply, false, countOn)

  local ctHint = newText(ct, FONT.body, 11, MUTE, "LEFT")
  ctHint:SetPoint("TOPLEFT", 18, -522); ctHint:SetPoint("RIGHT", ct, "RIGHT", -16, 0); ctHint:SetJustifyH("LEFT")
  ctHint:SetText("Styles the charge / stack / item count. Corner = Blizzard's spot on the icon; Plate centres it in the plate half (2:1 plate shapes only).")
  ct.refresh = function()
    local c = countData()
    local on = countOn()
    cten:refresh(); ctcs:refresh(); ctSize:refresh(); ctOx:refresh(); ctOy:refresh(); ctFont:refresh()
    ctcs.swatch:EnableMouse(on); ctcs.swatch:SetAlpha(on and 1 or 0.35)
    ctSize:setEnabled(on); ctOx:setEnabled(on); ctOy:setEnabled(on)
    ctFont:SetEnabled(on)
    for _, e in ipairs(ctZone) do e.b:SetActive(on and ((c and c.zone) or "corner") == e.z); e.b:SetEnabled(on) end
    ctStyle.refresh(on)
  end

  -- ---------------------------------------------------------------- COUNTDOWN
  local cd = newBlock("cdtext", 502)
  local cdlab = newText(cd, FONT.body, 12, TEXT, "LEFT"); cdlab:SetPoint("TOPLEFT", 18, -14); cdlab:SetText("Countdown numbers")
  local cdTog = makeToggle(cd, cdtextOn,
    function(v) local c = ensureCdtext(); if c then c.enabled = v and true or false end; reCD(); cd.refresh() end)
  cdTog:SetPoint("TOPRIGHT", -18, -12)

  local cdclab = newText(cd, FONT.body, 12, TEXT, "LEFT"); cdclab:SetPoint("TOPLEFT", 18, -46); cdclab:SetText("Color")
  local cdcs = colorSwatch(cd,
    function() local c = cdtextData(); return c and c.color end,
    function(col) local c = ensureCdtext(); c.color = col; reCD() end)
  cdcs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local cdSize = sliderRow(cd, -78, "Size", 8, 30, 1,
    function() local c = cdtextData(); return (c and c.size) or 16 end,
    function(v) local c = ensureCdtext(); c.size = v; reCD() end,
    function(v) return v .. "px" end)

  local cdflab = newText(cd, FONT.body, 12, TEXT, "LEFT"); cdflab:SetPoint("TOPLEFT", 18, -122); cdflab:SetText("Font")
  local cdFont = fontDropdown(cd, 150,
    function() local c = cdtextData(); return c and c.font end,
    function(name) local c = ensureCdtext(); c.font = name; reCD() end)
  cdFont:SetPoint("TOPRIGHT", -18, -120)

  -- POSITION (offsets only — countdown numbers have no zone) ABOVE Outline &
  -- shadow (Jason); OUTLINE & SHADOW follows below.
  local cdOx = sliderRow(cd, -160, "Offset X", -40, 40, 1,
    function() local c = cdtextData(); return (c and c.offsetX) or 0 end,
    function(v) local c = ensureCdtext(); c.offsetX = v; reCD() end,
    function(v) return v .. "px" end)
  local cdOy = sliderRow(cd, -204, "Offset Y", -40, 40, 1,
    function() local c = cdtextData(); return (c and c.offsetY) or 0 end,
    function(v) local c = ensureCdtext(); c.offsetY = v; reCD() end,
    function(v) return v .. "px" end)

  -- OUTLINE & SHADOW now follows the offsets (was at -160, above them).
  local cdStyle = textStyleGroup(cd, -244, cdtextData, ensureCdtext, reCD, true, cdtextOn)

  local cdHint = newText(cd, FONT.body, 11, MUTE, "LEFT")
  cdHint:SetPoint("TOPLEFT", 18, -456); cdHint:SetPoint("RIGHT", cd, "RIGHT", -16, 0); cdHint:SetJustifyH("LEFT")
  cdHint:SetText("The number Blizzard draws while a cooldown runs. Off = hidden. Styling applies from the next cooldown update.")
  cd.refresh = function()
    local on = cdtextOn()
    cdTog:refresh(); cdcs:refresh(); cdSize:refresh(); cdOx:refresh(); cdOy:refresh(); cdFont:refresh()
    cdcs.swatch:EnableMouse(on); cdcs.swatch:SetAlpha(on and 1 or 0.35)
    cdSize:setEnabled(on); cdOx:setEnabled(on); cdOy:setEnabled(on)
    cdFont:SetEnabled(on)
    cdStyle.refresh(on)
  end

  -- --------------------------------------------------------------------- NAME
  local nm = newBlock("name", 600)   -- POSITION-above-shadow reorder pushed the long hint lower
  local nmlab = newText(nm, FONT.body, 12, TEXT, "LEFT"); nmlab:SetPoint("TOPLEFT", 18, -14); nmlab:SetText("Macro name")
  local nmModes, nmmPrev = {}, nil
  for i = 3, 1, -1 do   -- reverse → Default ends up leftmost
    local mc = ({ { "default", "Default" }, { "custom", "Custom" }, { "hidden", "Hidden" } })[i]
    local b = flatButton(nm, 60, 22, COLOR.heroic, mc[2], 11)
    if nmmPrev then b:SetPoint("TOPRIGHT", nmmPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -12) end
    b:SetScript("OnClick", function()
      local c = ensureName(); c.mode = mc[1]; c.enabled = nil   -- mode supersedes the legacy flag
      reapply(); nm.refresh()
    end)
    nmModes[#nmModes + 1] = { b = b, m = mc[1] }; nmmPrev = b
  end

  local nmclab = newText(nm, FONT.body, 12, TEXT, "LEFT"); nmclab:SetPoint("TOPLEFT", 18, -46); nmclab:SetText("Color")
  local nmcs = colorSwatch(nm,
    function() local c = nameData(); return c and c.color end,
    function(col) local c = ensureName(); c.color = col; reapply() end)
  nmcs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local nmSize = sliderRow(nm, -78, "Size", 6, 28, 1,
    function() local c = nameData(); return (c and c.size) or 10 end,
    function(v) local c = ensureName(); c.size = v; reapply() end,
    function(v) return v .. "px" end)

  local nmflab = newText(nm, FONT.body, 12, TEXT, "LEFT"); nmflab:SetPoint("TOPLEFT", 18, -122); nmflab:SetText("Font")
  local nmFont = fontDropdown(nm, 150,
    function() local c = nameData(); return c and c.font end,
    function(name) local c = ensureName(); c.font = name; reapply() end)
  nmFont:SetPoint("TOPRIGHT", -18, -120)

  -- POSITION — zone (Blizzard's bottom edge / centred on the icon / in the plate
  -- half). POSITION sits ABOVE Outline & shadow (Jason); OUTLINE & SHADOW follows.
  local nmphdr = newText(nm, FONT.head, 13, COLOR.purple, "LEFT"); nmphdr:SetPoint("TOPLEFT", 18, -160); nmphdr:SetText("POSITION")
  local nmzlab = newText(nm, FONT.body, 12, TEXT, "LEFT"); nmzlab:SetPoint("TOPLEFT", 18, -190); nmzlab:SetText("Zone")
  local nmZone, nmzPrev = {}, nil
  for i = 3, 1, -1 do   -- reverse → Bottom ends up leftmost
    local zc = ({ { "bottom", "Bottom" }, { "center", "Center" }, { "extension", "Plate" } })[i]
    local b = flatButton(nm, 60, 22, COLOR.heroic, zc[2], 11)
    if nmzPrev then b:SetPoint("TOPRIGHT", nmzPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -188) end
    b:SetScript("OnClick", function()
      local c = ensureName(); c.zone = zc[1]
      for _, e in ipairs(nmZone) do e.b:SetActive(e.z == c.zone) end; reapply()
    end)
    nmZone[#nmZone + 1] = { b = b, z = zc[1] }; nmzPrev = b
  end

  local nmOx = sliderRow(nm, -222, "Offset X", -40, 40, 1,
    function() local c = nameData(); return (c and c.offsetX) or 0 end,
    function(v) local c = ensureName(); c.offsetX = v; reapply() end,
    function(v) return v .. "px" end)
  local nmOy = sliderRow(nm, -266, "Offset Y", -40, 40, 1,
    function() local c = nameData(); return (c and c.offsetY) or 0 end,
    function(v) local c = ensureName(); c.offsetY = v; reapply() end,
    function(v) return v .. "px" end)

  -- OUTLINE & SHADOW now follows POSITION (was at -160, above it).
  local nmStyle = textStyleGroup(nm, -304, nameData, ensureName, reapply, true,
    function() return nameMode() == "custom" end)

  local nmHint = newText(nm, FONT.body, 11, MUTE, "LEFT")
  nmHint:SetPoint("TOPLEFT", 18, -516); nmHint:SetPoint("RIGHT", nm, "RIGHT", -16, 0); nmHint:SetJustifyH("LEFT")
  nmHint:SetText("The macro-name label. Default = Blizzard's stock look; Hidden removes it entirely. Custom applies the styling above and widens Blizzard's 36px clip box to the icon. Plate centres it in the plate half (2:1 plate shapes only).")
  nm.refresh = function()
    local c = nameData()
    local m = nameMode()
    local on = m == "custom"
    nmcs:refresh(); nmSize:refresh(); nmOx:refresh(); nmOy:refresh(); nmFont:refresh()
    for _, e in ipairs(nmModes) do e.b:SetActive(e.m == m) end
    nmcs.swatch:EnableMouse(on); nmcs.swatch:SetAlpha(on and 1 or 0.35)
    nmSize:setEnabled(on); nmOx:setEnabled(on); nmOy:setEnabled(on)
    nmFont:SetEnabled(on)
    for _, e in ipairs(nmZone) do e.b:SetActive(on and ((c and c.zone) or "bottom") == e.z); e.b:SetEnabled(on) end
    nmStyle.refresh(on)
  end

  -- Chip row (which text element is being edited) + selection.
  selectTab = function(k)
    tab = k
    for _, c in ipairs(chips) do c.b:SetActive(c.k == k) end
    for key, f in pairs(blocks) do f:SetShown(key == k) end
    local b = blocks[k]
    b.refresh()
    bf:SetHeight(-BLOCK_TOP + b.height)
    relayout()
  end
  local cPrev
  for _, t in ipairs(TEXT_TABS) do
    local w = 24 + t[2]:len() * 6
    local b = flatButton(bf, w, 22, COLOR.heroic, t[2], 11); b:SetBase(0.2)
    if cPrev then b:SetPoint("TOPLEFT", cPrev, "TOPRIGHT", 6, 0) else b:SetPoint("TOPLEFT", 18, -12) end
    b:SetScript("OnClick", function() selectTab(t[1]) end)
    chips[#chips + 1] = { b = b, k = t[1] }; cPrev = b
  end

  bf:SetHeight(-BLOCK_TOP + blocks[tab].height)
  s.refresh = function() selectTab(tab) end
end

-- Empty slots — dim or hide bar slots with no action. Alpha-only (the secure
-- button is never shown/hidden — pure-skin wall); while an action is on the
-- cursor the slots return automatically so drop targets stay visible.
local function buildEmptySection(bf, s)
  local function mode() return (GB.db and GB.db.emptySlots) or "normal" end
  local mlab = newText(bf, FONT.body, 12, TEXT, "LEFT"); mlab:SetPoint("TOPLEFT", 18, -14); mlab:SetText("Empty slots")
  local modeBtns, prev = {}, nil
  local function setMode(v)
    if GB.Skin and GB.Skin.SetEmptySlots then GB.Skin:SetEmptySlots(v)
    elseif GB.db then GB.db.emptySlots = v end
    s.refresh()
  end
  for i = 3, 1, -1 do   -- reverse → Normal ends up leftmost
    local mc = ({ { "normal", "Normal" }, { "dim", "Dim" }, { "hide", "Hidden" } })[i]
    local b = flatButton(bf, 60, 22, COLOR.heroic, mc[2], 11)
    if prev then b:SetPoint("TOPRIGHT", prev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -12) end
    b:SetScript("OnClick", function() setMode(mc[1]) end)
    modeBtns[#modeBtns + 1] = { b = b, v = mc[1] }; prev = b
  end

  local dimRow = sliderRow(bf, -46, "Dim opacity", 0.05, 0.9, 0.05,
    function() return (GB.db and GB.db.emptySlotAlpha) or 0.35 end,
    function(v)
      if GB.Skin and GB.Skin.SetEmptySlotAlpha then GB.Skin:SetEmptySlotAlpha(v)
      elseif GB.db then GB.db.emptySlotAlpha = v end
    end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -90); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Slots with no action fade or vanish. They come back on their own while you drag a spell, so drop targets stay visible.")
  bf:SetHeight(124)
  s.refresh = function()
    for _, e in ipairs(modeBtns) do e.b:SetActive(e.v == mode()) end
    dimRow:setEnabled(mode() == "dim"); dimRow:refresh()
  end
end

-- Cast & channel — our pill-shaped fill (replaces Blizzard's square drain) and
-- the cancel/interrupt burst. All db-level (not per-style); the engine reads
-- these live on the NEXT cast (styleCast / CastFillOnUpdate / PlayEndBurstRed in
-- Skin.lua), so the setters are plain db writes — no ReapplyDecor, and the
-- preview pane doesn't animate casts. Test by casting / cancelling a spell.
local function buildCastSection(bf, s)
  local rows = {}
  local function showCast() C:SetPreviewState("cast") end   -- fill edits animate on the Cast chip
  -- FILL (cast fills up, channel drains).
  local flab = newText(bf, FONT.body, 12, TEXT, "LEFT"); flab:SetPoint("TOPLEFT", 18, -14); flab:SetText("Fill color")
  local fcs = colorSwatch(bf,
    function() return GB.db and GB.db.castFillColor end,
    function(c) if GB.db then GB.db.castFillColor = c end; showCast() end)
  fcs.swatch:SetPoint("TOPRIGHT", -18, -12)
  rows[#rows + 1] = fcs

  local opRow = sliderRow(bf, -46, "Opacity", 0, 1, 0.05,
    function() return (GB.db and GB.db.castFillAlpha) or 0.55 end,
    function(v) if GB.db then GB.db.castFillAlpha = v end; showCast() end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  rows[#rows + 1] = opRow

  local dirR = dirRow(bf, -96, "Direction",
    function() return (GB.db and GB.db.castDrainDir) or "up" end,
    function(d) if GB.db then GB.db.castDrainDir = d end; showCast() end)
  rows[#rows + 1] = dirR

  -- COMPLETE = the burst on a SUCCESSFUL cast/channel (Blizzard's completion flash,
  -- shaped + tinted). Distinct from the cooldown Finish flash (Cooldown & availability),
  -- which fires when an ability comes OFF cooldown.
  local cclab = newText(bf, FONT.body, 12, TEXT, "LEFT"); cclab:SetPoint("TOPLEFT", 18, -136); cclab:SetText("Complete color")
  local ccs = colorSwatch(bf,
    function() return GB.db and GB.db.castCompleteColor end,
    function(c) if GB.db then GB.db.castCompleteColor = c end end)
  ccs.swatch:SetPoint("TOPRIGHT", -18, -134)
  rows[#rows + 1] = ccs

  -- INTERRUPT / cancel = Blizzard's completion burst replayed in this colour.
  local ihdr = newText(bf, FONT.head, 13, COLOR.purple, "LEFT"); ihdr:SetPoint("TOPLEFT", 18, -172); ihdr:SetText("INTERRUPT")
  local iclab = newText(bf, FONT.body, 12, TEXT, "LEFT"); iclab:SetPoint("TOPLEFT", 18, -202); iclab:SetText("Color")
  local ics = colorSwatch(bf,
    function() return GB.db and GB.db.castInterruptColor end,
    function(c) if GB.db then GB.db.castInterruptColor = c end end)
  ics.swatch:SetPoint("TOPRIGHT", -18, -200)
  rows[#rows + 1] = ics

  local spRow = sliderRow(bf, -234, "Speed", 0.2, 2, 0.1,
    function() return (GB.db and GB.db.castInterruptSpeed) or 0.6 end,
    function(v) if GB.db then GB.db.castInterruptSpeed = v end end,
    function(v) return string.format("%.1fx", v) end)
  rows[#rows + 1] = spRow

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -274); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Changes apply on your next cast. Speed <1 slows the interrupt burst.")
  bf:SetHeight(304)
  s.refresh = function() for _, r in ipairs(rows) do r:refresh() end end
end

-- Glows — the unified shaped-glow matrix (session 10). Every button state that
-- drives the multi-part glow is ONE row: on-toggle · colour · layers (both / inner /
-- outer) · opacity, plus a global Pulse speed. Supersedes the old separate Proc glow
-- + State highlights sections (one engine now — GB.db.triggers). Cast fill/burst stay
-- in Cast & channel; only the cast/channel HALO colour+opacity live here.
local function trig(key) return GB.db and GB.db.triggers and GB.db.triggers[key] end

-- Layer cycle cell: a compact button showing the trigger's current layers
-- ("Both"/"Inner"/"Outer"); click cycles Both → Inner → Outer. onChange() lets the
-- caller reflect it in the preview. Returns { btn, refresh, setEnabled }.
local LAYER_LABEL = { both = "Both", inner = "Inner", outer = "Outer" }
local LAYER_NEXT  = { both = "inner", inner = "outer", outer = "both" }
local function layersCell(bf, x, yTop, key, onChange)
  local b = flatButton(bf, 50, 20, COLOR.heroic, "Both", 11)
  b:SetPoint("TOPLEFT", x, yTop)
  local function cur() local t = trig(key); return (t and t.layers) or "both" end
  local function paint() b.text:SetText(LAYER_LABEL[cur()] or "Both") end
  b:SetScript("OnClick", function()
    if GB.Glows then GB.Glows:SetTriggerLayers(key, LAYER_NEXT[cur()] or "both") end
    paint(); if onChange then onChange() end
  end)
  paint()
  local cell = { btn = b }
  function cell:refresh() paint() end
  function cell:setEnabled(on) b:SetEnabled(on) end
  return cell
end

-- Compact inline opacity slider for a matrix row (0–100%). Shares the sliders'
-- click/drag-anywhere-to-seek QOL. onChange() refreshes the preview. { refresh, setEnabled }.
local function opacityCell(bf, xLeft, yTop, key, onChange)
  local val = newText(bf, FONT.label, 11, TEXT, "RIGHT"); val:SetPoint("TOPRIGHT", -12, yTop - 3)
  local sl = CreateFrame("Slider", nil, bf)
  sl:SetPoint("TOPLEFT", xLeft, yTop - 4); sl:SetPoint("TOPRIGHT", -46, yTop - 4); sl:SetHeight(16)
  sl:EnableMouse(true); sl:SetOrientation("HORIZONTAL"); sl:SetMinMaxValues(0, 1); sl:SetValueStep(0.05); sl:SetObeyStepOnDrag(true)
  local track = sl:CreateTexture(nil, "BACKGROUND"); track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(6)
  track:SetColorTexture(COLOR.heroic.r, COLOR.heroic.g, COLOR.heroic.b, 0.20)
  local thumb = sl:CreateTexture(nil, "ARTWORK"); thumb:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1)
  thumb:SetSize(5, 18); sl:SetThumbTexture(thumb)
  local applying = false
  local function show(v) val:SetText(math.floor(v * 100 + 0.5) .. "%") end
  sl:SetScript("OnValueChanged", function(_, v)
    if not applying then if GB.Glows then GB.Glows:SetTriggerOpacity(key, v) end; if onChange then onChange() end end
    show(v)
  end)
  local function seek(self)
    local left, w = self:GetLeft(), self:GetWidth()
    if not (left and w and w > 0) then return end
    local frac = (GetCursorPosition() / self:GetEffectiveScale() - left) / w
    frac = math.max(0, math.min(1, frac))
    self:SetValue(math.floor(frac / 0.05 + 0.5) * 0.05)
  end
  -- A drag STARTING ON THE THUMB belongs to the native slider alone: with our
  -- seek also writing every frame, the two quantize the cursor differently
  -- near step boundaries and the value flickers between neighbours (Jason:
  -- "blurs" — worst on wide ranges like Gap's 0–64). Off-thumb, seek owns it.
  sl:SetScript("OnMouseDown", function(self)
    if not self:IsEnabled() then return end
    local left, w = self:GetLeft(), self:GetWidth()
    if left and w and w > 0 then
      local cx = GetCursorPosition() / self:GetEffectiveScale()
      local mn, mx = self:GetMinMaxValues()
      local tx = left + ((self:GetValue() - mn) / math.max(mx - mn, 1e-6)) * w
      if math.abs(cx - tx) <= 8 then return end   -- on the thumb → native drag
    end
    self._seek = true; seek(self)
  end)
  sl:SetScript("OnMouseUp", function(self) self._seek = false end)
  sl:SetScript("OnUpdate", function(self)
    if self._seek then
      if self:IsEnabled() and IsMouseButtonDown("LeftButton") then seek(self) else self._seek = false end
    end
  end)
  local cell = {}
  function cell:refresh() applying = true; local t = trig(key); sl:SetValue((t and t.opacity) or 1); show((t and t.opacity) or 1); applying = false end
  function cell:setEnabled(on) sl:SetEnabled(on); sl:SetAlpha(on and 1 or 0.35) end
  cell:refresh()
  return cell
end

-- The triggers, in priority (display) order. Third field = the preview chip to
-- flip to on edit — every trigger has one now (session 12).
local GLOW_ROWS = {
  { "proc", "Proc", "proc" }, { "highlight", "Highlight", "highlight" },
  { "cast", "Cast", "cast" }, { "channel", "Channel", "channel" },
  { "hover", "Hover", "hover" }, { "selected", "Selected", "selected" },
  { "flash", "Flash", "flash" }, { "assist", "Assist", "assist" },
}
local GX_TOG, GX_SW, GX_LAY, GX_SLIDE = 92, 142, 180, 236
local function buildGlowsSection(bf, s)
  local rows = {}
  local function showPrev(prev) if prev then C:SetPreviewState(prev) end end

  -- Global: pulse speed (applies to every pulsing trigger — proc / assist / flash).
  rows[#rows + 1] = sliderRow(bf, -14, "Pulse speed", 0.3, 2, 0.1,
    function() return (GB.db and GB.db.glowPulseSpeed) or 1 end,
    function(v) if GB.Glows then GB.Glows:SetPulseSpeed(v) end end,
    function(v) return string.format("%.1fx", v) end)

  -- Column headers.
  local function head(x, txt) local h = newText(bf, FONT.body, 10.5, MUTE, "LEFT"); h:SetPoint("TOPLEFT", x, -52); h:SetText(txt) end
  head(GX_TOG, "on"); head(GX_SW, "colour"); head(GX_LAY, "layers"); head(GX_SLIDE + 8, "opacity")

  local y = -72
  for _, r in ipairs(GLOW_ROWS) do
    local key, label, prev = r[1], r[2], r[3]
    local yTop = y
    local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, yTop); lab:SetText(label)

    local cs = colorSwatch(bf,
      function() local t = trig(key); return t and t.color end,
      function(c) if GB.Glows then GB.Glows:SetTriggerColor(key, c) end; showPrev(prev) end)
    cs.swatch:SetPoint("TOPLEFT", GX_SW, yTop - 1)

    local lay = layersCell(bf, GX_LAY, yTop - 1, key, function() showPrev(prev) end)
    local op = opacityCell(bf, GX_SLIDE, yTop, key, function() showPrev(prev) end)

    -- Enable toggle greys the row's controls when off.
    local function applyEnabled()
      local t = trig(key); local on = t and t.enabled ~= false
      cs.swatch:SetEnabled(on); cs.swatch:SetAlpha(on and 1 or 0.4)
      lay:setEnabled(on); op:setEnabled(on)
    end
    local tog = makeToggle(bf,
      function() local t = trig(key); return t and t.enabled ~= false end,
      function(on) if GB.Glows then GB.Glows:SetTriggerEnabled(key, on) end; applyEnabled(); showPrev(prev) end)
    tog:SetPoint("TOPLEFT", GX_TOG, yTop - 1)

    rows[#rows + 1] = { refresh = function() cs:refresh(); lay:refresh(); op:refresh(); tog:refresh(); applyEnabled() end }
    y = y - 30
  end

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, y - 6); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Click a Layers cell to cycle Both / Inner / Outer. Cast fill/burst live in Cast & channel.")
  bf:SetHeight(-y + 40)

  s.refresh = function()
    for _, rw in ipairs(rows) do rw:refresh() end
    C:SetPreviewState("proc")
  end
end

-- Cooldown & availability — cooldown sweep tint / opacity, our shape-masked finish
-- flash, and the availability tint (usable / unusable / out-of-mana). All
-- combat-safe: we react to Blizzard's rendered output, never reading secret values.
local function buildCooldownSection(bf, s)
  local rows = {}
  local function showCD() C:SetPreviewState("cooldown") end   -- reflect sweep edits on the Cooldown chip

  local cl = newText(bf, FONT.body, 12, TEXT, "LEFT"); cl:SetPoint("TOPLEFT", 18, -14); cl:SetText("Sweep color")
  local cs = colorSwatch(bf,
    function() return GB.db and GB.db.swipeColor end,
    function(c) if GB.Skin then GB.Skin:SetSwipeColor(c) end; showCD() end)
  cs.swatch:SetPoint("TOPRIGHT", -18, -12); rows[#rows + 1] = cs

  local opRow = sliderRow(bf, -46, "Sweep opacity", 0, 1, 0.05,
    function() return (GB.db and GB.db.swipeAlpha) or 0.8 end,
    function(v) if GB.Skin then GB.Skin:SetSwipeAlpha(v) end; showCD() end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  rows[#rows + 1] = opRow

  -- Finish flash: toggle + its colour (colour greyed while off). Both replay the
  -- flash on the preview so you can tune it without waiting for a real cooldown.
  local fl = newText(bf, FONT.body, 12, TEXT, "LEFT"); fl:SetPoint("TOPLEFT", 18, -92); fl:SetText("Finish flash")
  local fTog = makeToggle(bf,
    function() return GB.db and GB.db.finishFlash end,
    function(v) if GB.Skin then GB.Skin:SetFinishFlash(v) end; s.refresh(); C:PlayPreviewFlash() end)
  fTog:SetPoint("TOPRIGHT", -18, -90); rows[#rows + 1] = fTog
  local fcl = newText(bf, FONT.body, 12, TEXT, "LEFT"); fcl:SetPoint("TOPLEFT", 30, -122); fcl:SetText("Flash color")
  local fcs = colorSwatch(bf,
    function() return GB.db and GB.db.finishFlashColor end,
    function(c) if GB.Skin then GB.Skin:SetFinishFlashColor(c) end; C:PlayPreviewFlash() end)
  fcs.swatch:SetPoint("TOPRIGHT", -18, -120); rows[#rows + 1] = fcs

  -- AVAILABILITY — restyle Blizzard's usable/unusable/out-of-mana icon tint.
  local avlab = newText(bf, FONT.head, 13, COLOR.purple, "LEFT"); avlab:SetPoint("TOPLEFT", 18, -164); avlab:SetText("AVAILABILITY")
  local dl = newText(bf, FONT.body, 12, TEXT, "LEFT"); dl:SetPoint("TOPLEFT", 18, -194); dl:SetText("Desaturate unusable")
  local dTog = makeToggle(bf,
    function() return GB.db and GB.db.availDesaturate end,
    function(v) if GB.Skin then GB.Skin:SetAvailDesaturate(v) end end)
  dTog:SetPoint("TOPRIGHT", -18, -192); rows[#rows + 1] = dTog
  local ul = newText(bf, FONT.body, 12, TEXT, "LEFT"); ul:SetPoint("TOPLEFT", 18, -226); ul:SetText("Unusable tint")
  local ucs = colorSwatch(bf,
    function() return GB.db and GB.db.availUnusable end,
    function(c) if GB.Skin then GB.Skin:SetAvailUnusable(c) end end)
  ucs.swatch:SetPoint("TOPRIGHT", -18, -224); rows[#rows + 1] = ucs
  local ml = newText(bf, FONT.body, 12, TEXT, "LEFT"); ml:SetPoint("TOPLEFT", 18, -256); ml:SetText("Out-of-mana tint")
  local mcs = colorSwatch(bf,
    function() return GB.db and GB.db.availOOM end,
    function(c) if GB.Skin then GB.Skin:SetAvailOOM(c) end end)
  mcs.swatch:SetPoint("TOPRIGHT", -18, -254); rows[#rows + 1] = mcs

  -- Out of range: tint the icon to match Blizzard's red out-of-range keybind.
  local rl = newText(bf, FONT.body, 12, TEXT, "LEFT"); rl:SetPoint("TOPLEFT", 18, -288); rl:SetText("Tint out-of-range")
  local rTog = makeToggle(bf,
    function() return GB.db and GB.db.rangeTint end,
    function(v) if GB.Skin then GB.Skin:SetRangeTint(v) end; s.refresh() end)
  rTog:SetPoint("TOPRIGHT", -18, -286); rows[#rows + 1] = rTog
  local rcl = newText(bf, FONT.body, 12, TEXT, "LEFT"); rcl:SetPoint("TOPLEFT", 30, -318); rcl:SetText("Range color")
  local rcs = colorSwatch(bf,
    function() return GB.db and GB.db.rangeColor end,
    function(c) if GB.Skin then GB.Skin:SetRangeColor(c) end end)
  rcs.swatch:SetPoint("TOPRIGHT", -18, -316); rows[#rows + 1] = rcs

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -354); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Availability tints react to Blizzard's own checks (no preview — test on the bars). Out-of-range matches the red keybind; unusable/mana fire for wrong form, missing resources, etc. Countdown-number styling lives in Text.")
  bf:SetHeight(394)
  s.refresh = function()
    for _, r in ipairs(rows) do if r.refresh then r:refresh() end end
    local flashOn = GB.db and GB.db.finishFlash
    fcl:SetAlpha(flashOn and 1 or 0.35); fcs.swatch:EnableMouse(flashOn and true or false); fcs.swatch:SetAlpha(flashOn and 1 or 0.35)
    local rangeOn = GB.db and GB.db.rangeTint
    rcl:SetAlpha(rangeOn and 1 or 0.35); rcs.swatch:EnableMouse(rangeOn and true or false); rcs.swatch:SetAlpha(rangeOn and 1 or 0.35)
    C:SetPreviewState("cooldown")   -- show the sweep while this section is open
  end
end

-- --------------------------------------------------------------------------
-- Live preview pane (left). A sample construction rendered from the SAME shape
-- art the skin engine uses, so it matches the real bars. State chips let you
-- see proc / cooldown / hover / selected / flash on demand (you can't trigger a
-- real proc while editing). It's our own frame, so a fresh mask per change is
-- cheap and dodges the live-mask re-render quirk entirely.
-- --------------------------------------------------------------------------
local function sampleIconTexture()
  local b = _G["ActionButton1"]
  local ic = b and (b.icon or b.Icon)
  local tex = ic and ic.GetTexture and ic:GetTexture()
  return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local PREVIEW_STATES = {
  { "idle", "Idle" }, { "proc", "Proc" },
  { "highlight", "Highlight" }, { "assist", "Assist" },
  { "cast", "Cast" }, { "channel", "Channel" },
  { "hover", "Hover" }, { "selected", "Selected" },
  { "flash", "Flash" }, { "cooldown", "Cooldown" },
  { "unusable", "Unusable" }, { "oom", "Out of mana" },
  { "range", "Out of range" },
}
local RING_TINT = { hover = { 1, 0.82, 0.35 }, selected = { 0.45, 0.75, 1 }, flash = { 1, 0.25, 0.25 } }

-- Live extension % (mirror Skin.lua ExtensionPct: hexagon is a fixed shape → no
-- plate; signed key with a legacy below-only fallback). Drives the preview's
-- plate/mask/overlay geometry exactly like the bars.
local function previewExtendPct()
  if (GB.db and GB.db.shape) == "hexagon" then return 0 end
  local c = GB.db and GB.db.styleData and GB.db.styleData.construction
  if not c then return 0 end
  if c.extendPct ~= nil then return c.extendPct end
  return c.extendBottomPct or 0
end

-- Anchor an overlay (state ring / cooldown / proc glow) over the whole preview
-- construction (icon + extension), mirroring Skin.AnchorConstruction so overlays
-- follow the full pill and not just the icon. `ratio` = padding grow per axis,
-- `extra` = extra px overshoot.
local function anchorPreviewOverlay(tex, ratio, extra, ref)
  extra = extra or 0
  ref = ref or previewIcon   -- plate mode passes previewFrame for full-construction overlays
  local gx = ref:GetWidth() * ratio + extra
  local gy = (ref:GetHeight() + previewExtH) * ratio + extra
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", ref, "TOPLEFT", -gx, gy + previewExtT)
  tex:SetPoint("BOTTOMRIGHT", ref, "BOTTOMRIGHT", gx, -(gy + previewExtB))
end

-- Pooled gradient-plate texture (textures can't be freed, only reused/hidden).
-- A brand-new texture flags `previewPlateFresh` so RefreshPreview retries its
-- mask next frame (never-rendered textures reject AddMaskTexture — API-NOTES §2).
local function getPreviewPlate(idx)
  local p = previewPlates[idx]
  if not p then
    local tex = previewFrame:CreateTexture(nil, "ARTWORK", nil, 1)   -- sublevel 1 = above the icon
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    p = { tex = tex }
    previewPlates[idx] = p
    previewPlateFresh = true
  end
  return p
end

function C:RefreshPreview()
  if not previewIcon then return end
  local hk = GB.db and GB.db.handShape
  local handInfo = hk and GB:HandShapeInfo(hk)
  local shp = GB:GetShape()
  local style = GB:GetStyle()
  -- Reflect the icon's aspect ratio, fit within a ~104px box (long side = base).
  local base = 104
  local pw, ph = base, base
  if hk then
    -- Hand shape: aspect comes from the silhouette; cap the LONG side to the box.
    if handInfo.orient == "portrait" then pw, ph = base / handInfo.aspect, base
    elseif handInfo.orient == "landscape" then pw, ph = base, base / handInfo.aspect end
  else
    local iw, ih = (GB.db and GB.db.iconW) or 1, (GB.db and GB.db.iconH) or 1
    if iw > 0 and ih > 0 then
      if iw >= ih then pw, ph = base, base * ih / iw else pw, ph = base * iw / ih, base end
    end
  end
  previewFrame:SetSize(pw, ph)

  -- Plate mode (Stage 4b): mirror the bars — the SQUARE icon fills one half of the
  -- 2:1 silhouette, the plate colour the other. The full 2:1 rect IS previewFrame,
  -- so shape anchors (mask/glows/border) point at `sref` (the frame in plate mode)
  -- while the icon shrinks to its half. Non-plate: icon spans the frame, sref ==
  -- previewIcon, so nothing changes for the other shapes.
  previewPlateOn = (plateShapeOK() and plateData() and plateData().enabled) and true or false
  local plateSide = (plateData() and plateData().iconSide) or "top"
  previewIcon:ClearAllPoints()
  if previewPlateOn then
    previewIcon:SetSize(pw, pw)
    local e = (plateSide == "bottom") and "BOTTOM" or "TOP"
    previewIcon:SetPoint(e, previewFrame, e, 0, 0)
  else
    previewIcon:SetAllPoints(previewFrame)
  end
  local sref = previewPlateOn and previewFrame or previewIcon   -- the SHAPE reference rect

  -- Per-axis hand-mask growth (mirrors Skin.hgAnchor): a hand silhouette fills a
  -- different fraction of its canvas per axis, so grow each edge to land `grow` px
  -- out (caps stay round). Anchored to sref's corners using pw/ph directly
  -- (no reliance on GetWidth mid-refresh). grow=0 → icon edge; grow=t → border.
  local function handAnchor(tex, grow)
    grow = grow or 0
    local m0 = 0.5 * math.min(pw, ph)
    local aspect = math.max(pw, ph) / math.max(1, math.min(pw, ph))
    local addL = grow * (aspect + 1) / aspect
    local mx = m0 + (pw <= ph and 2 * grow or addL)
    local my = m0 + (ph < pw and 2 * grow or addL)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", sref, "TOPLEFT", -mx, my)
    tex:SetPoint("BOTTOMRIGHT", sref, "BOTTOMRIGHT", mx, -my)
  end

  -- Construction = icon + extension (a plate above/below). Mirror the engine:
  -- extendPct is signed (< 0 = above), the hexagon has none, and Continuous-OFF
  -- only bites with a plate on a straight-sided shape — force it ON with no
  -- extension or a circle (else the plate loses its mask → an unmasked square).
  -- Hand shapes take no plate extension (the silhouette IS the elongation).
  local extPct = hk and 0 or previewExtendPct()
  local ext = ph * math.abs(extPct)
  local above = extPct < 0
  local continuous = not (style.construction and style.construction.continuous == false)
  if hk or ext == 0 or (GB.db and GB.db.shape) == "circle" then continuous = true end
  local maskExt = continuous and ext or 0
  previewExtH = ext
  previewExtT, previewExtB = (above and ext or 0), (above and 0 or ext)   -- overlays span the real ext
  local mExtT, mExtB = (above and maskExt or 0), (above and 0 or maskExt)  -- masks span only when continuous

  -- Center the whole construction in the stage; the icon shifts so a plate
  -- growing either way keeps the construction visually centered (never rides
  -- into the state chips above or the caption below).
  previewFrame:ClearAllPoints()
  previewFrame:SetPoint("CENTER", previewFrame:GetParent(), "TOP", 0,
    PREVIEW_CENTER_Y + (above and -ext / 2 or ext / 2))

  previewIcon:SetTexture(sampleIconTexture())
  -- Icon mask spans the construction when continuous (one pill wrapping icon +
  -- plate), else just the icon (a rounded icon on a crisp square plate). Same
  -- aspect source the engine uses (maskPlan → the construction's aspect).
  -- A hand shape masks the icon to its own -base silhouette (per-axis grown);
  -- otherwise the SDF aspect mask, grown by GROW_RATIO, as the engine does.
  local maskSrc = hk and GB:HandAsset(hk, "base") or GB.Skin:AspectMask(pw, ph + maskExt)
  local growX = pw * GROW_RATIO
  local growY = (ph + maskExt) * GROW_RATIO
  if previewMask then previewIcon:RemoveMaskTexture(previewMask) end
  previewMask = previewFrame:CreateMaskTexture()
  previewMask:SetTexture(maskSrc or shp.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  if hk then
    handAnchor(previewMask, 0)
  else
    previewMask:ClearAllPoints()
    previewMask:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", -growX, growY + mExtT)
    previewMask:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", growX, -(growY + mExtB))
  end
  previewIcon:AddMaskTexture(previewMask)
  -- Same cover-fit crop as the engine so the preview matches the bars (part a).
  -- Plate mode: the icon is the pw×pw square half → square crop, like the bars.
  if previewPlateOn then
    previewIcon:SetTexCoord(GB.Skin:TexCoordFor(pw, pw))
  else
    previewIcon:SetTexCoord(GB.Skin:TexCoordFor(previewIcon:GetWidth(), previewIcon:GetHeight()))
  end

  -- Overlay art + span follow the construction shape/aspect, like the bars.
  previewGlow:SetTexture(GB.Skin:GlowArt() or shp.glow)   -- SDF-fallback proc bloom (non-hand shapes)
  previewRing:SetTexture(GB.Skin:AspectRing(pw, ph + maskExt) or shp.ring)
  anchorPreviewOverlay(previewRing, GB.Skin:StateWidthRatio())   -- spread tracks the Glow width control
  anchorPreviewOverlay(previewCD, 0, 0)                    -- swipe covers the whole pill
  -- Multi-part glow (hand shapes): mirror the bars' outer (under icon, grown by the
  -- border) / inner (over plate, +2px) art + per-axis anchor; SetPreviewState tints/shows.
  if hk then
    local bg = (style.border and style.border.enabled and (style.border.thickness or 0) > 0) and style.border.thickness or 0
    previewOuter:SetTexture(GB:HandAsset(hk, "outer")); handAnchor(previewOuter, bg)
    previewInner:SetTexture(GB:HandAsset(hk, "inner")); handAnchor(previewInner, 2)
  end
  -- Cooldown sweep traces the hand silhouette (its -swipe) on hand shapes, else the SDF
  -- swipe. Plate mode: the icon-half swipe (the CD chip tracks previewIcon = the square).
  local swipePart = previewPlateOn and ((plateSide == "bottom") and "swipe-b" or "swipe-t") or "swipe"
  if previewCD.SetSwipeTexture then previewCD:SetSwipeTexture((hk and GB:HandAsset(hk, swipePart)) or GB.Skin:AspectSwipe(pw, ph + maskExt) or shp.swipe) end

  -- Gradient plate layers — mirror Skin.ApplyDecor's directional renderer. Each
  -- layer is a shape-masked (continuous) or square (off) fade; when an extension
  -- lies on the solid edge, a flat SOLID zone is drawn through it first (the
  -- "plate" look), then the fade travels from that edge across the icon.
  previewPlateFresh = false
  local function plateMask(plate)
    if plate.mask then plate.tex:RemoveMaskTexture(plate.mask); plate.mask = nil end
    if not continuous then return end                     -- square plate (crisp junction)
    local m = previewFrame:CreateMaskTexture()
    m:SetTexture(maskSrc or shp.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if hk then
      handAnchor(m, 0)
    else
      m:ClearAllPoints()
      m:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", -growX, growY + mExtT)
      m:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", growX, -(growY + mExtB))
    end
    plate.tex:AddMaskTexture(m)
    plate.mask = m
  end
  local used = 0
  -- Plate mode draws its OWN fill + gradient and skips the decoration layers,
  -- exactly like the engine (ApplyDecor's plate blocks).
  if previewPlateOn then
    local pd = plateData()
    local pc = (pd and pd.color) or { 0.1, 0.1, 0.13 }
    local fadeStart = (pd and pd.fadeStart) or 0.5
    -- Fill: the solid square half OPPOSITE the icon, clipped by the silhouette mask.
    used = used + 1
    local fill = getPreviewPlate(used); plateMask(fill)
    local e = (plateSide == "bottom") and "TOP" or "BOTTOM"
    fill.tex:ClearAllPoints()
    fill.tex:SetPoint(e, previewFrame, e, 0, 0); fill.tex:SetSize(pw, pw)
    local fc = CreateColor(pc[1], pc[2], pc[3], 1)
    fill.tex:SetGradient("VERTICAL", fc, fc)   -- solid (clears any pooled gradient)
    fill.tex:Show()
    -- Gradient: opaque at the midline, fading across fadeStart of the icon half.
    used = used + 1
    local grad = getPreviewPlate(used); plateMask(grad)
    local fromC, toC = CreateColor(pc[1], pc[2], pc[3], 1), CreateColor(pc[1], pc[2], pc[3], 0)
    grad.tex:ClearAllPoints(); grad.tex:SetHeight(math.max(0.01, pw * fadeStart))
    if plateSide == "bottom" then   -- icon in the BOTTOM half → opaque at its TOP, fading DOWN
      grad.tex:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", 0, 0); grad.tex:SetPoint("TOPRIGHT", previewIcon, "TOPRIGHT", 0, 0)
      grad.tex:SetGradient("VERTICAL", toC, fromC)
    else                            -- icon in the TOP half → opaque at its BOTTOM, fading UP
      grad.tex:SetPoint("BOTTOMLEFT", previewIcon, "BOTTOMLEFT", 0, 0); grad.tex:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", 0, 0)
      grad.tex:SetGradient("VERTICAL", fromC, toC)
    end
    grad.tex:Show()
  end
  for _, layer in ipairs((not previewPlateOn and style.layers) or {}) do
    if layer.enabled ~= false and layer.kind == "gradient" then
      local c = layer.color or { 1, 1, 1 }
      local fromC = CreateColor(c[1], c[2], c[3], layer.fromAlpha or 1)
      local toC = CreateColor(c[1], c[2], c[3], layer.toAlpha or 0)
      local dir = layer.dir or "up"
      local reach = layer.bleedPct or 0.5                 -- fraction of the icon the fade spans
      if dir == "left" or dir == "right" then
        local solidRight = (dir == "left")                -- fades left ⇒ solid on the right
        local edge = solidRight and "RIGHT" or "LEFT"
        used = used + 1
        local fade = getPreviewPlate(used); plateMask(fade)
        fade.tex:ClearAllPoints()
        fade.tex:SetPoint("TOP" .. edge, previewIcon, "TOP" .. edge, 0, previewExtT)
        fade.tex:SetPoint("BOTTOM" .. edge, previewIcon, "BOTTOM" .. edge, 0, -previewExtB)
        fade.tex:SetWidth(math.max(0.01, pw * reach))
        if solidRight then fade.tex:SetGradient("HORIZONTAL", toC, fromC)
        else fade.tex:SetGradient("HORIZONTAL", fromC, toC) end
        fade.tex:Show()
      else
        local solidBottom = (dir == "up")
        local edge = solidBottom and "BOTTOM" or "TOP"
        local extAligned = ext > 0 and ((solidBottom and not above) or (not solidBottom and above))
        if extAligned then
          used = used + 1
          local solid = getPreviewPlate(used); plateMask(solid)
          local outward = solidBottom and -ext or ext
          solid.tex:ClearAllPoints()
          solid.tex:SetPoint(edge .. "LEFT", previewIcon, edge .. "LEFT", 0, outward)
          solid.tex:SetPoint(edge .. "RIGHT", previewIcon, edge .. "RIGHT", 0, outward)
          solid.tex:SetHeight(ext)
          solid.tex:SetGradient("VERTICAL", fromC, fromC)
          solid.tex:Show()
        end
        used = used + 1
        local fade = getPreviewPlate(used); plateMask(fade)
        fade.tex:ClearAllPoints()
        fade.tex:SetPoint(edge .. "LEFT", previewIcon, edge .. "LEFT", 0, 0)
        fade.tex:SetPoint(edge .. "RIGHT", previewIcon, edge .. "RIGHT", 0, 0)
        fade.tex:SetHeight(math.max(0.01, ph * reach))
        if solidBottom then fade.tex:SetGradient("VERTICAL", fromC, toC)
        else fade.tex:SetGradient("VERTICAL", toC, fromC) end
        fade.tex:Show()
      end
    end
  end
  for i = used + 1, #previewPlates do previewPlates[i].tex:Hide() end

  -- Border — a colored shape-copy behind the icon, oversized by `thickness` and
  -- (like the engine) framing the whole masked construction. Fresh mask per
  -- refresh (cheap; dodges the live-mask re-render quirk).
  local bd = style.border
  if bd and bd.enabled and (bd.thickness or 0) > 0 then
    local t, col = bd.thickness, bd.color or { 0, 0, 0 }
    local a = bd.alpha or 1
    previewBorder:ClearAllPoints()
    previewBorder:SetPoint("TOPLEFT", sref, "TOPLEFT", -t, t + mExtT)
    previewBorder:SetPoint("BOTTOMRIGHT", sref, "BOTTOMRIGHT", t, -(mExtB + t))
    if bd.color2 then
      local c2 = bd.color2
      local orient = (bd.gradDir == "left" or bd.gradDir == "right") and "HORIZONTAL" or "VERTICAL"
      local g1 = CreateColor(col[1], col[2], col[3], (col[4] or 1) * a)
      local g2 = CreateColor(c2[1], c2[2], c2[3], (c2[4] or 1) * a)
      if bd.gradDir == "down" or bd.gradDir == "left" then previewBorder:SetGradient(orient, g2, g1)
      else previewBorder:SetGradient(orient, g1, g2) end
    else
      previewBorder:SetVertexColor(col[1], col[2], col[3], (col[4] or 1) * a)
    end
    if previewBorderMask then previewBorder:RemoveMaskTexture(previewBorderMask) end
    previewBorderMask = previewFrame:CreateMaskTexture()
    previewBorderMask:SetTexture(maskSrc or shp.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if hk then
      handAnchor(previewBorderMask, t)
    else
      local gx, gy = (pw + 2 * t) * GROW_RATIO, (ph + maskExt + 2 * t) * GROW_RATIO
      previewBorderMask:ClearAllPoints()
      previewBorderMask:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", -(t + gx), (t + gy) + mExtT)
      previewBorderMask:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", (t + gx), -(mExtB + t + gy))
    end
    previewBorder:AddMaskTexture(previewBorderMask)
    previewBorder:Show()
  else
    previewBorder:Hide()
  end

  -- Cast/channel fill preview: the frame spans the shape rect exactly (a draining
  -- rectangle — the mask does the shaping, same rule as the bars' fill); fresh
  -- same-frame mask per refresh (the border's pattern). The chip's very first
  -- show gets a one-frame retry from SetPreviewState (never-rendered quirk §2).
  if previewCastFillFrame then
    local pfl = previewCastFillFrame
    pfl:ClearAllPoints()
    pfl:SetPoint("TOPLEFT", sref, "TOPLEFT", 0, 0)
    pfl:SetPoint("BOTTOMRIGHT", sref, "BOTTOMRIGHT", 0, 0)
    if pfl.mask then pfl.tex:RemoveMaskTexture(pfl.mask) end
    pfl.mask = pfl:CreateMaskTexture()
    pfl.mask:SetTexture(maskSrc or shp.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if hk then
      handAnchor(pfl.mask, 0)
    else
      pfl.mask:ClearAllPoints()
      pfl.mask:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", -growX, growY + mExtT)
      pfl.mask:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", growX, -(growY + mExtB))
    end
    pfl.tex:AddMaskTexture(pfl.mask)
  end

  -- Caption tucks just below the construction (below the plate when it extends
  -- downward) so it never sits under the plate: bold state heading, body under it
  -- (an empty heading has zero height, so the default caption sits at the top).
  if previewCaption and previewCaptionHead then
    local pane2 = previewFrame:GetParent()
    previewCaptionHead:ClearAllPoints()
    previewCaptionHead:SetPoint("TOP", previewFrame, "BOTTOM", 0, -(previewExtB + 26))   -- breathing room under the construction (Jason)
    previewCaptionHead:SetPoint("LEFT", pane2, "LEFT", 10, 0)
    previewCaptionHead:SetPoint("RIGHT", pane2, "RIGHT", -10, 0)
    previewCaption:ClearAllPoints()
    previewCaption:SetPoint("TOP", previewCaptionHead, "BOTTOM", 0, -3)
    previewCaption:SetPoint("LEFT", pane2, "LEFT", 10, 0)
    previewCaption:SetPoint("RIGHT", pane2, "RIGHT", -10, 0)
    if previewCaptionLinks then
      previewCaptionLinks:ClearAllPoints()
      previewCaptionLinks:SetPoint("TOP", previewCaption, "BOTTOM", 0, -8)
      previewCaptionLinks:SetPoint("LEFT", pane2, "LEFT", 10, 0)
      previewCaptionLinks:SetPoint("RIGHT", pane2, "RIGHT", -10, 0)
    end
  end

  -- A plate texture created THIS frame hasn't rendered, so its first
  -- AddMaskTexture silently failed (never-rendered quirk, API-NOTES §2) → retry
  -- once next frame, by when it has drawn and accepts the mask.
  if previewPlateFresh and not previewRetryPending then
    previewRetryPending = true
    C_Timer.After(0, function()
      previewRetryPending = nil
      if panel and panel:IsShown() then C:RefreshPreview() end
    end)
  end
end

function C:PreviewZoom(v)
  if previewIcon then
    previewIcon:SetTexCoord(GB.Skin:TexCoordFor(previewIcon:GetWidth(), previewIcon:GetHeight()))
  end
end

-- Replay the shaped finish flash on the preview (so its colour/shape is visible
-- without waiting for a real cooldown to end). Uses the same art + sizing as the
-- engine's playFinishFlash. No-op when the flash is disabled.
-- Shared burst player: the expanding flash tinted `c` — the cooldown finish flash
-- and the cast/channel COMPLETE burst both use it, differing only by colour.
-- Mirrors the bars' playFinishFlash: hand shapes use the shape's own -outer glow
-- art on the hand-canvas anchor (the art's silhouette occupies the centre half of
-- its canvas → margins of half the short side land its edge ON the shape edge);
-- the legacy SDF path keeps the old bloom + uniform grow.
local function playPreviewBurst(c)
  if not (previewFlash and previewIcon) then return end
  local hk = GB.db and GB.db.handShape
  previewFlash:SetTexture(hk and GB:HandAsset(hk, "outer") or GB.Skin:GlowArt())
  previewFlash:SetVertexColor(c[1], c[2], c[3])
  if hk then
    -- Plate mode spans the full 2:1 construction (the bars trace constructRef).
    local ref = previewPlateOn and previewFrame or previewIcon
    local m0 = 0.5 * math.min(previewFrame:GetWidth(), previewFrame:GetHeight())
    previewFlashFrame:ClearAllPoints()
    previewFlashFrame:SetPoint("TOPLEFT", ref, "TOPLEFT", -m0, m0)
    previewFlashFrame:SetPoint("BOTTOMRIGHT", ref, "BOTTOMRIGHT", m0, -m0)
  else
    anchorPreviewOverlay(previewFlashFrame, (128 / 80 - 1) / 2)
  end
  previewFlashFrame:SetAlpha(1)
  previewFlashAnim:Stop(); previewFlashAnim:Play()
end
function C:PlayPreviewFlash()
  if not (GB.db and GB.db.finishFlash) then return end
  playPreviewBurst(GB.db.finishFlashColor or { 1, 0.9, 0.5 })
end
-- (No cast-complete burst in the preview: the real one is Blizzard's EndBurst
-- animation replayed inside their widget — not reproducible faithfully here.)

-- Multi-part preview glow: for a hand shape, every glow-trigger chip (proc /
-- highlight / assist / cast / channel / hover / selected / flash) shows the real
-- outer+inner glow tinted by that trigger's colour / opacity / layers
-- (art + anchor set in RefreshPreview). Respects `enabled` (off → blank chip).
local GLOW_STATES = { proc = true, highlight = true, assist = true, cast = true,
  channel = true, hover = true, selected = true, flash = true }
local PREVIEW_PULSING = { proc = true, flash = true, assist = true, highlight = true }   -- mirror the bars' PULSING
local function applyPreviewGlow(key)
  local t = (GB.db and GB.db.triggers and GB.db.triggers[key]) or {}
  if t.enabled == false then previewOuter:Hide(); previewInner:Hide(); previewPulsing = false; return end
  local c = t.color or { 1, 0.85, 0.35 }
  local a = math.max(0.35, t.opacity or 0.9)
  local layers = t.layers or "both"
  previewOuter:SetVertexColor(c[1], c[2], c[3]); previewOuter:SetAlpha(a)
  previewInner:SetVertexColor(c[1], c[2], c[3]); previewInner:SetAlpha(a)
  previewOuter:SetShown(layers ~= "inner")
  previewInner:SetShown(layers ~= "outer")
  previewPulsing, previewPulsePeak = PREVIEW_PULSING[key] or false, a   -- the OnUpdate breathes it
end

function C:SetPreviewState(st)
  previewState = st or "idle"
  local hk = GB.db and GB.db.handShape
  local glowState = GLOW_STATES[previewState]
  -- Hand shape (the norm): drive the multi-part glow chips; hide the SDF bloom/ring.
  if previewOuter and previewInner then
    if hk and glowState then applyPreviewGlow(previewState)
    else previewOuter:Hide(); previewInner:Hide(); previewPulsing = false end
  end
  -- SDF fallback (non-hand): the single soft bloom (proc) + ring (states).
  if previewGlow then
    previewGlow:SetShown((not hk) and previewState == "proc")
    if (not hk) and previewState == "proc" and previewIcon then
      local pt = (GB.db and GB.db.triggers and GB.db.triggers.proc) or {}
      local c = pt.color or { 1, 0.85, 0.35 }
      local sc = (GB.db and GB.db.glowScale) or (128 / 80)
      anchorPreviewOverlay(previewGlow, (sc - 1) / 2)
      previewGlow:SetVertexColor(c[1], c[2], c[3])
      previewGlow:SetAlpha(math.max(0.35, pt.opacity or 0.9))
    end
  end
  if previewCD then
    if previewState == "cooldown" then
      -- Reflect the sweep tint / opacity via the same engine path the bars use.
      if GB.Skin and GB.Skin.StyleCooldown then GB.Skin:StyleCooldown(previewCD) end
      previewCD:Show(); previewCD:SetCooldown(GetTime(), 12)
    else previewCD:Hide() end
  end
  -- Cast / Channel chips: run the looping fake drain (colour / alpha / direction
  -- from the same db fields the bars read — edits in Cast & channel show live).
  if previewCastFillFrame then
    if previewState == "cast" or previewState == "channel" then
      local f = previewCastFillFrame
      f.channel = (previewState == "channel")
      local col = (GB.db and GB.db.castFillColor) or { 1, 0.85, 0.4 }
      local a = (GB.db and GB.db.castFillAlpha) or 0.55
      f.tex:SetVertexColor(col[1], col[2], col[3], a)
      f.tex:Show(); f:Show()
      if not f.everShown then
        -- Very first show: the tex had never rendered, so RefreshPreview's mask
        -- attach silently failed (§2) — re-attach one frame later.
        f.everShown = true
        C_Timer.After(0, function()
          if panel and panel:IsShown() then local st = previewState; C:RefreshPreview(); C:SetPreviewState(st) end
        end)
      end
    else
      previewCastFillFrame:Hide()
    end
  end
  -- Icon tint: the availability chips mirror the engine's computeIconTint (range =
  -- desaturate + wash; oom / unusable = the configured vertex tint — same db fields
  -- the bars read); cooldown keeps its desaturated look; everything else full colour.
  if previewIcon then
    local adb = GB.db or {}
    if previewState == "range" then
      local c = adb.rangeColor or { 1, 0.2, 0.2 }
      previewIcon:SetDesaturated(true); previewIcon:SetVertexColor(c[1], c[2], c[3])
    elseif previewState == "oom" then
      local c = adb.availOOM or { 0.5, 0.5, 1 }
      previewIcon:SetDesaturated(false); previewIcon:SetVertexColor(c[1], c[2], c[3])
    elseif previewState == "unusable" then
      local c = adb.availUnusable or { 0.4, 0.4, 0.4 }
      previewIcon:SetDesaturated(adb.availDesaturate and true or false)
      previewIcon:SetVertexColor(c[1], c[2], c[3])
    else
      previewIcon:SetDesaturated(previewState == "cooldown")
      previewIcon:SetVertexColor(1, 1, 1)
    end
  end
  local isRing = RING_TINT[previewState] ~= nil
  if previewRing then
    previewRing:SetShown((not hk) and isRing)
    if (not hk) and isRing then
      local rt = GB.db and GB.db.triggers and GB.db.triggers[previewState]
      local c = (rt and rt.color) or RING_TINT[previewState]
      previewRing:SetVertexColor(c[1], c[2], c[3])
      previewRing:SetAlpha((rt and rt.opacity) or 1)
    end
  end
  -- Glow chips don't show animations; the Animations section re-adds them via
  -- SetPreviewAnim. Clear any preview animation by default so they don't linger.
  if GB.Anims and previewFrame then GB.Anims:PreviewReconcile(previewFrame, previewPlateOn and previewFrame or previewIcon, GB.db and GB.db.handShape, nil) end
  for s2, chip in pairs(previewChips) do chip:SetActive(s2 == previewState) end
  -- Caption tracks whatever state is previewed (top chips or a section). SetPreviewAnim
  -- runs after this and overrides with the animation trigger's own description.
  setCaption(STATE_DESC[previewState])
end

-- Preview the selected trigger's glow (its chip, or idle) PLUS its enabled animations
-- on the preview host — the live-feedback surface for the Animations section.
-- Every animation trigger has a matching state chip now (session 12).
function C:SetPreviewAnim(triggerKey)
  self:SetPreviewState(triggerKey or "idle")
  if GB.Anims and previewFrame and previewIcon then
    local trigger = GB.db and GB.db.triggers and GB.db.triggers[triggerKey]
    -- Plate mode: animations span the full 2:1 construction (the bars' ConstructRef).
    GB.Anims:PreviewReconcile(previewFrame, previewPlateOn and previewFrame or previewIcon, GB.db and GB.db.handShape, trigger)
  end
  setCaption(STATE_DESC[triggerKey])
end

-- Animations — the per-trigger animation system (GB.Anims). Pick a trigger, then
-- enable/configure each registered animation module (shine, and future march/sheen/…)
-- for it. Params are generated from each module's schema, so new modules get a UI for
-- free. The preview host runs the selected trigger's enabled animations live.
local ANIM_TRIGGERS = {
  { "proc", "Proc" }, { "highlight", "Highlight" }, { "cast", "Cast" }, { "channel", "Channel" },
  { "hover", "Hover" }, { "selected", "Selected" }, { "flash", "Flash" }, { "assist", "Assist" },
}
local animTrigger = "proc"   -- which trigger the section is currently editing

local function animData(id)   -- saved params for the selected trigger's animation `id` (nil until created)
  local t = GB.db and GB.db.triggers and GB.db.triggers[animTrigger]
  return t and t.anims and t.anims[id]
end
local function animEnsure(id)   -- create the saved table from the module defaults (enabled = false)
  local t = GB.db and GB.db.triggers and GB.db.triggers[animTrigger]
  if not t then return nil end
  t.anims = t.anims or {}
  if not t.anims[id] then
    local mod = GB.Anims and GB.Anims:Get(id)
    local d = { enabled = false }
    if mod then for k, v in pairs(mod.defaults) do d[k] = (type(v) == "table") and { v[1], v[2], v[3], v[4] } or v end end
    t.anims[id] = d
  end
  return t.anims[id]
end
local function animDefault(id, key) local m = GB.Anims and GB.Anims:Get(id); return m and m.defaults[key] end
local function animGet(id, key) local d = animData(id); if d and d[key] ~= nil then return d[key] end; return animDefault(id, key) end
local function animSet(id, key, v) local d = animEnsure(id); if d then d[key] = v end end
local function animFmt(p)
  if p.fmt == "int" then return function(v) return tostring(math.floor(v + 0.5)) end end
  if p.fmt == "secs" then return function(v) return string.format("%.1fs", v) end end
  return function(v) return string.format("%.1f", v) end
end

-- One param control (from a module's schema). Returns { h, refresh, setEnabled, setShown }.
local function animParamRow(bf, yTop, id, param, onChange)
  if param.kind == "color" then
    local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 30, yTop); lab:SetText(param.label)
    local cs = colorSwatch(bf, function() return animGet(id, param.key) end,
      function(c) animSet(id, param.key, c); onChange() end)
    cs.swatch:SetPoint("TOPRIGHT", -18, yTop + 1)
    return { h = 30, refresh = function() cs:refresh() end,
      setEnabled = function(on) cs.swatch:SetEnabled(on); cs.swatch:SetAlpha(on and 1 or 0.4); lab:SetAlpha(on and 1 or 0.4) end,
      setShown = function(on) lab:SetShown(on); cs.swatch:SetShown(on) end }
  elseif param.kind == "range" then
    local row = sliderRow(bf, yTop, param.label, param.min, param.max, param.step,
      function() return animGet(id, param.key) end,
      function(v) animSet(id, param.key, v); onChange() end, animFmt(param))
    return { h = 44, refresh = function() row:refresh() end, setEnabled = function(on) row:setEnabled(on) end,
      setShown = function(on) row:SetShown(on) end }
  elseif param.kind == "bispeed" then
    -- One signed slider: centre = still, right half = faster (posLabel), left half = faster
    -- (negLabel). Value = velocity in [-1,1]; |v| = 1 is param.minRev sec/rev. Direction
    -- labels default to CCW/CW (rotation) but a module can override (e.g. Sheen's L/R sweep).
    local minRev = param.minRev or 0.8
    local negLabel, posLabel = param.neg or "CCW", param.pos or "CW"
    local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 30, yTop); lab:SetText(param.label)
    local val = newText(bf, FONT.label, 11, TEXT, "RIGHT"); val:SetPoint("TOPRIGHT", -18, yTop)
    local lccw = newText(bf, FONT.body, 9.5, MUTE, "LEFT"); lccw:SetPoint("TOPLEFT", 18, yTop - 32); lccw:SetText(negLabel)
    local lcw = newText(bf, FONT.body, 9.5, MUTE, "RIGHT"); lcw:SetPoint("TOPRIGHT", -18, yTop - 32); lcw:SetText(posLabel)
    local sl = CreateFrame("Slider", nil, bf)
    sl:SetPoint("TOPLEFT", 18, yTop - 18); sl:SetPoint("TOPRIGHT", -18, yTop - 18); sl:SetHeight(16)
    sl:EnableMouse(true); sl:SetOrientation("HORIZONTAL"); sl:SetMinMaxValues(-1, 1); sl:SetValueStep(0.05); sl:SetObeyStepOnDrag(true)
    local track = sl:CreateTexture(nil, "BACKGROUND"); track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(6)
    track:SetColorTexture(COLOR.heroic.r, COLOR.heroic.g, COLOR.heroic.b, 0.20)
    local tick = sl:CreateTexture(nil, "ARTWORK"); tick:SetSize(2, 12); tick:SetPoint("CENTER"); tick:SetColorTexture(1, 1, 1, 0.28)
    local thumb = sl:CreateTexture(nil, "ARTWORK"); thumb:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1)
    thumb:SetSize(5, 20); sl:SetThumbTexture(thumb)
    local applying = false
    local function show(v)
      if math.abs(v) < 0.04 then val:SetText("still")
      else val:SetText(string.format("%s %.1fs", v > 0 and posLabel or negLabel, minRev / math.abs(v))) end
    end
    sl:SetScript("OnValueChanged", function(_, v) if not applying then animSet(id, param.key, v); onChange() end; show(v) end)
    local function seek(self)
      local left, w = self:GetLeft(), self:GetWidth()
      if not (left and w and w > 0) then return end
      local frac = math.max(0, math.min(1, (GetCursorPosition() / self:GetEffectiveScale() - left) / w))
      self:SetValue(math.floor((-1 + frac * 2) / 0.05 + 0.5) * 0.05)
    end
    sl:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self._seek = true; seek(self) end end)
    sl:SetScript("OnMouseUp", function(self) self._seek = false end)
    sl:SetScript("OnUpdate", function(self)
      if self._seek then if self:IsEnabled() and IsMouseButtonDown("LeftButton") then seek(self) else self._seek = false end end
    end)
    return { h = 50,
      refresh = function() applying = true; local v = animGet(id, param.key) or 0; sl:SetValue(v); show(v); applying = false end,
      setEnabled = function(on)
        sl:SetEnabled(on); sl:SetAlpha(on and 1 or 0.35)
        for _, t in ipairs({ lab, val, lccw, lcw }) do t:SetAlpha(on and 1 or 0.4) end
      end,
      setShown = function(on) for _, t in ipairs({ lab, val, lccw, lcw, sl }) do t:SetShown(on) end end }
  elseif param.kind == "choice" then
    local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 30, yTop); lab:SetText(param.label)
    local btns, prev = {}, nil
    for i = #param.choices, 1, -1 do
      local ch = param.choices[i]
      local b = flatButton(bf, 46, 20, COLOR.heroic, ch[2], 11)
      if prev then b:SetPoint("TOPRIGHT", prev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, yTop + 1) end
      b:SetScript("OnClick", function() animSet(id, param.key, ch[1]); for _, e in ipairs(btns) do e.b:SetActive(e.v == ch[1]) end; onChange() end)
      btns[#btns + 1] = { b = b, v = ch[1] }; prev = b
    end
    return { h = 28,
      refresh = function() local cur = animGet(id, param.key); for _, e in ipairs(btns) do e.b:SetActive(e.v == cur) end end,
      setEnabled = function(on) for _, e in ipairs(btns) do e.b:SetEnabled(on) end; lab:SetAlpha(on and 1 or 0.4) end,
      setShown = function(on) lab:SetShown(on); for _, e in ipairs(btns) do e.b:SetShown(on) end end }
  end
  return { h = 0, refresh = function() end, setEnabled = function() end, setShown = function() end }
end

-- A generic dropdown flyout (short lists, no scroll) — options = { {value,label}, .. }.
-- Modelled on the font flyout: a full-screen catcher closes it on any outside click.
local animFlyout
local function animFlyoutFrame()
  if animFlyout then return animFlyout end
  local catcher = CreateFrame("Button", nil, panel)
  catcher:SetFrameStrata("FULLSCREEN"); catcher:SetAllPoints(UIParent); catcher:Hide()
  local fly = CreateFrame("Frame", nil, catcher)
  fly:SetFrameStrata("FULLSCREEN_DIALOG"); skinPlate(fly); addEdges(fly, COLOR.rim, 1)
  catcher:SetScript("OnClick", function() catcher:Hide() end)
  fly.catcher, fly.rows = catcher, {}
  animFlyout = fly
  return fly
end
local function openAnimFlyout(anchor, options, current, onPick)
  local fly = animFlyoutFrame()
  local ROW_H, y = 22, -3
  for i, opt in ipairs(options) do
    local row = fly.rows[i]
    if not row then
      row = CreateFrame("Button", nil, fly); row:SetHeight(ROW_H)
      row.hl = row:CreateTexture(nil, "BACKGROUND"); row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 1, 1, 0.07); row.hl:Hide()
      row:SetScript("OnEnter", function(self) self.hl:Show() end)
      row:SetScript("OnLeave", function(self) self.hl:Hide() end)
      row.text = newText(row, FONT.body, 12, TEXT, "LEFT"); row.text:SetPoint("LEFT", 8, 0); row.text:SetPoint("RIGHT", -8, 0); row.text:SetWordWrap(false)
      fly.rows[i] = row
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 3, y); row:SetPoint("TOPRIGHT", -3, y)
    row.text:SetText(opt.label)
    if opt.value == current then row.text:SetTextColor(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b) else row.text:SetTextColor(1, 1, 1) end
    row:SetScript("OnClick", function() fly.catcher:Hide(); onPick(opt.value) end)
    row:Show()
    y = y - ROW_H
  end
  for i = #options + 1, #fly.rows do fly.rows[i]:Hide() end
  fly:SetSize(math.max(anchor:GetWidth(), 150), #options * ROW_H + 6)
  fly:ClearAllPoints(); fly:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  fly.catcher:Show()
end
local function animDropdown(parent, w, getLabel, getOptions, getCurrent, onPick)
  local b = flatButton(parent, w, 22, COLOR.heroic, "", 11); b:SetBase(0.2); b.text:SetWordWrap(false)
  -- Inset the label so long names truncate (…) instead of running under the
  -- caret (Jason: "Gloomfury - Stormrage" collided). Justify stays centered.
  b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -18, 0); b.text:SetJustifyH("CENTER")
  local car = b:CreateTexture(nil, "ARTWORK"); car:SetTexture(CARET_TEX)   -- ▾ down-caret (same asset as the accordion)
  car:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b)
  car:SetSize(8, 8); car:SetPoint("RIGHT", -8, 0); car:SetRotation(CARET_DOWN)
  function b:refresh() self.text:SetText(getLabel()) end
  b:SetScript("OnClick", function() openAnimFlyout(b, getOptions(), getCurrent(), function(v) onPick(v); b:refresh() end) end)
  b:refresh()
  return b
end

-- Animations section: State chips -> Animation dropdown (one per state, or None) -> the
-- selected animation's params. Params for each module are pre-built (hidden) at the same
-- spot; only the chosen module's set is shown. Each state's params are independent (they
-- read/write GB.db.triggers[animTrigger].anims[id]).
local function buildAnimsSection(bf, s)
  local chips, blocks, dd = {}, {}, nil
  local function apply() C:SetPreviewAnim(animTrigger); if GB.Anims then GB.Anims:Invalidate(animTrigger) end end

  local function currentSel()
    local t = GB.db and GB.db.triggers and GB.db.triggers[animTrigger]
    local found = "none"
    if t and t.anims and GB.Anims then
      GB.Anims:Each(function(mod) if t.anims[mod.id] and t.anims[mod.id].enabled then found = mod.id end end)
    end
    return found
  end
  local function options()
    local o = { { value = "none", label = "None" } }
    if GB.Anims then GB.Anims:Each(function(mod) o[#o + 1] = { value = mod.id, label = mod.label } end) end
    return o
  end
  local function labelFor(v) if v == "none" or not v then return "None" end local m = GB.Anims and GB.Anims:Get(v); return (m and m.label) or "None" end

  -- State chips (onClick assigned once selectTrigger exists, below).
  local st = newText(bf, FONT.body, 11, MUTE, "LEFT"); st:SetPoint("TOPLEFT", 18, -12); st:SetText("State")
  local cx, cy = 18, -30
  for i, tr in ipairs(ANIM_TRIGGERS) do
    local b = flatButton(bf, 58, 20, COLOR.heroic, tr[2], 11); b:SetPoint("TOPLEFT", cx, cy)
    chips[#chips + 1] = { b = b, k = tr[1] }
    cx = cx + 62; if i == 4 then cx, cy = 18, cy - 24 end
  end

  local ddLab = newText(bf, FONT.body, 12, TEXT, "LEFT"); ddLab:SetPoint("TOPLEFT", 18, -84); ddLab:SetText("Animation")

  -- Param blocks (one per module), all anchored at PARAM_Y, hidden until selected. Each
  -- records its own bottom so the section can size to JUST the selected module.
  local PARAM_Y = -118
  if GB.Anims then
    GB.Anims:Each(function(mod)
      local prs, y = {}, PARAM_Y
      for _, param in ipairs(mod.params) do local pr = animParamRow(bf, y, mod.id, param, apply); prs[#prs + 1] = pr; y = y - pr.h end
      blocks[mod.id] = {
        bottom = y,
        setShown = function(on) for _, pr in ipairs(prs) do pr.setShown(on) end end,
        refresh = function() for _, pr in ipairs(prs) do pr.refresh(); pr.setEnabled(true) end end,
      }
      blocks[mod.id].setShown(false)
    end)
  end

  -- Size the section to the SELECTED module's params (None → tight under the dropdown), then
  -- reflow the accordion — no dead space below a short module (was fixed to the tallest one).
  local function heightFor(id)
    local blk = blocks[id]
    return -((blk and blk.bottom) or (PARAM_Y + 8)) + 16
  end
  local function setSectionHeight(id) bf:SetHeight(heightFor(id)); relayout() end

  local function selectAnim(v)
    local t = GB.db and GB.db.triggers and GB.db.triggers[animTrigger]
    if not t then return end
    t.anims = t.anims or {}
    if GB.Anims then GB.Anims:Each(function(mod)
      if mod.id == v then local d = animEnsure(mod.id); if d then d.enabled = true end
      elseif t.anims[mod.id] then t.anims[mod.id].enabled = false end
    end) end
    for id, blk in pairs(blocks) do blk.setShown(id == v) end
    if blocks[v] then blocks[v].refresh() end
    setSectionHeight(v)
    apply()
  end

  dd = animDropdown(bf, 168, function() return labelFor(currentSel()) end, options, currentSel, selectAnim)
  dd:SetPoint("TOPRIGHT", -18, -84)

  local function refreshForTrigger()
    dd:refresh()
    local cur = currentSel()
    for id, blk in pairs(blocks) do blk.setShown(id == cur) end
    if blocks[cur] then blocks[cur].refresh() end
    setSectionHeight(cur)
    C:SetPreviewAnim(animTrigger)
  end
  local function selectTrigger(k) animTrigger = k; for _, c in ipairs(chips) do c.b:SetActive(c.k == k) end; refreshForTrigger() end
  for _, c in ipairs(chips) do c.b:SetScript("OnClick", function() selectTrigger(c.k) end) end

  bf:SetHeight(heightFor(currentSel()))   -- initial; runtime changes go through setSectionHeight
  s.refresh = function()
    for _, c in ipairs(chips) do c.b:SetActive(c.k == animTrigger) end
    refreshForTrigger()
  end
end

-- Profiles — profile picker (per-character active, account-wide library) +
-- preset picker (the whole-look every section below edits). Presets AUTO-SAVE:
-- the edit preset is a live document — switching preset/profile snapshots the
-- outgoing look first (Core SwitchPreset/SetActiveProfile), logout too — so
-- there is no Save button. Per-bar assignment arrives with Apply to bars.
-- Left rail (session 14): profile + preset selection, ALWAYS visible.
-- Replaced the old "Profiles" accordion section — the profile and preset decide
-- what every other control edits, so they live outside the accordion, never
-- hidden. Management (new/copy/rename/delete) lives here too.
local function buildRailPane(parent)
  local rail = CreateFrame("Frame", nil, parent)
  rail:SetPoint("TOPLEFT", 0, TITLE_DIV_Y - 1)
  rail:SetPoint("BOTTOMLEFT", 0, FOOTER_H)
  rail:SetWidth(RAIL_W)

  local function sortedNames(t)
    local o = {}
    for name in pairs(t or {}) do o[#o + 1] = { value = name, label = name } end
    table.sort(o, function(a, b) return a.label < b.label end)
    return o
  end
  local function profNames() return sortedNames(GB.db and GB.db.profiles) end
  local function presetNames() local prof = GB:ActiveProfile(); return sortedNames(prof and prof.presets) end
  local function editName() local prof = GB:ActiveProfile(); return (prof and prof.edit) or "?" end

  local railRefresh   -- fwd-declared upvalue; assigned once both dropdowns exist
  local msgLine       -- inline feedback (name taken / can't delete the last one)
  local function note(text) msgLine:SetText(text or "") end
  -- Two-click destructive confirm (no popup): first click arms, second fires.
  local function confirmable(b, label, fn)
    b:SetScript("OnClick", function()
      if b._armed then
        b._armed = nil; b:SetText(label); fn()
      else
        b._armed = true; b:SetText("Sure?")
        C_Timer.After(3, function() if b._armed then b._armed = nil; b:SetText(label) end end)
      end
    end)
  end

  local X, W = 14, RAIL_W - 28   -- content column inset + width
  local function railButton(x, y, w, label)
    local b = flatButton(rail, w, 20, COLOR.heroic, label, 11); b:SetBase(0.2)
    b:SetPoint("TOPLEFT", x, y)
    return b
  end

  -- PROFILE block.
  local ph = newText(rail, FONT.head, 12, MUTE, "LEFT"); ph:SetPoint("TOPLEFT", X, -12); ph:SetText("PROFILE")
  local pdd = animDropdown(rail, W,
    function() return GB:ActiveProfileName() or "?" end,
    profNames,
    function() return GB:ActiveProfileName() end,
    function(v) note(""); GB:SetActiveProfile(v); railRefresh() end)
  pdd:SetPoint("TOPLEFT", X, -30)

  local bw = (W - 4) / 2   -- 2×2 button grid
  local pNew  = railButton(X, -58, bw, "New")
  local pCopy = railButton(X + bw + 4, -58, bw, "Copy")
  local pRen  = railButton(X, -82, bw, "Rename")
  local pDel  = railButton(X + bw + 4, -82, bw, "Delete")
  pNew:SetScript("OnClick", function()
    OpenNameDialog("New profile", "", function(name)
      if name == "" then return end
      if GB:CreateProfile(name) then GB:SetActiveProfile(name); railRefresh()
      else note("A profile with that name already exists.") end
    end)
  end)
  pCopy:SetScript("OnClick", function()
    local active = GB:ActiveProfileName()
    OpenNameDialog("Copy profile", (active or "") .. " copy", function(name)
      if name == "" then return end
      if GB:CopyProfile(active, name) then GB:SetActiveProfile(name); railRefresh()
      else note("A profile with that name already exists.") end
    end)
  end)
  pRen:SetScript("OnClick", function()
    local active = GB:ActiveProfileName()
    OpenNameDialog("Rename profile", active or "", function(name)
      if name == "" then return end
      if GB:RenameProfile(active, name) then C:Refresh()
      else note("A profile with that name already exists.") end
    end)
  end)
  confirmable(pDel, "Delete", function()
    if not GB:DeleteProfile(GB:ActiveProfileName()) then note("Can't delete the last profile.") end
    C:Refresh()
  end)
  attachTip(pdd, "Profile", "The active profile for this character. Each character remembers its own; the profile library is shared account-wide.")
  attachTip(pNew, "New profile", "Creates a profile starting from the current look, and switches to it.")
  attachTip(pCopy, "Copy profile", "Duplicates this profile — presets, bar assignments and all — and switches to the copy.")
  attachTip(pRen, "Rename profile", "Renames this profile. Characters using it follow the new name.")
  attachTip(pDel, "Delete profile", "Deletes this profile (click twice to confirm). Characters using it fall back to another profile. The last profile can't be deleted.")

  local div = hLine(rail); div:SetPoint("TOPLEFT", X, -114); div:SetPoint("TOPRIGHT", -X, -114)

  -- PRESET block (the edit target).
  local sh = newText(rail, FONT.head, 12, MUTE, "LEFT"); sh:SetPoint("TOPLEFT", X, -126); sh:SetText("PRESET (BEING EDITED)")
  local sdd = animDropdown(rail, W,
    editName,
    presetNames,
    editName,
    function(v) note(""); GB:SwitchPreset(v); railRefresh() end)
  sdd:SetPoint("TOPLEFT", X, -144)

  local tw = (W - 8) / 3   -- 3-across button row
  local sNew = railButton(X, -172, tw, "New")
  local sRen = railButton(X + tw + 4, -172, tw, "Rename")
  local sDel = railButton(X + 2 * (tw + 4), -172, tw, "Delete")
  sNew:SetScript("OnClick", function()
    OpenNameDialog("New preset", "", function(name)
      if name == "" then return end
      if GB:CreatePreset(name) then railRefresh()
      else note("A preset with that name already exists.") end
    end)
  end)
  sRen:SetScript("OnClick", function()
    OpenNameDialog("Rename preset", editName(), function(name)
      if name == "" then return end
      if GB:RenamePreset(editName(), name) then C:Refresh()
      else note("A preset with that name already exists.") end
    end)
  end)
  confirmable(sDel, "Delete", function()
    if not GB:DeletePreset(editName()) then note("Can't delete the last preset.") end
    C:Refresh()
  end)
  attachTip(sdd, "Preset", "The look being edited — every control in the middle panel edits this preset, and it saves automatically as you edit. Picking another preset swaps the whole look.")
  attachTip(sNew, "New preset", "Creates a preset starting as a copy of the current look, and makes it the one being edited.")
  attachTip(sRen, "Rename preset", "Renames this preset. Bars assigned to it follow the new name.")
  attachTip(sDel, "Delete preset", "Deletes this preset (click twice to confirm). Bars assigned to it fall back to another preset. The last preset can't be deleted.")

  msgLine = newText(rail, FONT.body, 11, MUTE, "LEFT")
  msgLine:SetPoint("TOPLEFT", X, -200); msgLine:SetPoint("RIGHT", rail, "RIGHT", -X, 0); msgLine:SetJustifyH("LEFT")

  railRefresh = function() pdd:refresh(); sdd:refresh() end
  parent._railRefresh = railRefresh
end

-- Bar layout (phase L1+L2) — Gloom's Bars owns bar geometry PER BAR, opt-in;
-- Edit Mode keeps any bar left off. Engine: Layout.lua (containers only —
-- never the secure buttons; out-of-combat with a combat queue). Settings live
-- per bar in the PROFILE (barLayout[barKey]), beside the preset assignments.
local function barLayoutData(barKey)
  local prof = GB:ActiveProfile(); local t = prof and prof.barLayout; return t and t[barKey]
end
local function ensureBarLayout(barKey)
  local prof = GB:ActiveProfile(); if not prof then return nil end
  prof.barLayout = prof.barLayout or {}
  prof.barLayout[barKey] = prof.barLayout[barKey] or
    { size = 45, gap = 4, rows = 1, horizontal = true, count = 12 }
  return prof.barLayout[barKey]
end
local function layoutOn() local prof = GB:ActiveProfile(); return (prof and prof.layoutEnabled) or false end

local function buildLayoutSection(bf, s)
  local selBar = GB.BARS[1].buttonPrefix
  local chips = {}
  local selectBar   -- fwd-declared

  local function data() return barLayoutData(selBar) end
  local function apply() if GB.Layout then GB.Layout:Reassert(selBar) end end

  -- THE master switch (Jason: all-or-nothing — when on, this addon arranges
  -- ALL the bars with the per-bar settings below; when off, Edit Mode does).
  local olab = newText(bf, FONT.body, 12, TEXT, "LEFT"); olab:SetPoint("TOPLEFT", 18, -14); olab:SetText("Gloom's Bars layout")
  local own = makeToggle(bf, layoutOn,
    function(v)
      local prof = GB:ActiveProfile(); if prof then prof.layoutEnabled = v and true or false end
      if GB.Layout then GB.Layout:ApplyAll() end
      s.refresh()
    end)
  own:SetPoint("TOPRIGHT", -18, -12)
  attachTip(own, "Gloom's Bars layout", "On: this addon arranges ALL the bars, each with its settings below. Off: Edit Mode arranges everything, exactly as normal.")

  -- Bar chips (4-wide grid; 10 bars = 3 rows), pinging the real bar on hover
  -- (same QoL as Apply to bars). Numbered bars show "Bar N"; pet/stance show
  -- their name (they're bars 9-10 in GB.BARS but "Bar 9/10" would be wrong).
  local CHIP_ROWS = math.ceil(#GB.BARS / 4)
  for i, bar in ipairs(GB.BARS) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local label = bar.key:match("^bar(%d+)$") and ("Bar " .. bar.key:match("^bar(%d+)$")) or bar.label:gsub(" Bar$", "")
    local chip = flatButton(bf, 82, 22, COLOR.heroic, label, 11); chip:SetBase(0.2)
    chip:SetPoint("TOPLEFT", 18 + col * 88, -44 - row * 26)
    chip:SetScript("OnClick", function() selectBar(bar.buttonPrefix) end)
    chip:HookScript("OnEnter", function() if GB.Skin and GB.Skin.PingBar then GB.Skin:PingBar(bar.buttonPrefix, true) end end)
    chip:HookScript("OnLeave", function() if GB.Skin and GB.Skin.PingBar then GB.Skin:PingBar(bar.buttonPrefix, false) end end)
    attachTip(chip, bar.label, "Select this bar to edit its layout settings. Hovering pulses it on screen.")
    chips[#chips + 1] = { b = chip, k = bar.buttonPrefix }
  end

  -- Visibility (Jason: "I don't use all 8 bars" + Edit Mode's conditional
  -- modes): Default = Blizzard's rules; Always visible forces a bar Edit Mode
  -- disabled to appear; In/Out of combat use a secure state driver (the only
  -- legal way to flip a bar at combat edges); Hidden removes it.
  local VIS_OPTS = {
    { value = "default",  label = "Default" },
    { value = "show",     label = "Always visible" },
    { value = "combat",   label = "In combat" },
    { value = "nocombat", label = "Out of combat" },
    { value = "hide",     label = "Hidden" },
  }
  local function visValue() local c = data(); return (c and c.vis) or "default" end
  local function visLabel()
    local v = visValue()
    for _, o in ipairs(VIS_OPTS) do if o.value == v then return o.label end end
    return "Default"
  end
  -- Content below the chip grid is shifted down by the extra chip row (10 bars
  -- = 3 rows now that pet/stance are members, vs the 2 rows this section was
  -- laid out for) PLUS the Preset dropdown row folded in from the old "Apply to
  -- bars" section (Jason: assign a preset to the selected bar right here — no
  -- separate section). BY threads the shift through every fixed offset + reflow.
  local PRESET_ROW = 32
  local baseBY = (CHIP_ROWS - 2) * 26
  local BY = baseBY + PRESET_ROW

  -- Preset (folded in from "Apply to bars"): which whole-look preset the SELECTED
  -- bar wears. Sits in the row freed above Visibility (at the old pre-preset BY).
  local function presetOptions()
    local prof = GB:ActiveProfile(); local o = {}
    for name in pairs((prof and prof.presets) or {}) do o[#o + 1] = { value = name, label = name } end
    table.sort(o, function(a, b) return a.label < b.label end)
    return o
  end
  local plab = newText(bf, FONT.body, 12, TEXT, "LEFT"); plab:SetPoint("TOPLEFT", 18, -106 - baseBY); plab:SetText("Preset")
  local presetdd = animDropdown(bf, 150,
    function() local prof = GB:ActiveProfile(); return (prof and prof.bars and prof.bars[selBar]) or "?" end,
    presetOptions,
    function() local prof = GB:ActiveProfile(); return prof and prof.bars and prof.bars[selBar] end,
    function(v) GB:AssignBarPreset(selBar, v); s.refresh() end)
  presetdd:SetPoint("TOPRIGHT", -18, -104 - baseBY)
  attachTip(presetdd, "Preset", "Which whole-look preset the selected bar wears. The preset being edited renders live as you tweak it; any other preset shows its saved look. Flyouts follow the bar they pop from.")
  -- Pulse the selected bar on screen while the Preset row is hovered / its list is
  -- open (the same QoL the old "Apply to bars" grid had, now keyed to selBar).
  presetdd:HookScript("OnEnter", function() if GB.Skin and GB.Skin.PingBar then GB.Skin:PingBar(selBar, true) end end)
  presetdd:HookScript("OnLeave", function()
    if animFlyout and animFlyout:IsShown() and animFlyout.gbPingBar == selBar then return end
    if GB.Skin and GB.Skin.PingBar then GB.Skin:PingBar(selBar, false) end
  end)
  presetdd:HookScript("OnClick", function()
    if not (animFlyout and animFlyout:IsShown()) then return end
    if animFlyout.gbPingBar and animFlyout.gbPingBar ~= selBar and GB.Skin then
      GB.Skin:PingBar(animFlyout.gbPingBar, false)   -- a different bar was selected when last opened
    end
    animFlyout.gbPingBar = selBar
    if not animFlyout.gbPingHooked then
      animFlyout.gbPingHooked = true
      animFlyout:HookScript("OnHide", function(f)
        if f.gbPingBar and GB.Skin and GB.Skin.PingBar then GB.Skin:PingBar(f.gbPingBar, false) end
        f.gbPingBar = nil
      end)
    end
  end)

  local vlab = newText(bf, FONT.body, 12, TEXT, "LEFT"); vlab:SetPoint("TOPLEFT", 18, -106 - BY); vlab:SetText("Visibility")
  local visdd = animDropdown(bf, 150, visLabel,
    function() return VIS_OPTS end,
    visValue,
    function(v)
      local c = ensureBarLayout(selBar)
      c.vis = (v ~= "default") and v or nil
      apply(); s.refresh()
    end)
  visdd:SetPoint("TOPRIGHT", -18, -104 - BY)
  attachTip(visdd, "Visibility", "Default follows Blizzard's rules (Edit Mode, mouseover, vehicles). Always visible shows the bar even if Edit Mode has it disabled. In/Out of combat show it only then. Hidden removes it. Game-driven hides always win.")

  -- Empty buttons (Jason, borrowed from Edit Mode's Always Show Buttons):
  -- Shown = Blizzard's rules + the skin's Empty-slots treatment; Hidden =
  -- action-less buttons collapse entirely (their grid slot stays — a hole,
  -- not a shuffle; drag a spell and they reappear as drop targets).
  local elab = newText(bf, FONT.body, 12, TEXT, "LEFT"); elab:SetPoint("TOPLEFT", 18, -136 - BY); elab:SetText("Empty buttons")
  local emBtns, emPrev = {}, nil
  for i = 2, 1, -1 do
    local ec = ({ { true, "Shown" }, { false, "Hidden" } })[i]
    local b = flatButton(bf, 60, 22, COLOR.heroic, ec[2], 11)
    if emPrev then b:SetPoint("TOPRIGHT", emPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -134 - BY) end
    b:SetScript("OnClick", function()
      local c = ensureBarLayout(selBar)
      -- NOT `x and false or nil` — that idiom can never yield false (the
      -- `or` eats it), which silently wrote Default here (Jason's bug).
      if ec[1] then c.showEmpty = nil else c.showEmpty = false end
      for _, e in ipairs(emBtns) do e.b:SetActive(e.v == ec[1]) end
      apply()
    end)
    emBtns[#emBtns + 1] = { b = b, v = ec[1] }; emPrev = b
  end
  attachTip(emBtns[2].b, "Shown", "Empty slots render normally — Blizzard's rules plus the Empty slots section's treatment.")
  attachTip(emBtns[1].b, "Hidden", "Buttons with no action disappear entirely. Their spot in the grid stays reserved, and they reappear while you drag a spell.")

  -- Copy another bar's whole layout onto this one (Jason: styling 8 bars one
  -- by one is a chore — tune one, copy it around).
  local cplab = newText(bf, FONT.body, 12, TEXT, "LEFT"); cplab:SetPoint("TOPLEFT", 18, -164 - BY); cplab:SetText("Copy layout from")
  local cpdd = animDropdown(bf, 150,
    function() return "Pick a bar…" end,
    function()
      local o = {}
      for i, bar in ipairs(GB.BARS) do
        if bar.buttonPrefix ~= selBar then o[#o + 1] = { value = bar.buttonPrefix, label = bar.label } end
      end
      return o
    end,
    function() return nil end,
    function(v)
      local src = barLayoutData(v)
      if not src then return end
      -- Copy the ARRANGEMENT only — size, gap, rows, row gap, orientation
      -- (Jason). Never position (that literally stacks two bars on one spot);
      -- visibility, button count and empty-button settings stay per-bar too.
      local dst = ensureBarLayout(selBar)
      if not dst then return end
      dst.size, dst.gap, dst.rows = src.size, src.gap, src.rows
      dst.gapCross, dst.horizontal = src.gapCross, src.horizontal
      apply(); s.refresh()
    end)
  cpdd:SetPoint("TOPRIGHT", -18, -162 - BY)
  attachTip(cpdd, "Copy layout", "Copies the picked bar's arrangement — button size, gap, rows, row gap, orientation — onto the selected bar. Its position, visibility, button count and empty-button settings stay as they are.")

  local sizeRow = sliderRow(bf, -194 - BY, "Button size", 24, 64, 1,
    function() local c = data(); return (c and c.size) or 45 end,
    function(v) local c = ensureBarLayout(selBar); c.size = v; apply() end,
    function(v) return v .. "px" end)
  local gapRow = sliderRow(bf, -238 - BY, "Gap", -32, 64, 1,
    function() local c = data(); return (c and c.gap) or 4 end,
    function(v) local c = ensureBarLayout(selBar); c.gap = v; apply() end,
    function(v) return v .. "px" end)
  local rowsRow = sliderRow(bf, -282 - BY, "Rows", 1, 6, 1,
    function() local c = data(); return (c and c.rows) or 1 end,
    function(v) local c = ensureBarLayout(selBar); c.rows = v; apply(); s.refresh() end,   -- refresh: Row gap shows at rows > 1
    function(v) return tostring(v) end)
  local cntRow = sliderRow(bf, -326 - BY, "Buttons", 1, 12, 1,
    function() local c = data(); return (c and c.count) or 12 end,
    function(v) local c = ensureBarLayout(selBar); c.count = v; apply() end,
    function(v) return tostring(v) end)

  -- Orientation base y (shifted by BY); Row gap slides it further when rows > 1.
  local dlab = newText(bf, FONT.body, 12, TEXT, "LEFT"); dlab:SetPoint("TOPLEFT", 18, -374 - BY); dlab:SetText("Orientation")
  local orBtns, orPrev = {}, nil
  for i = 2, 1, -1 do
    local oc = ({ { true, "Horizontal" }, { false, "Vertical" } })[i]
    local b = flatButton(bf, 80, 22, COLOR.heroic, oc[2], 11)
    if orPrev then b:SetPoint("TOPRIGHT", orPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -372 - BY) end
    b:SetScript("OnClick", function()
      local c = ensureBarLayout(selBar); c.horizontal = oc[1]
      for _, e in ipairs(orBtns) do e.b:SetActive(e.h == c.horizontal) end; apply()
    end)
    orBtns[#orBtns + 1] = { b = b, h = oc[1] }; orPrev = b
  end

  -- Cross-axis gap — between rows (columns on a vertical bar). Only shown when
  -- the bar folds into more than one row (Jason's rule); defaults to Gap. Sits
  -- ABOVE Orientation (Jason), which slides down to make room when it shows.
  local rgRow = sliderRow(bf, -370 - BY, "Row gap", -32, 64, 1,
    function() local c = data(); return (c and (c.gapCross or c.gap)) or 4 end,
    function(v) local c = ensureBarLayout(selBar); c.gapCross = v; apply() end,
    function(v) return v .. "px" end)

  -- Position (phase L3): move mode + per-bar reset. Both need the master
  -- switch on (position is part of the layout the addon owns).
  local mvBtn = flatButton(bf, 110, 22, COLOR.purple, "Move bars", 11)
  mvBtn:SetPoint("TOPLEFT", 18, -436)
  mvBtn:SetScript("OnClick", function()
    if GB.Layout then GB.Layout:SetMoveMode(not GB.Layout:MoveModeOn()) end
  end)
  attachTip(mvBtn, "Move bars", "Drag any bar's overlay to reposition it. Click an overlay to select it, then nudge with the arrow keys — hold Shift for 10px steps. ESC or this button exits. Out of combat only.")
  -- Quick keybind (phase L4, the last layout-scope item): launches Blizzard's
  -- own quick-bind flow — hover a button, press a key. Same entry the
  -- Settings panel uses (close the open panel, then Show). Not gated on the
  -- master switch: keybinding isn't layout.
  local qkBtn = flatButton(bf, 110, 22, COLOR.heroic, "Quick keybind", 11)
  qkBtn:SetPoint("LEFT", mvBtn, "RIGHT", 8, 0)
  qkBtn:SetScript("OnClick", openQuickKeybind)
  attachTip(qkBtn, "Quick keybind", "Opens Blizzard's Quick Keybind mode: hover any action button and press a key to bind it, ESC when done. Out of combat only.")
  local rsBtn = flatButton(bf, 130, 22, COLOR.heroic, "Reset position", 11)
  rsBtn:SetPoint("TOPRIGHT", -18, -436)
  rsBtn:SetScript("OnClick", function() if GB.Layout then GB.Layout:ResetPosition(selBar) end end)
  attachTip(rsBtn, "Reset position", "Returns the selected bar to wherever Edit Mode places it.")

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -406); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Button size scales the WHOLE button proportionally — icon, text, glows — like Edit Mode's size setting. How the icon sits within its button stays a style choice (the Shape & icon section's Size, saved in the preset). Changes made in combat apply the moment combat ends.")

  selectBar = function(k)
    selBar = k
    for _, c in ipairs(chips) do c.b:SetActive(c.k == k) end
    s.refresh()
  end

  bf:SetHeight(478 + BY)
  s.refresh = function()
    for _, c in ipairs(chips) do c.b:SetActive(c.k == selBar) end
    local on = layoutOn()
    -- Preset assignment is independent of the layout master switch (assign a look
    -- to a bar whether or not GB owns its geometry) → always enabled.
    presetdd:refresh()
    own:refresh(); sizeRow:refresh(); gapRow:refresh(); rowsRow:refresh(); cntRow:refresh(); rgRow:refresh()
    sizeRow:setEnabled(on); gapRow:setEnabled(on); rowsRow:setEnabled(on); cntRow:setEnabled(on)
    local c = data()
    local hz = not c or c.horizontal ~= false
    for _, e in ipairs(orBtns) do e.b:SetActive(on and e.h == hz); e.b:SetEnabled(on) end
    visdd:refresh(); visdd:SetEnabled(on)
    local se = not (c and c.showEmpty == false)   -- nil/true = Shown
    for _, e in ipairs(emBtns) do e.b:SetActive(on and e.v == se); e.b:SetEnabled(on) end
    -- Row gap: visible only when the bar folds into >1 row. It lives above
    -- Orientation, so Orientation + the hint slide down when it shows (only
    -- the row's ANCHOR button moves — the second is chained to it). BY = the
    -- extra chip-row shift (pet/stance added a third row of bar chips).
    local multiRow = (c and (c.rows or 1) or 1) > 1
    rgRow:SetShown(multiRow); rgRow:setEnabled(on)
    local yOr = (multiRow and -416 or -372) - BY
    dlab:ClearAllPoints(); dlab:SetPoint("TOPLEFT", 18, yOr - 2)
    orBtns[1].b:ClearAllPoints(); orBtns[1].b:SetPoint("TOPRIGHT", -18, yOr)
    mvBtn:ClearAllPoints(); mvBtn:SetPoint("TOPLEFT", 18, yOr - 30)
    rsBtn:ClearAllPoints(); rsBtn:SetPoint("TOPRIGHT", -18, yOr - 30)
    local moving = (GB.Layout and GB.Layout:MoveModeOn()) or false
    mvBtn:SetActive(moving)
    mvBtn:SetText(moving and "Lock bars" or "Move bars")   -- Jason: the button names the NEXT action
    mvBtn:SetEnabled(on); rsBtn:SetEnabled(on)
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", 18, yOr - 62)
    hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0)
    bf:SetHeight((multiRow and 522 or 478) + BY)
    relayout()
  end
end

local function buildPreviewPane(parent)
  local pane = CreateFrame("Frame", nil, parent)
  pane:SetPoint("TOPRIGHT", 0, TITLE_DIV_Y - 1)
  pane:SetPoint("BOTTOMRIGHT", 0, FOOTER_H)
  pane:SetWidth(PREVIEW_W)

  local eb = newText(pane, FONT.head, 12, MUTE, "LEFT"); eb:SetPoint("TOPLEFT", 14, -12); eb:SetText("PREVIEW")

  -- state chips (2 columns x 3 rows)
  previewChips = {}
  for i, st in ipairs(PREVIEW_STATES) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local chip = flatButton(pane, 90, 22, COLOR.heroic, st[2], 11); chip:SetBase(0.2)
    chip:SetPoint("TOPLEFT", 12 + col * 96, -34 - row * 26)
    chip:SetScript("OnClick", function() C:SetPreviewState(st[1]) end)
    previewChips[st[1]] = chip
  end

  -- Sample construction. The icon is 104px; the whole construction (icon +
  -- plate) is centered at PREVIEW_CENTER_Y and RefreshPreview re-anchors it as
  -- the extension grows, so nothing floats. (Initial anchor is overwritten there.)
  local frame = CreateFrame("Frame", nil, pane); frame:SetSize(104, 104)
  frame:SetPoint("CENTER", pane, "TOP", 0, PREVIEW_CENTER_Y)
  previewFrame = frame
  -- Live pulse for the pulsing chips (proc/flash): breathe the multi-part glow's
  -- alpha about its peak at the current Pulse-speed, mirroring Glows.lua's driver, so
  -- the slider has a visible effect. Runs only while the window (this frame) is shown.
  frame:SetScript("OnUpdate", function(_, dt)
    if not previewPulsing then return end
    previewPulsePhase = previewPulsePhase + dt * math.max(0.1, (GB.db and GB.db.glowPulseSpeed) or 1)
    local a = previewPulsePeak * (PREVIEW_PULSE_DEPTH + (1 - PREVIEW_PULSE_DEPTH) * (0.5 + 0.5 * math.cos(previewPulsePhase * 5.7)))
    if previewOuter:IsShown() then previewOuter:SetAlpha(a) end
    if previewInner:IsShown() then previewInner:SetAlpha(a) end
  end)
  previewGlow = frame:CreateTexture(nil, "BACKGROUND"); previewGlow:SetPoint("TOPLEFT", -16, 16); previewGlow:SetPoint("BOTTOMRIGHT", 16, -16)
  previewGlow:SetBlendMode("ADD"); previewGlow:SetVertexColor(1, 0.77, 0.30); previewGlow:Hide()
  -- Multi-part shaped glow (hand shapes): outer bloom UNDER the icon, inner rim OVER
  -- the plate — mirrors the bars (Glows.lua) so the Proc/Hover/Selected/Flash chips
  -- show the real glow, honouring each trigger's colour / opacity / layers.
  previewOuter = frame:CreateTexture(nil, "BACKGROUND", nil, -1); previewOuter:SetBlendMode("BLEND"); previewOuter:Hide()
  previewInner = frame:CreateTexture(nil, "OVERLAY"); previewInner:SetBlendMode("BLEND"); previewInner:Hide()
  previewIcon = frame:CreateTexture(nil, "ARTWORK"); previewIcon:SetAllPoints()
  previewCD = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate"); previewCD:SetAllPoints(previewIcon)
  previewCD:SetDrawEdge(false); previewCD:SetDrawBling(false); previewCD:Hide()
  -- No countdown number on the preview sweep: it ignores the Text→Countdown
  -- styling and the enlarged preview makes its size/position wrong anyway (Jason).
  if previewCD.SetHideCountdownNumbers then previewCD:SetHideCountdownNumbers(true) end
  previewRing = frame:CreateTexture(nil, "OVERLAY"); previewRing:SetPoint("TOPLEFT", -4, 4); previewRing:SetPoint("BOTTOMRIGHT", 4, -4)
  previewRing:SetBlendMode("ADD"); previewRing:Hide()
  previewBorder = frame:CreateTexture(nil, "BACKGROUND", nil, -2)   -- behind the icon; peeks out as the border
  previewBorder:SetTexture("Interface\\Buttons\\WHITE8X8"); previewBorder:Hide()
  -- Finish-flash preview: an expanding shape-glow burst that fades out, mirroring
  -- the engine's setupFinishFlash so the flash colour/shape is visible without a
  -- real cooldown. Frame is anchored over the construction at play time (so the
  -- scale bursts from centre); the texture fills the frame.
  previewFlashFrame = CreateFrame("Frame", nil, frame)
  previewFlashFrame:SetFrameLevel(frame:GetFrameLevel() + 5); previewFlashFrame:SetAlpha(0)
  previewFlash = previewFlashFrame:CreateTexture(nil, "OVERLAY"); previewFlash:SetBlendMode("ADD")
  previewFlash:SetAllPoints(previewFlashFrame)
  previewFlashAnim = previewFlashFrame:CreateAnimationGroup()
  local fa = previewFlashAnim:CreateAnimation("Alpha")
  fa:SetFromAlpha(1); fa:SetToAlpha(0); fa:SetDuration(0.45); fa:SetSmoothing("OUT")
  local fsc = previewFlashAnim:CreateAnimation("Scale")
  fsc:SetScaleFrom(0.85, 0.85); fsc:SetScaleTo(1.5, 1.5); fsc:SetOrigin("CENTER", 0, 0)
  fsc:SetDuration(0.45); fsc:SetSmoothing("OUT")
  if previewFlashAnim.SetToFinalAlpha then previewFlashAnim:SetToFinalAlpha(true) end
  previewFlashAnim:SetScript("OnFinished", function() previewFlashFrame:SetAlpha(0) end)

  -- Cast/channel fill preview: a looping fake drain mirroring the bars' fill
  -- (CastFillOnUpdate geometry — cast fills up, channel drains; colour / alpha /
  -- direction from the same db fields the engine reads). Shown by the Cast /
  -- Channel chips; anchored + masked per-refresh in RefreshPreview.
  previewCastFillFrame = CreateFrame("Frame", nil, frame)
  previewCastFillFrame:SetFrameLevel(frame:GetFrameLevel() + 4)   -- above plates/glows, below the flash burst (+5)
  previewCastFillFrame.tex = previewCastFillFrame:CreateTexture(nil, "OVERLAY")
  previewCastFillFrame.tex:SetTexture("Interface\\Buttons\\WHITE8X8")   -- maskable (masks don't clip SetColorTexture)
  previewCastFillFrame:SetScript("OnUpdate", function(f)
    -- No completion burst at the wrap: the real one is Blizzard's own EndBurst
    -- animation (replayed inside their widget on the bars) and can't be cloned
    -- faithfully here — Jason: better none than a lookalike (session 12).
    local p = (GetTime() % 2.4) / 2.4      -- a looping fake 2.4s cast
    local frac = f.channel and (1 - p) or p
    local tex, W, H = f.tex, f:GetWidth(), f:GetHeight()
    local dir = (GB.db and GB.db.castDrainDir) or "up"
    tex:ClearAllPoints()
    if dir == "up" then tex:SetPoint("BOTTOMLEFT", f); tex:SetPoint("BOTTOMRIGHT", f); tex:SetHeight(math.max(0.01, H * frac))
    elseif dir == "down" then tex:SetPoint("TOPLEFT", f); tex:SetPoint("TOPRIGHT", f); tex:SetHeight(math.max(0.01, H * frac))
    elseif dir == "left" then tex:SetPoint("TOPRIGHT", f); tex:SetPoint("BOTTOMRIGHT", f); tex:SetWidth(math.max(0.01, W * frac))
    else tex:SetPoint("TOPLEFT", f); tex:SetPoint("BOTTOMLEFT", f); tex:SetWidth(math.max(0.01, W * frac)) end
  end)
  previewCastFillFrame:Hide()

  -- Caption = a bold state-name heading (GeneralSans-Semibold) + the description
  -- body. The body lives on its own mouse-enabled frame with hyperlinks on:
  -- section names are |Hgbsec:*|h links (caret orange) that open that accordion
  -- section. RefreshPreview re-anchors both below the construction.
  local head = newText(pane, FONT.label, 11, TEXT, "LEFT")
  head:SetJustifyH("LEFT"); head:SetText("")
  head:SetPoint("TOP", frame, "BOTTOM", 0, -26)
  head:SetPoint("LEFT", pane, "LEFT", 10, 0); head:SetPoint("RIGHT", pane, "RIGHT", -10, 0)
  previewCaptionHead = head
  local cap = newText(pane, FONT.body, 10, MUTE, "LEFT")
  cap:SetJustifyH("LEFT"); cap:SetText(PREVIEW_CAPTION_DEFAULT)
  cap:SetPoint("TOP", head, "BOTTOM", 0, -3)
  cap:SetPoint("LEFT", pane, "LEFT", 10, 0); cap:SetPoint("RIGHT", pane, "RIGHT", -10, 0)
  previewCaption = cap
  -- The "Styled in:" bullet list — bold (Semibold), on its own mouse-enabled
  -- hyperlink frame; clicking an orange section name opens that section.
  local capFrame = CreateFrame("Frame", nil, pane)
  capFrame:SetHyperlinksEnabled(true)
  capFrame:EnableMouse(true)
  capFrame:SetScript("OnHyperlinkClick", function(_, link)
    local title = link and link:match("^gbsec:(.+)$")
    if not title then return end
    local st = previewState
    C:OpenSection(title)
    C:SetPreviewState(st)   -- some sections hijack the preview on open (Glows → proc); restore the clicked state
  end)
  local links = newText(capFrame, FONT.label, 10.5, MUTE, "LEFT")
  links:SetJustifyH("LEFT"); links:SetSpacing(3); links:SetText("")
  links:SetPoint("TOP", cap, "BOTTOM", 0, -8)
  links:SetPoint("LEFT", pane, "LEFT", 10, 0); links:SetPoint("RIGHT", pane, "RIGHT", -10, 0)
  previewCaptionLinks = links
  capFrame:SetAllPoints(links)   -- the click surface tracks the list's rect
end

local function BuildPanel()
  panel = CreateFrame("Frame", "GloomsBarsConfig", UIParent)
  panel:SetSize(PANEL_W, PANEL_H)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:EnableMouse(true)
  panel:SetMovable(true); panel:SetClampedToScreen(true)
  skinPlate(panel)
  -- Signature warm bottom glow: orange gradient fading up over the lower ~55%.
  local glow = panel:CreateTexture(nil, "BORDER")
  glow:SetTexture(WHITE)
  glow:SetPoint("BOTTOMLEFT", 1, 1); glow:SetPoint("BOTTOMRIGHT", -1, 1); glow:SetHeight(PANEL_H * 0.55)
  glow:SetGradient("VERTICAL",
    CreateColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, 0.11),
    CreateColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, 0))
  addEdges(panel, COLOR.rim, 1)

  -- Title bar: the Gb monogram (Media/ui/logo.png, 115×128 art shown at 25×28
  -- — native aspect; the wordmark is cropped off — the title text IS the
  -- wordmark here) left of the title.
  local logo = panel:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(GB.MEDIA .. "ui\\logo.png")
  logo:SetSize(25, 28)
  logo:SetPoint("TOPLEFT", 14, -10)
  local mark = newText(panel, FONT.title, 21, { r = 1, g = 1, b = 1 }, "LEFT")
  mark:SetPoint("LEFT", logo, "RIGHT", 9, 0); mark:SetText("GLOOM'S BARS")
  local sub = newText(panel, FONT.head, 14, COLOR.purple, "LEFT")
  sub:SetPoint("LEFT", mark, "RIGHT", 9, -1); sub:SetText("STYLE EDITOR")
  local close = flatButton(panel, 22, 20, COLOR.heroic, "X", 12)
  close:SetPoint("TOPRIGHT", -8, -13); close:SetScript("OnClick", function() panel:Hide() end)
  local tdiv = panel:CreateTexture(nil, "ARTWORK"); tdiv:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  tdiv:SetHeight(1); tdiv:SetPoint("TOPLEFT", 0, TITLE_DIV_Y); tdiv:SetPoint("TOPRIGHT", 0, TITLE_DIV_Y)

  -- Drag strip (title bar)
  local drag = CreateFrame("Frame", nil, panel)
  drag:SetPoint("TOPLEFT", 2, -2); drag:SetPoint("TOPRIGHT", -34, -2); drag:SetHeight(44)
  drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() if panel:IsMovable() then panel:StartMoving() end end)
  drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

  -- Footer: divider + master enable toggle + profile placeholder
  local fdiv = panel:CreateTexture(nil, "ARTWORK"); fdiv:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  fdiv:SetHeight(1); fdiv:SetPoint("BOTTOMLEFT", 0, FOOTER_H); fdiv:SetPoint("BOTTOMRIGHT", 0, FOOTER_H)
  local enTog = makeToggle(panel,
    function() return GB.Skin and GB.Skin.enabled end,
    function(v) if not GB.Skin then return end; if v then GB.Skin:Enable() else GB.Skin:Disable() end end)
  enTog:SetPoint("BOTTOMLEFT", 16, 16)
  local enLbl = newText(panel, FONT.body, 12.5, TEXT, "LEFT"); enLbl:SetPoint("LEFT", enTog, "RIGHT", 10, 0)
  enLbl:SetText("Enable Gloom's Bars")
  panel._enableToggle = enTog
  -- Footer quick-keybind (Jason: reachable without digging into Bar layout).
  -- (The old footer profile switcher is gone — the left rail is always visible.)
  local fqk = flatButton(panel, 110, 24, COLOR.heroic, "Quick keybind", 11); fqk:SetBase(0.2)
  fqk:SetPoint("BOTTOMRIGHT", -14, 14)
  fqk:SetScript("OnClick", openQuickKeybind)
  attachTip(fqk, "Quick keybind", "Opens Blizzard's Quick Keybind mode: hover any action button and press a key to bind it, ESC when done. Out of combat only.")

  -- Three panels: left rail (profiles/presets) · middle controls · right preview,
  -- with a vertical divider at each seam.
  buildRailPane(panel)
  buildPreviewPane(panel)
  local vdivL = panel:CreateTexture(nil, "ARTWORK"); vdivL:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  vdivL:SetWidth(1); vdivL:SetPoint("TOPLEFT", RAIL_W, TITLE_DIV_Y); vdivL:SetPoint("BOTTOMLEFT", RAIL_W, FOOTER_H)
  local vdivR = panel:CreateTexture(nil, "ARTWORK"); vdivR:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  vdivR:SetWidth(1); vdivR:SetPoint("TOPRIGHT", -PREVIEW_W, TITLE_DIV_Y); vdivR:SetPoint("BOTTOMRIGHT", -PREVIEW_W, FOOTER_H)

  -- Body: a scroll frame holding the accordion (the middle panel).
  -- The section content grows past the window height, so it scrolls (mouse wheel).
  local scroll = CreateFrame("ScrollFrame", nil, panel)
  contentScroll = scroll   -- module ref: ToggleSection scrolls the opened section near the top
  scroll:SetPoint("TOPLEFT", RAIL_W + 1, TITLE_DIV_Y - 1)
  scroll:SetPoint("BOTTOMRIGHT", -(PREVIEW_W + 8), FOOTER_H + 1)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 42)))
  end)
  bodyContainer = CreateFrame("Frame", nil, scroll)
  bodyContainer:SetSize(PANEL_W - RAIL_W - PREVIEW_W - 9, 10)
  scroll:SetScrollChild(bodyContainer)

  -- Custom thin scrollbar (shared helper): orange thumb + click-to-jump + drag + wheel.
  -- The accordion grows/shrinks as sections open; the bar's OnUpdate tracks it.
  -- Sits in the middle panel's right gutter, just left of the preview divider.
  makeScrollbar(panel, scroll, function(b)
    b:SetPoint("TOPRIGHT", -(PREVIEW_W + 4), TITLE_DIV_Y - 2); b:SetPoint("BOTTOMRIGHT", -(PREVIEW_W + 4), FOOTER_H + 2)
  end)

  -- Sections (mockup order). Profiles/presets live in the left rail now — the
  -- accordion holds the per-preset styling + bar controls.
  makeSection("Shape & icon", buildShapeSection)
  makeSection("Plate", buildPlateSection)
  makeSection("Decoration layers", buildDecorSection)
  makeSection("Text", buildTextSection)
  makeSection("Glows", buildGlowsSection)
  makeSection("Animations", buildAnimsSection)
  makeSection("Cast & channel", buildCastSection)
  makeSection("Cooldown & availability", buildCooldownSection)
  makeSection("Empty slots", buildEmptySection)
  makeSection("Bar Layout & Preset", buildLayoutSection)

  -- All sections start CLOSED (Jason 2026-07-20 — easier to find the one you want
  -- than scrolling past a large open panel).
  relayout()

  tinsert(UISpecialFrames, "GloomsBarsConfig")   -- Escape closes it

  -- Exiting the addon RELOCKS the bars (Jason): however the window goes away —
  -- the X, ESC, /gb — move mode ends with it, so movers never outlive the
  -- window. (ESC with the window open ends move mode via one of two paths:
  -- the mover key catcher eats it, or the window closes and this fires.)
  panel:HookScript("OnHide", function()
    if GB.Layout and GB.Layout:MoveModeOn() then GB.Layout:SetMoveMode(false) end
  end)
  C:RefreshPreview()
  C:SetPreviewState("idle")
end

function C:Refresh()
  if not panel then return end
  if panel._enableToggle then panel._enableToggle:refresh() end
  if panel._railRefresh then panel._railRefresh() end
  for _, s in ipairs(sections) do if s.refresh then s.refresh() end end
  C:RefreshPreview()
  C:SetPreviewState(previewState)
end

function C:Toggle()
  if not panel then BuildPanel(); C:Refresh(); return end
  if panel:IsShown() then panel:Hide() else panel:Show(); C:Refresh() end
end
