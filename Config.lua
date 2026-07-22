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
  sl:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self._seek = true; seek(self) end end)
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
local PANEL_W, PANEL_H = 620, 640
local PREVIEW_W = 210            -- left preview pane width
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

local panel, bodyContainer
local sections = {}
local previewFrame, previewIcon, previewMask, previewGlow, previewRing, previewCD
local previewBorder, previewBorderMask, previewCaption
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
local STATE_DESC = {
  idle     = "Idle: the button's resting look, with nothing active.",
  cooldown = "Cooldown: while the ability is recharging (the shaped sweep, then a finish flash).",
  proc     = "Proc: fires when an ability procs (a free or empowered cast becomes ready).",
  highlight = "Highlight: Blizzard's \"press this\" pulse — where a hovered spellbook/talent spell sits on your bars.",
  cast     = "Cast: while you're casting a cast-time spell on this button (in-game it also drains a fill).",
  channel  = "Channel: while you're channeling a spell on this button (in-game it also drains a fill).",
  hover    = "Hover: while your mouse is over the button.",
  selected = "Selected: when the button is toggled on (a stance, form, or toggled aura).",
  flash    = "Flash: during auto-attack or auto-shot (needs the Attack ability on a bar).",
  assist   = "Assist: Blizzard's suggested-next-ability rotation highlight.",
  unusable = "Unusable: wrong form/stance, silenced, or missing a resource. Tint in Cooldown & availability.",
  oom      = "Out of mana: not enough mana/power. Tint in Cooldown & availability.",
  range    = "Out of range: target too far — icon wash + keybind recolour. Enable in Cooldown & availability.",
}

function C:ToggleSection(s)
  if previewCaption then previewCaption:SetText(PREVIEW_CAPTION_DEFAULT) end   -- Animations re-sets it in s.refresh
  local wasOpen = s.open
  for _, x in ipairs(sections) do x.open = false end
  if not wasOpen then s.open = true; if s.refresh then s.refresh() end end   -- reflect current state on open
  relayout()
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

-- Text — keybind styling + placement. The engine (ApplyHotkeyOverride, re-run
-- via ReapplyDecor and re-asserted in the UpdateHotkeys hook) reads styleData.
-- hotkey. Off = Blizzard's default. Count has its own section (session 12);
-- a Name override remains future work.
local function buildTextSection(bf, s)
  local function reapply() if GB.Skin then GB.Skin:ReapplyDecor() end end

  local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, -14); lab:SetText("Custom keybind")
  local en = makeToggle(bf,
    hotkeyOn,
    function(v) local h = ensureHotkey(); if h then h.enabled = v and true or false end; reapply(); if GB.Skin then GB.Skin:RefreshHotkeyText() end; s.refresh() end)
  en:SetPoint("TOPRIGHT", -18, -12)

  local clab = newText(bf, FONT.body, 12, TEXT, "LEFT"); clab:SetPoint("TOPLEFT", 18, -46); clab:SetText("Color")
  local cs = colorSwatch(bf,
    function() local h = hotkeyData(); return h and h.color end,
    function(c) local h = ensureHotkey(); h.color = c; reapply() end)
  cs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local sizeRow = sliderRow(bf, -78, "Size", 6, 28, 1,
    function() local h = hotkeyData(); return (h and h.size) or 13 end,
    function(v) local h = ensureHotkey(); h.size = v; reapply() end,
    function(v) return v .. "px" end)

  -- Font — a dropdown of every LibSharedMedia font (bundled + other addons').
  local flab = newText(bf, FONT.body, 12, TEXT, "LEFT"); flab:SetPoint("TOPLEFT", 18, -122); flab:SetText("Font")
  local fontBtn = fontDropdown(bf, 150,
    function() local h = hotkeyData(); return h and h.font end,
    function(name) local h = ensureHotkey(); h.font = name; reapply() end)
  fontBtn:SetPoint("TOPRIGHT", -18, -120)

  -- POSITION — zone (over the icon vs. in the extension plate) + nudge offsets.
  local phdr = newText(bf, FONT.head, 13, COLOR.purple, "LEFT"); phdr:SetPoint("TOPLEFT", 18, -160); phdr:SetText("POSITION")
  local zlab = newText(bf, FONT.body, 12, TEXT, "LEFT"); zlab:SetPoint("TOPLEFT", 18, -190); zlab:SetText("Zone")
  local zoneBtns, zPrev = {}, nil
  for i = 2, 1, -1 do
    local zc = ({ { "center", "Center" }, { "extension", "Extension" } })[i]
    local b = flatButton(bf, 80, 22, COLOR.heroic, zc[2], 11)
    if zPrev then b:SetPoint("TOPRIGHT", zPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -188) end
    b:SetScript("OnClick", function()
      local h = ensureHotkey(); h.zone = zc[1]
      for _, e in ipairs(zoneBtns) do e.b:SetActive(e.z == h.zone) end; reapply()
    end)
    zoneBtns[#zoneBtns + 1] = { b = b, z = zc[1] }; zPrev = b
  end

  local oxRow = sliderRow(bf, -222, "Offset X", -40, 40, 1,
    function() local h = hotkeyData(); return (h and h.offsetX) or 0 end,
    function(v) local h = ensureHotkey(); h.offsetX = v; reapply() end,
    function(v) return v .. "px" end)
  local oyRow = sliderRow(bf, -266, "Offset Y", -40, 40, 1,
    function() local h = hotkeyData(); return (h and h.offsetY) or 0 end,
    function(v) local h = ensureHotkey(); h.offsetY = v; reapply() end,
    function(v) return v .. "px" end)

  -- Modifiers — a SUB-feature of Custom keybind: swap the keybind's modifier
  -- prefixes (m-/s-/c-/a-) for Mac symbols (⌘⇧⌃⌥), hyphen removed. Only renders
  -- while Custom keybind is on (greyed + inert when off); stored per style
  -- (keybindMods) so the choice persists across the master toggle.
  local mhdr = newText(bf, FONT.head, 13, COLOR.purple, "LEFT"); mhdr:SetPoint("TOPLEFT", 18, -306); mhdr:SetText("MODIFIERS")
  local mlab = newText(bf, FONT.body, 12, TEXT, "LEFT"); mlab:SetPoint("TOPLEFT", 18, -336); mlab:SetText("Mac symbol icons")
  local modTog = makeToggle(bf,
    function() local st = GB.db and GB.db.styleData; return st and st.keybindMods == "symbols" end,
    function(v)
      local st = GB.db and GB.db.styleData; if st then st.keybindMods = v and "symbols" or "default" end
      if GB.Skin then GB.Skin:RefreshHotkeyText() end
    end)
  modTog:SetPoint("TOPRIGHT", -18, -334)

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -366); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Everything here needs Custom keybind on. Mac symbol icons replace m-/s-/c-/a- prefixes with ⌘/⇧/⌃/⌥ (macOS binds).")
  bf:SetHeight(404)
  s.refresh = function()
    local h = hotkeyData()
    local on = hotkeyOn()
    en:refresh(); cs:refresh(); sizeRow:refresh(); oxRow:refresh(); oyRow:refresh()
    fontBtn:refresh(); modTog:refresh()
    -- Grey the styling controls when the override is off (Mac symbols gate on it too now).
    cs.swatch:EnableMouse(on); cs.swatch:SetAlpha(on and 1 or 0.35)
    sizeRow:setEnabled(on); oxRow:setEnabled(on); oyRow:setEnabled(on)
    fontBtn:SetEnabled(on)
    modTog:SetEnabled(on); modTog:SetAlpha(on and 1 or 0.35)
    for _, e in ipairs(zoneBtns) do e.b:SetActive(on and (h.zone or "extension") == e.z); e.b:SetEnabled(on) end
  end
end

-- Charge count — styling + placement for the count text (spell charges, item
-- stacks). Engine: ApplyCountOverride (re-run via ReapplyDecor) reads
-- styleData.count. Off = Blizzard's default corner text.
local function buildCountSection(bf, s)
  local function reapply() if GB.Skin then GB.Skin:ReapplyDecor() end end

  local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, -14); lab:SetText("Custom count")
  local en = makeToggle(bf, countOn,
    function(v) local c = ensureCount(); if c then c.enabled = v and true or false end; reapply(); s.refresh() end)
  en:SetPoint("TOPRIGHT", -18, -12)

  local clab = newText(bf, FONT.body, 12, TEXT, "LEFT"); clab:SetPoint("TOPLEFT", 18, -46); clab:SetText("Color")
  local cs = colorSwatch(bf,
    function() local c = countData(); return c and c.color end,
    function(col) local c = ensureCount(); c.color = col; reapply() end)
  cs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local sizeRow = sliderRow(bf, -78, "Size", 6, 28, 1,
    function() local c = countData(); return (c and c.size) or 14 end,
    function(v) local c = ensureCount(); c.size = v; reapply() end,
    function(v) return v .. "px" end)

  local flab = newText(bf, FONT.body, 12, TEXT, "LEFT"); flab:SetPoint("TOPLEFT", 18, -122); flab:SetText("Font")
  local fontBtn = fontDropdown(bf, 150,
    function() local c = countData(); return c and c.font end,
    function(name) local c = ensureCount(); c.font = name; reapply() end)
  fontBtn:SetPoint("TOPRIGHT", -18, -120)

  -- POSITION — zone (Blizzard's corner / centred on the icon / in the plate half).
  local phdr = newText(bf, FONT.head, 13, COLOR.purple, "LEFT"); phdr:SetPoint("TOPLEFT", 18, -160); phdr:SetText("POSITION")
  local zlab = newText(bf, FONT.body, 12, TEXT, "LEFT"); zlab:SetPoint("TOPLEFT", 18, -190); zlab:SetText("Zone")
  local zoneBtns, zPrev = {}, nil
  for i = 3, 1, -1 do   -- reverse → Corner ends up leftmost
    local zc = ({ { "corner", "Corner" }, { "center", "Center" }, { "extension", "Plate" } })[i]
    local b = flatButton(bf, 60, 22, COLOR.heroic, zc[2], 11)
    if zPrev then b:SetPoint("TOPRIGHT", zPrev, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -18, -188) end
    b:SetScript("OnClick", function()
      local c = ensureCount(); c.zone = zc[1]
      for _, e in ipairs(zoneBtns) do e.b:SetActive(e.z == c.zone) end; reapply()
    end)
    zoneBtns[#zoneBtns + 1] = { b = b, z = zc[1] }; zPrev = b
  end

  local oxRow = sliderRow(bf, -222, "Offset X", -40, 40, 1,
    function() local c = countData(); return (c and c.offsetX) or 0 end,
    function(v) local c = ensureCount(); c.offsetX = v; reapply() end,
    function(v) return v .. "px" end)
  local oyRow = sliderRow(bf, -266, "Offset Y", -40, 40, 1,
    function() local c = countData(); return (c and c.offsetY) or 0 end,
    function(v) local c = ensureCount(); c.offsetY = v; reapply() end,
    function(v) return v .. "px" end)

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -306); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Styles the charge / stack / item count. Corner = Blizzard's spot on the icon; Plate centres it in the plate half (2:1 plate shapes only).")
  bf:SetHeight(344)
  s.refresh = function()
    local c = countData()
    local on = countOn()
    en:refresh(); cs:refresh(); sizeRow:refresh(); oxRow:refresh(); oyRow:refresh(); fontBtn:refresh()
    cs.swatch:EnableMouse(on); cs.swatch:SetAlpha(on and 1 or 0.35)
    sizeRow:setEnabled(on); oxRow:setEnabled(on); oyRow:setEnabled(on)
    fontBtn:SetEnabled(on)
    for _, e in ipairs(zoneBtns) do e.b:SetActive(on and ((c and c.zone) or "corner") == e.z); e.b:SetEnabled(on) end
  end
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
  -- FILL (cast fills up, channel drains).
  local flab = newText(bf, FONT.body, 12, TEXT, "LEFT"); flab:SetPoint("TOPLEFT", 18, -14); flab:SetText("Fill color")
  local fcs = colorSwatch(bf,
    function() return GB.db and GB.db.castFillColor end,
    function(c) if GB.db then GB.db.castFillColor = c end end)
  fcs.swatch:SetPoint("TOPRIGHT", -18, -12)
  rows[#rows + 1] = fcs

  local opRow = sliderRow(bf, -46, "Opacity", 0, 1, 0.05,
    function() return (GB.db and GB.db.castFillAlpha) or 0.55 end,
    function(v) if GB.db then GB.db.castFillAlpha = v end end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  rows[#rows + 1] = opRow

  local dirR = dirRow(bf, -96, "Direction",
    function() return (GB.db and GB.db.castDrainDir) or "up" end,
    function(d) if GB.db then GB.db.castDrainDir = d end end)
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
  sl:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self._seek = true; seek(self) end end)
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
  hint:SetText("Availability tints react to Blizzard's own checks (no preview — test on the bars). Out-of-range matches the red keybind; unusable/mana fire for wrong form, missing resources, etc.")
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

  -- Caption tucks just below the construction (below the plate when it extends
  -- downward) so it never sits under the plate.
  if previewCaption then
    previewCaption:ClearAllPoints()
    previewCaption:SetPoint("TOP", previewFrame, "BOTTOM", 0, -(previewExtB + 14))
    previewCaption:SetPoint("LEFT", previewFrame:GetParent(), "LEFT", 10, 0)
    previewCaption:SetPoint("RIGHT", previewFrame:GetParent(), "RIGHT", -10, 0)
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
function C:PlayPreviewFlash()
  if not (previewFlash and previewIcon) then return end
  if not (GB.db and GB.db.finishFlash) then return end
  previewFlash:SetTexture(GB.Skin:GlowArt())
  local c = GB.db.finishFlashColor or { 1, 0.9, 0.5 }
  previewFlash:SetVertexColor(c[1], c[2], c[3])
  -- Anchor the FRAME so the scale bursts from centre; plate mode spans the full 2:1
  -- construction (the bars' flash traces constructRef), else the icon.
  anchorPreviewOverlay(previewFlashFrame, (128 / 80 - 1) / 2, 0, previewPlateOn and previewFrame or nil)
  previewFlashFrame:SetAlpha(1)
  previewFlashAnim:Stop(); previewFlashAnim:Play()
end

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
  if previewCaption then previewCaption:SetText(STATE_DESC[previewState] or PREVIEW_CAPTION_DEFAULT) end
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
  if previewCaption then previewCaption:SetText(STATE_DESC[triggerKey] or PREVIEW_CAPTION_DEFAULT) end
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

local function buildPreviewPane(parent)
  local pane = CreateFrame("Frame", nil, parent)
  pane:SetPoint("TOPLEFT", 0, TITLE_DIV_Y - 1)
  pane:SetPoint("BOTTOMLEFT", 0, FOOTER_H)
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

  local cap = newText(pane, FONT.body, 10, MUTE, "CENTER")
  cap:SetPoint("TOP", frame, "BOTTOM", 0, -16); cap:SetPoint("LEFT", 10, 0); cap:SetPoint("RIGHT", -10, 0)
  cap:SetJustifyH("CENTER"); cap:SetText(PREVIEW_CAPTION_DEFAULT)
  previewCaption = cap   -- RefreshPreview re-anchors it below the construction (below the plate)
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

  -- Title bar
  local mark = newText(panel, FONT.title, 21, { r = 1, g = 1, b = 1 }, "LEFT")
  mark:SetPoint("TOPLEFT", 16, -15); mark:SetText("GLOOM'S BARS")
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
  local prof = flatButton(panel, 118, 24, COLOR.heroic, "Profile: Default", 11); prof:SetBase(0.2)
  prof:SetPoint("BOTTOMRIGHT", -14, 14)

  -- Left preview pane + vertical divider
  buildPreviewPane(panel)
  local vdiv = panel:CreateTexture(nil, "ARTWORK"); vdiv:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  vdiv:SetWidth(1); vdiv:SetPoint("TOPLEFT", PREVIEW_W, TITLE_DIV_Y); vdiv:SetPoint("BOTTOMLEFT", PREVIEW_W, FOOTER_H)

  -- Body: a scroll frame holding the accordion (right of the preview pane).
  -- The section content grows past the window height, so it scrolls (mouse wheel).
  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", PREVIEW_W + 1, TITLE_DIV_Y - 1)
  scroll:SetPoint("BOTTOMRIGHT", -8, FOOTER_H + 1)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 42)))
  end)
  bodyContainer = CreateFrame("Frame", nil, scroll)
  bodyContainer:SetSize(PANEL_W - PREVIEW_W - 9, 10)
  scroll:SetScrollChild(bodyContainer)

  -- Custom thin scrollbar (shared helper): orange thumb + click-to-jump + drag + wheel.
  -- The accordion grows/shrinks as sections open; the bar's OnUpdate tracks it.
  makeScrollbar(panel, scroll, function(b)
    b:SetPoint("TOPRIGHT", -4, TITLE_DIV_Y - 2); b:SetPoint("BOTTOMRIGHT", -4, FOOTER_H + 2)
  end)

  -- Sections (mockup order). Bar layout + Apply to bars are still stubs.
  makeSection("Shape & icon", buildShapeSection)
  makeSection("Plate", buildPlateSection)
  makeSection("Decoration layers", buildDecorSection)
  makeSection("Text", buildTextSection)
  makeSection("Charge count", buildCountSection)
  makeSection("Glows", buildGlowsSection)
  makeSection("Animations", buildAnimsSection)
  makeSection("Cast & channel", buildCastSection)
  makeSection("Cooldown & availability", buildCooldownSection)
  makeSection("Empty slots", buildEmptySection)
  makeSection("Bar layout", stubBody)
  makeSection("Apply to bars", stubBody)

  -- All sections start CLOSED (Jason 2026-07-20 — easier to find the one you want
  -- than scrolling past a large open panel).
  relayout()

  tinsert(UISpecialFrames, "GloomsBarsConfig")   -- Escape closes it
  C:RefreshPreview()
  C:SetPreviewState("idle")
end

function C:Refresh()
  if not panel then return end
  if panel._enableToggle then panel._enableToggle:refresh() end
  for _, s in ipairs(sections) do if s.refresh then s.refresh() end end
  C:RefreshPreview()
  C:SetPreviewState(previewState)
end

function C:Toggle()
  if not panel then BuildPanel(); C:Refresh(); return end
  if panel:IsShown() then panel:Hide() else panel:Show(); C:Refresh() end
end
