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
local function sliderRow(parent, yTop, labelText, minV, maxV, step, get, set, fmt)
  local lab = newText(parent, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, yTop); lab:SetText(labelText)
  local val = newText(parent, FONT.label, 11, TEXT, "RIGHT"); val:SetPoint("TOPRIGHT", -18, yTop)
  local sl = CreateFrame("Slider", nil, parent)
  sl:SetPoint("TOPLEFT", 18, yTop - 20); sl:SetPoint("TOPRIGHT", -18, yTop - 20); sl:SetHeight(6)
  sl:SetOrientation("HORIZONTAL"); sl:SetMinMaxValues(minV, maxV); sl:SetValueStep(step); sl:SetObeyStepOnDrag(true)
  local track = sl:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints()
  track:SetColorTexture(COLOR.heroic.r, COLOR.heroic.g, COLOR.heroic.b, 0.20)
  local thumb = sl:CreateTexture(nil, "ARTWORK"); thumb:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1)
  thumb:SetSize(5, 20); sl:SetThumbTexture(thumb)
  local applying = false
  local function show(v) val:SetText(fmt and fmt(v) or tostring(v)) end
  sl:SetScript("OnValueChanged", function(_, v) if not applying then set(v) end; show(v) end)
  local row = {}
  function row:refresh() applying = true; local v = get() or minV; sl:SetValue(v); show(v); applying = false end
  function row:setEnabled(on) sl:SetEnabled(on); sl:SetAlpha(on and 1 or 0.35) end
  function row:SetShown(on) lab:SetShown(on); val:SetShown(on); sl:SetShown(on) end
  row:refresh()
  return row
end

-- Color swatch — a solid button that opens the game ColorPickerFrame (modern
-- SetupColorPickerAndShow API, present on this client, with a fallback). Returns
-- { swatch, refresh }.
local function colorSwatch(parent, get, set)
  local sw = CreateFrame("Button", nil, parent); sw:SetSize(28, 20)
  local tex = sw:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints()
  addEdges(sw, COLOR.rim, 1)
  local function update() local c = get() or { 1, 1, 1 }; tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1) end
  sw:SetScript("OnClick", function()
    local c = get() or { 1, 1, 1 }
    local function apply()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      set({ r, g, b }); update()
    end
    local info = { hasOpacity = false, r = c[1], g = c[2], b = c[3], swatchFunc = apply }
    if ColorPickerFrame.SetupColorPickerAndShow then ColorPickerFrame:SetupColorPickerAndShow(info)
    else ColorPickerFrame.func = apply; ColorPickerFrame:SetColorRGB(c[1], c[2], c[3]); ColorPickerFrame:Show() end
  end)
  update()
  local row = { swatch = sw }
  function row:refresh() update() end
  return row
end

-- --------------------------------------------------------------------------
-- Window shell + one-open accordion
-- --------------------------------------------------------------------------
local PANEL_W, PANEL_H = 620, 640
local PREVIEW_W = 210            -- left preview pane width
local TITLE_DIV_Y = -48          -- title bar divider
local FOOTER_H = 52              -- footer strip height (divider sits here above bottom)
local SECTION_HDR_H = 36

local panel, bodyContainer
local sections = {}
local previewFrame, previewIcon, previewMask, previewGlow, previewRing, previewCD
local previewBorder, previewBorderMask
local previewChips, previewState = {}, "idle"

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

function C:ToggleSection(s)
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

-- The visible icon's "natural" size = the Edit-Mode button size; the sizing
-- sliders start here until an explicit width/height override is set.
local function naturalIconSize()
  local b = _G["ActionButton1"]
  local w = b and b.GetWidth and b:GetWidth()
  return (w and w > 0) and math.floor(w + 0.5) or 45
end

-- Shape & icon — shape preset + corner radius + icon size, wired to the real
-- engine. Corners are all-or-nothing: Circle (its own mode), Rounded (all four
-- corners rounded at the radius level), or Square (all sharp). Per-corner MIXING
-- was removed 2026-07-19 — a mixed pattern can't render cleanly on a non-square
-- icon (the pill covers rounded-non-square). Shape + radius apply live (fresh
-- masks); zoom + size are live re-anchors. The Corner radius row is shown ONLY
-- for Rounded (it's meaningless for Circle/Square), and the icon controls slide
-- up to fill its place so there's never a floating gap.
local function buildShapeSection(bf, s)
  local RADIUS_LABELS = { [0] = "Subtle", [1] = "Soft", [2] = "Medium", [3] = "Round", [4] = "Bold", [5] = "Full" }

  local function parse()  -- db.shape → pattern {tl,tr,bl,br}, radius level, isCircle
    local sh = GB.db and GB.db.shape
    if sh == "circle" then return { 1, 1, 1, 1 }, 2, true end
    local a, b, c, d, r = tostring(sh):match("^corner%-(%d)(%d)(%d)(%d)%-r(%d)$")
    if a then return { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }, tonumber(r), false end
    return { 1, 1, 1, 1 }, 2, false
  end
  local function isCircle() return (GB.db and GB.db.shape) == "circle" end
  local function isHexagon() return (GB.db and GB.db.shape) == "hexagon" end
  local function isSquare() local p, _, c = parse(); return (not c) and p[1] == 0 and p[2] == 0 and p[3] == 0 and p[4] == 0 end
  -- Rounded = a corner-pattern shape with at least one round corner. Circle and
  -- Hexagon are their own FIXED modes (parse() falls through to the all-round
  -- default for them, so guard explicitly) — no corner radius applies.
  local function isRounded()
    if isCircle() or isHexagon() then return false end
    local p, _, c = parse(); return (not c) and (p[1] == 1 or p[2] == 1 or p[3] == 1 or p[4] == 1)
  end
  local function apply(pattern, level)
    local nm = ("corner-%d%d%d%d-r%d"):format(pattern[1], pattern[2], pattern[3], pattern[4], level)
    if GB.Skin then GB.Skin:SetShape(nm) else GB.db.shape = nm end
  end

  -- Shape presets (four now — narrower to fit one row)
  local lbl = newText(bf, FONT.body, 12, TEXT, "LEFT"); lbl:SetPoint("TOPLEFT", 18, -13); lbl:SetText("Shape")
  local presetBtns = {
    { label = "Circle",  set = function() if GB.Skin then GB.Skin:SetShape("circle") else GB.db.shape = "circle" end end,
      on = isCircle },
    -- Keep the current level when already Rounded; otherwise default to a visible round.
    { label = "Rounded", set = function() local _, lv = parse(); apply({ 1, 1, 1, 1 }, isRounded() and lv or 3) end,
      on = isRounded },
    { label = "Square",  set = function() apply({ 0, 0, 0, 0 }, 0) end,
      on = isSquare },
    -- Hexagon is fixed-aspect → force a SQUARE icon (no separate width/height).
    { label = "Hexagon", set = function()
        local sz = (GB.db and GB.db.iconW) or naturalIconSize()
        GB.db.iconLockAspect, GB.db.iconAspect = true, 1
        if GB.Skin then GB.Skin:SetIconSize(sz, sz); GB.Skin:SetShape("hexagon")
        else GB.db.iconW, GB.db.iconH, GB.db.shape = sz, sz, "hexagon" end
      end, on = isHexagon },
  }
  local x = 18
  for _, p in ipairs(presetBtns) do
    local b = flatButton(bf, 70, 24, COLOR.heroic, p.label, 11)
    b:SetPoint("TOPLEFT", x, -36); x = x + 74
    p.btn = b
    b:SetScript("OnClick", function() p.set(); s.refresh(); C:RefreshPreview() end)
  end

  -- Corner radius — discrete levels (baked masks, so it snaps); r5 = fully round.
  -- Shown only for Rounded (see s.refresh); at -74 (where its own label sits).
  local radiusRow = sliderRow(bf, -74, "Corner radius", 0, 5, 1,
    function() local _, lv = parse(); return lv end,
    function(v) if not isRounded() then return end; local pat = parse(); apply(pat, v); C:RefreshPreview() end,
    function(v) return RADIUS_LABELS[v] or tostring(v) end)

  -- The icon controls live in a group we slide up one row when the radius row is
  -- hidden (Circle/Square), so nothing floats. Offsets below are relative to it.
  local iconGroup = CreateFrame("Frame", nil, bf)
  iconGroup:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -106)
  iconGroup:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, -106)
  iconGroup:SetHeight(224)

  -- Icon zoom — live (SetTexCoord)
  local zoomRow = sliderRow(iconGroup, -12, "Icon zoom", 0, 0.30, 0.01,
    function() return GB.db and GB.db.zoom end,
    function(v) if GB.Skin then GB.Skin:SetZoom(v) end; C:PreviewZoom(v) end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)

  -- Icon width / height — resize the VISIBLE icon (hit area stays Edit Mode's)
  local wRow, hRow
  local function applySize()
    if GB.Skin then GB.Skin:SetIconSize(GB.db.iconW, GB.db.iconH) end
    C:RefreshPreview()
  end
  -- Lock aspect ratio = keep the CURRENT width:height ratio while resizing (not
  -- force square). The ratio is captured when lock is enabled; dragging one axis
  -- scales the other to match.
  local function lockRatio() return (GB.db and GB.db.iconAspect) or 1 end
  wRow = sliderRow(iconGroup, -56, "Icon width", 16, 96, 1,
    function() return (GB.db and GB.db.iconW) or naturalIconSize() end,
    function(v)
      GB.db.iconW = v
      if GB.db.iconLockAspect then GB.db.iconH = math.floor(v * lockRatio() + 0.5); hRow:refresh()
      elseif not GB.db.iconH then GB.db.iconH = naturalIconSize() end
      applySize()
    end,
    function(v) return v .. "px" end)
  hRow = sliderRow(iconGroup, -100, "Icon height", 16, 96, 1,
    function() return (GB.db and GB.db.iconH) or naturalIconSize() end,
    function(v)
      GB.db.iconH = v
      if GB.db.iconLockAspect then GB.db.iconW = math.floor(v / lockRatio() + 0.5); wRow:refresh()
      elseif not GB.db.iconW then GB.db.iconW = naturalIconSize() end
      applySize()
    end,
    function(v) return v .. "px" end)

  -- Icon SIZE — the single control for fixed-aspect shapes (Hexagon): one square
  -- size, no separate width/height. Shown only for Hexagon (s.refresh), sharing
  -- the width row's slot (-56) so the two never appear together.
  local sizeRow = sliderRow(iconGroup, -56, "Icon size", 16, 96, 1,
    function() return (GB.db and GB.db.iconW) or naturalIconSize() end,
    function(v) GB.db.iconW, GB.db.iconH = v, v; applySize() end,
    function(v) return v .. "px" end)

  local lockLbl = newText(iconGroup, FONT.body, 12, TEXT, "LEFT"); lockLbl:SetPoint("TOPLEFT", 18, -138); lockLbl:SetText("Lock aspect ratio")
  local lockTog = makeToggle(iconGroup,
    function() return GB.db and GB.db.iconLockAspect end,
    function(v)
      GB.db.iconLockAspect = v
      if v then
        -- Capture the current shape's ratio so locking PRESERVES it (no reset to square).
        local w = GB.db.iconW or naturalIconSize()
        local h = GB.db.iconH or naturalIconSize()
        GB.db.iconAspect = (w > 0) and (h / w) or 1
      end
    end)
  lockTog:SetPoint("TOPRIGHT", -18, -136)

  -- Crop to fill vs stretch — how a non-square icon shows the (square) spell art.
  local fillLbl = newText(iconGroup, FONT.body, 12, TEXT, "LEFT"); fillLbl:SetPoint("TOPLEFT", 18, -166); fillLbl:SetText("Crop to fill")
  local fillTog = makeToggle(iconGroup,
    function() return not (GB.db and GB.db.iconFill == "stretch") end,
    function(v)
      if GB.Skin then GB.Skin:SetIconFill(v and "fill" or "stretch") else GB.db.iconFill = v and "fill" or "stretch" end
      C:RefreshPreview()
    end)
  fillTog:SetPoint("TOPRIGHT", -18, -164)

  local hint = newText(iconGroup, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -196); hint:SetPoint("RIGHT", iconGroup, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Size is the VISIBLE icon; the clickable hit area stays Edit Mode's. Unlock aspect for non-square; Crop to fill keeps art undistorted.")
  bf:SetHeight(336)   -- initial (Rounded); s.refresh sets the real height per shape

  s.refresh = function()
    for _, p in ipairs(presetBtns) do p.btn:SetActive(p.on()) end
    local showRadius = isRounded()   -- Corner radius: only for Rounded
    local hex = isHexagon()          -- Hexagon: fixed-aspect → single square size
    radiusRow:SetShown(showRadius)
    -- Icon controls swap by shape: Hexagon shows one "Icon size" and hides width/
    -- height/lock/crop (sizeRow shares the width slot); flexible shapes show the
    -- full set. The hint + heights move so nothing floats; relayout() lets the
    -- sections below follow the height change.
    sizeRow:SetShown(hex)
    wRow:SetShown(not hex); hRow:SetShown(not hex)
    lockLbl:SetShown(not hex); lockTog:SetShown(not hex)
    fillLbl:SetShown(not hex); fillTog:SetShown(not hex)
    hint:SetPoint("TOPLEFT", 18, hex and -100 or -196)
    hint:SetText(hex
      and "Size is the VISIBLE icon (hexagons stay square, fixed shape); the clickable hit area stays Edit Mode's."
      or "Size is the VISIBLE icon; the clickable hit area stays Edit Mode's. Unlock aspect for non-square; Crop to fill keeps art undistorted.")
    local yIcon = showRadius and -106 or -62
    iconGroup:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, yIcon)
    iconGroup:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, yIcon)
    bf:SetHeight(hex and 200 or (showRadius and 336 or 292))
    if showRadius then radiusRow:refresh() end
    zoomRow:refresh()
    if hex then sizeRow:refresh()
    else wRow:refresh(); hRow:refresh(); lockTog:refresh(); fillTog:refresh() end
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

-- Construction — the extension zone below the icon (extra plate real estate). A
-- lighter re-anchor (ReapplyDecor) applies it; no mask recreation needed.
local function buildConstructionSection(bf, s)
  -- Centered slider: 0 = no plate, LEFT (negative) extends ABOVE the icon, RIGHT
  -- (positive) BELOW — a signed % of icon height (construction.extendPct). The
  -- hexagon is a fixed shape → no extension (slider disabled).
  local function isHex() return (GB.db and GB.db.shape) == "hexagon" end
  local function get()
    if isHex() then return 0 end
    local c = GB.db and GB.db.styleData and GB.db.styleData.construction
    if not c then return 0 end
    if c.extendPct ~= nil then return c.extendPct end
    return c.extendBottomPct or 0   -- legacy below-only key
  end
  local row = sliderRow(bf, -14, "Extend plate", -0.9, 0.9, 0.05, get,
    function(v)
      if isHex() then return end
      local st = GB.db.styleData; st.construction = st.construction or {}
      st.construction.extendPct = v
      st.construction.extendBottomPct = nil   -- superseded by the signed key
      if GB.Skin then GB.Skin:ReapplyDecor() end
      C:RefreshPreview()
    end,
    function(v)
      if math.abs(v) < 0.001 then return "None" end
      return (v < 0 and "Above " or "Below ") .. math.floor(math.abs(v) * 100 + 0.5) .. "%"
    end)
  -- Continuous shape: ON = icon + plate wrapped as one shape; OFF = rounded icon
  -- on a crisp square plate (squares off the junction).
  local contLbl = newText(bf, FONT.body, 12, TEXT, "LEFT"); contLbl:SetPoint("TOPLEFT", 18, -54); contLbl:SetText("Continuous shape")
  local contTog = makeToggle(bf,
    function() local c = GB.db and GB.db.styleData and GB.db.styleData.construction; return not (c and c.continuous == false) end,
    function(v)
      local st = GB.db.styleData; st.construction = st.construction or {}
      st.construction.continuous = v
      if GB.Skin then GB.Skin:ReapplyDecor() end
      C:RefreshPreview()
    end)
  contTog:SetPoint("TOPRIGHT", -18, -52)

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -86); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  bf:SetHeight(112)
  s.refresh = function()
    local hex = isHex()
    row:setEnabled(not hex)
    row:refresh()
    contTog:EnableMouse(not hex); contTog:SetAlpha(hex and 0.35 or 1); contTog:refresh()
    hint:SetText(hex
      and "The hexagon is a fixed shape — no plate extension."
      or "Centered slider: LEFT = plate above, RIGHT = below. Continuous = one shape; off = rounded icon + square plate.")
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
    function(c) local l = ensureGradLayer(); l.color = c; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)
  cs.swatch:SetPoint("TOPRIGHT", -18, -44)

  local bleedRow = sliderRow(bf, -78, "Fade start", 0, 1, 0.05,
    function() local l = gradLayer(); return (l and l.bleedPct) or 0.5 end,
    function(v) local l = ensureGradLayer(); l.bleedPct = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)

  -- Border — a colored frame around ANY shape (a shape-copy behind the icon,
  -- peeking out by the thickness). On/off + color + thickness + opacity.
  local blab = newText(bf, FONT.head, 13, COLOR.purple, "LEFT"); blab:SetPoint("TOPLEFT", 18, -118); blab:SetText("BORDER")
  local ben = makeToggle(bf,
    function() local b = borderData(); return b and b.enabled end,
    function(v) local b = ensureBorder(); b.enabled = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)
  ben:SetPoint("TOPRIGHT", -18, -116)

  local bclab = newText(bf, FONT.body, 12, TEXT, "LEFT"); bclab:SetPoint("TOPLEFT", 18, -148); bclab:SetText("Color")
  local bcs = colorSwatch(bf,
    function() local b = borderData(); return b and b.color end,
    function(c) local b = ensureBorder(); b.color = c; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end)
  bcs.swatch:SetPoint("TOPRIGHT", -18, -146)

  local thickRow = sliderRow(bf, -180, "Thickness", 1, 12, 1,
    function() local b = borderData(); return (b and b.thickness) or 3 end,
    function(v) local b = ensureBorder(); b.thickness = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end,
    function(v) return v .. "px" end)

  local bopRow = sliderRow(bf, -224, "Opacity", 0, 1, 0.05,
    function() local b = borderData(); return (b and b.alpha) or 1 end,
    function(v) local b = ensureBorder(); b.alpha = v; if GB.Skin then GB.Skin:ReapplyDecor() end; C:RefreshPreview() end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)

  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -268); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Gradient fills the extension; Border frames any shape. More layer kinds later.")
  bf:SetHeight(292)
  s.refresh = function()
    en:refresh(); cs:refresh(); bleedRow:refresh()
    ben:refresh(); bcs:refresh(); thickRow:refresh(); bopRow:refresh()
  end
end

-- State highlights — hover / selected / flash tints + intensity. Live-safe
-- (SetVertexColor / SetAlpha); the preview's state chips show each one.
local function buildStateSection(bf, s)
  local rows = {}
  local function colorRow(yTop, label, which)
    local lab = newText(bf, FONT.body, 12, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 18, yTop); lab:SetText(label)
    local cs = colorSwatch(bf,
      function() return GB.db and GB.db.stateColors and GB.db.stateColors[which] end,
      function(c) if GB.Skin then GB.Skin:SetStateColor(which, c) end; C:SetPreviewState(previewState) end)
    cs.swatch:SetPoint("TOPRIGHT", -18, yTop + 2)
    rows[#rows + 1] = cs
  end
  colorRow(-14, "Hover", "hover")
  colorRow(-42, "Selected", "selected")
  colorRow(-70, "Flash", "flash")
  local intRow = sliderRow(bf, -104, "Intensity", 0, 1, 0.05,
    function() return GB.db and GB.db.stateIntensity end,
    function(v) if GB.Skin then GB.Skin:SetStateIntensity(v) end; C:SetPreviewState(previewState) end,
    function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  rows[#rows + 1] = intRow
  local hint = newText(bf, FONT.body, 11, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", 18, -142); hint:SetPoint("RIGHT", bf, "RIGHT", -16, 0); hint:SetJustifyH("LEFT")
  hint:SetText("Use the Hover / Selected / Flash preview chips to see each color.")
  bf:SetHeight(166)
  s.refresh = function() for _, r in ipairs(rows) do r:refresh() end end
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
  { "idle", "Idle" }, { "proc", "Proc" }, { "cooldown", "Cooldown" },
  { "hover", "Hover" }, { "selected", "Selected" }, { "flash", "Flash" },
}
local RING_TINT = { hover = { 1, 0.82, 0.35 }, selected = { 0.45, 0.75, 1 }, flash = { 1, 0.25, 0.25 } }

function C:RefreshPreview()
  if not previewIcon then return end
  local shp = GB:GetShape()
  -- Reflect the icon's aspect ratio, fit within a ~104px box.
  local iw, ih = (GB.db and GB.db.iconW) or 1, (GB.db and GB.db.iconH) or 1
  local base = 104
  local pw, ph = base, base
  if iw > 0 and ih > 0 then
    if iw >= ih then pw, ph = base, base * ih / iw else pw, ph = base * iw / ih, base end
  end
  previewFrame:SetSize(pw, ph)
  previewIcon:SetTexture(sampleIconTexture())
  if previewMask then previewIcon:RemoveMaskTexture(previewMask) end
  previewMask = previewFrame:CreateMaskTexture()
  -- Match the engine: use the aspect-correct mask for a non-square preview.
  local aSrc = GB.Skin:AspectMask(pw, ph)
  previewMask:SetTexture(aSrc or shp.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  local growX = pw * (256 / 240 - 1) / 2
  local growY = ph * (256 / 240 - 1) / 2
  previewMask:ClearAllPoints()
  previewMask:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", -growX, growY)
  previewMask:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", growX, -growY)
  previewIcon:AddMaskTexture(previewMask)
  -- Same cover-fit crop as the engine so the preview matches the bars (part a).
  previewIcon:SetTexCoord(GB.Skin:TexCoordFor(previewIcon:GetWidth(), previewIcon:GetHeight()))
  previewGlow:SetTexture(shp.glow)   -- proc glow not aspect-varied yet (matches the bars)
  previewRing:SetTexture(GB.Skin:AspectRing(pw, ph) or shp.ring)
  if previewCD.SetSwipeTexture then previewCD:SetSwipeTexture(GB.Skin:AspectSwipe(pw, ph) or shp.swipe) end
  -- Border preview — the engine's shape-backing (a shape copy behind the icon,
  -- peeking out by the thickness). Fresh mask per refresh (cheap; dodges the
  -- live-mask re-render quirk).
  local bd = GB.db and GB.db.styleData and GB.db.styleData.border
  if bd and bd.enabled and (bd.thickness or 0) > 0 then
    local t, col = bd.thickness, bd.color or { 0, 0, 0 }
    previewBorder:ClearAllPoints()
    previewBorder:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", -t, t)
    previewBorder:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", t, -t)
    previewBorder:SetVertexColor(col[1], col[2], col[3], bd.alpha or 1)
    if previewBorderMask then previewBorder:RemoveMaskTexture(previewBorderMask) end
    previewBorderMask = previewFrame:CreateMaskTexture()
    previewBorderMask:SetTexture(GB.Skin:AspectMask(pw + 2 * t, ph + 2 * t) or shp.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local bgx, bgy = (pw + 2 * t) * (256 / 240 - 1) / 2, (ph + 2 * t) * (256 / 240 - 1) / 2
    previewBorderMask:ClearAllPoints()
    previewBorderMask:SetPoint("TOPLEFT", previewBorder, "TOPLEFT", -bgx, bgy)
    previewBorderMask:SetPoint("BOTTOMRIGHT", previewBorder, "BOTTOMRIGHT", bgx, -bgy)
    previewBorder:AddMaskTexture(previewBorderMask)
    previewBorder:Show()
  else
    previewBorder:Hide()
  end
end

function C:PreviewZoom(v)
  if previewIcon then
    previewIcon:SetTexCoord(GB.Skin:TexCoordFor(previewIcon:GetWidth(), previewIcon:GetHeight()))
  end
end

function C:SetPreviewState(st)
  previewState = st or "idle"
  if previewGlow then previewGlow:SetShown(previewState == "proc") end
  if previewCD then
    if previewState == "cooldown" then previewCD:Show(); previewCD:SetCooldown(GetTime(), 12) else previewCD:Hide() end
  end
  if previewIcon then previewIcon:SetDesaturated(previewState == "cooldown") end
  local isRing = RING_TINT[previewState] ~= nil
  if previewRing then
    previewRing:SetShown(isRing)
    if isRing then
      local sc = GB.db and GB.db.stateColors
      local c = (sc and sc[previewState]) or RING_TINT[previewState]
      previewRing:SetVertexColor(c[1], c[2], c[3])
      previewRing:SetAlpha((GB.db and GB.db.stateIntensity) or 1)
    end
  end
  for s2, chip in pairs(previewChips) do chip:SetActive(s2 == previewState) end
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

  -- sample construction (icon at 104px; grows when decorations get wired)
  local frame = CreateFrame("Frame", nil, pane); frame:SetSize(104, 104); frame:SetPoint("TOP", 0, -132)
  previewFrame = frame
  previewGlow = frame:CreateTexture(nil, "BACKGROUND"); previewGlow:SetPoint("TOPLEFT", -16, 16); previewGlow:SetPoint("BOTTOMRIGHT", 16, -16)
  previewGlow:SetBlendMode("ADD"); previewGlow:SetVertexColor(1, 0.77, 0.30); previewGlow:Hide()
  previewIcon = frame:CreateTexture(nil, "ARTWORK"); previewIcon:SetAllPoints()
  previewCD = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate"); previewCD:SetAllPoints(previewIcon)
  previewCD:SetDrawEdge(false); previewCD:SetDrawBling(false); previewCD:Hide()
  previewRing = frame:CreateTexture(nil, "OVERLAY"); previewRing:SetPoint("TOPLEFT", -4, 4); previewRing:SetPoint("BOTTOMRIGHT", 4, -4)
  previewRing:SetBlendMode("ADD"); previewRing:Hide()
  previewBorder = frame:CreateTexture(nil, "BACKGROUND", nil, -2)   -- behind the icon; peeks out as the border
  previewBorder:SetTexture("Interface\\Buttons\\WHITE8X8"); previewBorder:Hide()

  local cap = newText(pane, FONT.body, 10, MUTE, "CENTER")
  cap:SetPoint("TOP", frame, "BOTTOM", 0, -16); cap:SetPoint("LEFT", 10, 0); cap:SetPoint("RIGHT", -10, 0)
  cap:SetJustifyH("CENTER"); cap:SetText("Sample of the visible skin. Your clickable hit area stays Edit Mode's size.")
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

  -- Sections (mockup order). Shape & icon is wired; the rest are stubbed.
  makeSection("Shape & icon", buildShapeSection)
  makeSection("Construction", buildConstructionSection)
  makeSection("Decoration layers", buildDecorSection)
  makeSection("Text", stubBody)
  makeSection("Proc glow", stubBody)
  makeSection("State highlights", buildStateSection)
  makeSection("Cooldown & availability", stubBody)
  makeSection("Bar layout", stubBody)
  makeSection("Apply to bars", stubBody)

  sections[1].open = true
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
