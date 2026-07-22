-- Skin.lua — Gloom's Bars skin engine v0 (GB.Skin)
--
-- Applies the session-1 proven recipe (docs/API-NOTES.md §2) to all 8 bars:
-- icon zoom crop → bundled padded circle mask → square slot art suppressed.
--
-- Re-assertion strategy, source-verified against wow-ui-source live branch at
-- exactly 12.0.7 build 68453 (docs/API-NOTES.md §4):
--   • UpdateButtonArt is the ONLY Lua path that re-shows SlotArt/SlotBackground
--     and re-sets the Normal/Pushed border atlases → per-button hooksecurefunc.
--     (Mixin methods are copied onto frames — hooking the mixin table would
--     miss existing buttons; GloomsAuras learning.)
--   • The press-cycle border re-show is the C-side Button state machine, which
--     toggles Show/Hide but never alpha → suppress via SetAlpha(0), not Hide().
--   • Nothing in Blizzard_ActionBar calls SetTexCoord on .icon → zoom persists.
--   • UpdateUsable's icon vertex-color changes are Blizzard's range/usability
--     tint — deliberately untouched (pure skin: Blizzard behavior keeps working).

local GB = _G.GloomsBars

local Skin = { enabled = false }
GB.Skin = Skin

local ZOOM = 0.08   -- default icon zoom-crop; GB.db.zoom overrides it (live via Skin:SetZoom)
local function zoomVal() return (GB.db and GB.db.zoom) or ZOOM end
-- The circle art is padded to 240/256 of its canvas (edge-bleed rule,
-- API-NOTES §2); oversize the mask region so the circle spans the icon.
local GROW_RATIO = (256 / 240 - 1) / 2

-- Icon texcoord for a w×h frame at the current zoom + fill mode. The spell art
-- is square, so mapping the square zoom-crop onto a non-square icon STRETCHES it
-- (Jason's QA feedback). "fill" (cover, default) keeps the art's aspect and
-- CROPS the overflow dimension so a non-square icon shows undistorted art;
-- "stretch" is Blizzard's default look (distorts). Square frames → identical.
function Skin:TexCoordFor(w, h)
  local z = zoomVal()
  local mode = (GB.db and GB.db.iconFill) or "fill"
  if mode == "stretch" or not (w and h) or w <= 0 or h <= 0 or math.abs(w - h) < 0.5 then
    return z, 1 - z, z, 1 - z
  end
  local s = 1 - 2 * z   -- side of the square zoom-crop, in UV space
  if w >= h then
    local ch = s * h / w
    return z, 1 - z, 0.5 - ch / 2, 0.5 + ch / 2   -- full width, centered slice of height
  else
    local cw = s * w / h
    return 0.5 - cw / 2, 0.5 + cw / 2, z, 1 - z   -- full height, centered slice of width
  end
end
local function applyTexCoord(icon)
  icon:SetTexCoord(Skin:TexCoordFor(icon:GetWidth(), icon:GetHeight()))
end

local records = {}   -- [button] = { mask, texCoord, active, iconMaskRemoved }

-- Button-state art (hover/checked/flash): REPLACED with our round ring-glow,
-- not masked — runtime mask attachment failed to clip the highlight in QA
-- (API-NOTES §2), and we want our own art here for the design language anyway.
-- Deeper overlay FRAMES (SpellCastAnimFrame, AssistedCombatRotationFrame,
-- AutoCastOverlay, the spell-alert proc glow) are a later pass.
local STATE_TINT = {
  highlight = { 1, 0.82, 0.35 },   -- gold hover
  checked   = { 0.45, 0.75, 1 },   -- blue active/auto-repeat
  flash     = { 1, 0.25, 0.25 },   -- red attack flash
  assist    = { 0.35, 0.75, 1 },   -- assisted-rotation suggestion (Blizzard-ish blue)
}
-- Hover/checked/flash tints + intensity are user-editable (Config UI → State
-- highlights). db.stateColors keys map to the engine's texture roles; fall back
-- to the defaults above.
local STATE_KEY = { highlight = "hover", checked = "selected", flash = "flash" }
local function stateColor(role)
  local sc = GB.db and GB.db.stateColors
  return (sc and sc[STATE_KEY[role]]) or STATE_TINT[role]
end
local function stateIntensity() return (GB.db and GB.db.stateIntensity) or 1 end
-- "Glow width": how far the state-highlight ring spreads past the icon, as a
-- per-axis anchor grow (AnchorConstruction ratio). db.stateWidth (0..1) maps into
-- [MIN..MAX]; the default (~0.5) lands a touch wider than the old fixed RING_FIT
-- rim so the highlight reads bolder (fixes the "too subtle" note), 0 hugs tight,
-- 1 blooms into a wide halo.
local STATE_WIDTH_MIN, STATE_WIDTH_MAX = 0.02, 0.26
local function stateWidthRatio()
  local w = (GB.db and GB.db.stateWidth) or 0.5
  if w < 0 then w = 0 elseif w > 1 then w = 1 end
  return STATE_WIDTH_MIN + w * (STATE_WIDTH_MAX - STATE_WIDTH_MIN)
end
function Skin:StateWidthRatio() return stateWidthRatio() end

-- Reskin the assisted-rotation helper (the persistent blue square): its
-- ActiveFrame.Border is a 128px square-ish atlas → our ring, tinted; the
-- rotating square FX is silenced. The frame is created LAZILY by
-- UpdateAssistedCombatRotationFrame → also hooked so late-created frames get
-- styled before they're seen. /reload restores.
local function StyleAssistedFrame(btn)
  local active = btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame.ActiveFrame
  if not active or active.gbStyled then return end
  local icon = btn.icon or btn.Icon
  if not icon then return end
  local grow = icon:GetWidth() * GROW_RATIO
  if active.Border then
    active.Border:SetTexture(GB:GetShape().ring)
    active.Border:SetVertexColor(unpack(STATE_TINT.assist))
    active.Border:ClearAllPoints()
    active.Border:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
    active.Border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
  end
  if active.Glow then active.Glow:SetAlpha(0) end
  active.gbStyled = true
end

-- Bundled fonts on the button text. Face swaps stick (Blizzard never re-sets
-- fonts, only the HotKey COLOR for the range indicator — which we keep,
-- API-NOTES §3). Sizes/flags stay Blizzard's for now; Config UI later.
local TEXT_FONT = {
  HotKey = "label",   -- GeneralSans-Semibold
  Count  = "bodyM",   -- GeneralSans-Medium
  Name   = "body",    -- GeneralSans-Regular (macro names)
}
local function StyleText(btn)
  for key, fontKey in pairs(TEXT_FONT) do
    local fs = btn[key]
    if fs and fs.GetFont then
      local _, size, flags = fs:GetFont()
      if size then
        fs:SetFont(GB.FONT[fontKey], size, flags)
      end
    end
  end
end

local function Suppress(btn)
  if btn.SlotBackground then btn.SlotBackground:Hide() end
  if btn.SlotArt then btn.SlotArt:Hide() end
  if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
  if btn.PushedTexture then btn.PushedTexture:SetAlpha(0) end
  -- Equipped-item green border (rounded-square, mismatched on a pill) — suppress
  -- via alpha-0 (Blizzard toggles it Show/Hide, so alpha sticks). API-NOTES §1.
  if btn.Border then btn.Border:SetAlpha(0) end
  -- Ground-target reticle: the green square `UI-HUD-ActionBar-Target` glow shown
  -- while a ground-target spell is on the cursor (event UNIT_SPELLCAST_RETICLE_
  -- TARGET → TargetReticleAnimFrame:Setup). Setup only Show()s + plays a ROTATE
  -- anim (never touches alpha), so alpha-0 sticks like the equipped border. Its
  -- square art clashes with our shape; our Selected (checked) ring conveys the
  -- pending state instead. (Sibling of the red InterruptDisplay we also suppress.)
  if btn.TargetReticleAnimFrame then btn.TargetReticleAnimFrame:SetAlpha(0) end
end

-- ---------------------------------------------------------------------------
-- Decoration engine — interprets GB.STYLES recipes (the design north star).
-- Plates are pooled per button (textures can't be destroyed, only reused) and
-- clipped by fresh per-plate shape masks (our-own-texture + fresh-mask = the
-- provably safe path). The HotKey override re-asserts via an UpdateHotkeys
-- post-hook (Blizzard re-anchors it top-right on every update).
-- ---------------------------------------------------------------------------
-- The construction = the icon plus an optional extension zone ABOVE or BELOW it
-- (extra visible real estate — textures may draw beyond the secure button). The
-- extension is a SIGNED percentage of icon height: construction.extendPct < 0 =
-- ABOVE, > 0 = BELOW (a centered slider). Legacy extendBottomPct (below-only) is
-- read as +below. The hexagon is a fixed shape → no extension.
local function ExtensionPct()
  if (GB.db and GB.db.shape) == "hexagon" then return 0 end
  local c = GB:GetStyle().construction
  if not c then return 0 end
  if c.extendPct ~= nil then return c.extendPct end
  return c.extendBottomPct or 0   -- legacy key (below)
end
-- Extension magnitude in px (for sizing / aspect); direction via ExtensionAbove.
local function ExtensionHeight(icon)
  return icon:GetHeight() * math.abs(ExtensionPct())
end
local function ExtensionAbove()
  return ExtensionPct() < 0
end

-- Continuous-OFF makes a HYBRID construction — a rounded icon on a SQUARE plate —
-- that no single all-round shape matches (its bottom, or top, is square). This
-- returns the mixed-corner pattern that DOES match (rounded on the icon end, sharp
-- on the plate end), for the glow + cast-fill to use; nil when there's nothing to
-- mix (continuous ON, no plate, or a non-rounded shape — circle/square/hexagon).
local function mixedCornerBase()
  if ExtensionPct() == 0 then return nil end
  local c = GB:GetStyle().construction
  if not (c and c.continuous == false) then return nil end
  local pat, r = tostring(GB.db and GB.db.shape):match("^corner%-(%d%d%d%d)%-r(%d)$")
  if pat ~= "1111" then return nil end
  return ExtensionAbove() and ("corner-0011-r" .. r) or ("corner-1100-r" .. r)
end

-- Hand-authored shapes: while a hand shape is active, EVERY masked element (icon,
-- gradient plate, border) sources from Media/art/hand/<key>-base.png, whose
-- silhouette sits in the centre 256 of a 512 canvas — so to map it onto a region we
-- expand the region by HALF its short side (`pad` extends further, e.g. a border's
-- thickness). The two mask anchors below defer here when a hand shape is set; overlay
-- (ring/sweep) anchoring is left alone (those are replaced by the hand glow).
-- Session 8 pivot: the active key is a PERSISTED setting (GB.db.handShape), read
-- straight from the db here — nil → the legacy SDF shape path.
local function handKey() return GB.db and GB.db.handShape end

-- Plate mode (session 11): a 2:1 PORTRAIT hand shape rendered as a SQUARE icon filling
-- one half + a solid-colour PLATE filling the other half (the colour then fading up over
-- the icon). Only the 2:1 portrait shapes halve into two clean squares, so plate mode is
-- gated to them. styleData.plate = { enabled, iconSide = "top"|"bottom", color, fadeStart }.
local function plateStyle() local s = GB:GetStyle(); return s and s.plate end
local function plateActive()
  local hk = handKey(); if not hk then return false end
  local info = GB.HAND_SHAPES and GB.HAND_SHAPES[hk]
  if not (info and info.orient == "portrait" and info.aspect == 2) then return false end
  local p = plateStyle()
  return p and p.enabled and true or false
end
-- Where the SQUARE icon sits (plate fills the opposite half). Returns "top"|"bottom".
local function plateIconSide() local p = plateStyle(); return (p and p.iconSide) or "top" end
-- Anchor a hand texture/mask so its silhouette maps to the icon GROWN uniformly by
-- `grow` screen-px on every side. The base's shape occupies a different FRACTION of the
-- canvas per axis (short = 0.5, long = long/(long+256)), so a uniform margin would grow
-- the long axis more and flatten the caps — this compensates PER AXIS: the short axis
-- adds 2*grow, the long axis adds grow*(aspect+1)/aspect, which both land the edge exactly
-- `grow` px out. grow=0 → icon edge (icon/plate mask); grow=thickness → border outer edge
-- (border mask + the outer glow, so the glow blooms from OUTSIDE the border).
local function hgAnchor(tex, icon, grow)
  grow = grow or 0
  local w, h = icon:GetWidth(), icon:GetHeight()
  local m0 = 0.5 * math.min(w, h)
  local aspect = math.max(w, h) / math.max(1, math.min(w, h))
  local addS, addL = 2 * grow, grow * (aspect + 1) / aspect
  local mx = m0 + (w <= h and addS or addL)
  local my = m0 + (h < w and addS or addL)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -mx, my)
  tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", mx, -my)
end

-- Anchor a mask over the whole construction (padding-compensated per axis). `ext`
-- is the magnitude; the extension sits ABOVE or BELOW the icon per ExtensionAbove.
local function AnchorConstructionMask(mask, icon, ext)
  if handKey() then return hgAnchor(mask, icon, 0) end
  local above = ExtensionAbove()
  local extT, extB = (above and ext or 0), (above and 0 or ext)
  local growX = icon:GetWidth() * GROW_RATIO
  local growY = (icon:GetHeight() + ext) * GROW_RATIO
  mask:ClearAllPoints()
  mask:SetPoint("TOPLEFT", icon, "TOPLEFT", -growX, growY + extT)
  mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", growX, -(growY + extB))
end

-- Anchor an OVERLAY (state ring, cooldown sweep, cast ring) over the whole
-- construction (icon + extension below) so it follows the full pill, not just
-- the icon — on a plate the icon is ~square while the construction is the pill.
-- `ratio` = padding grow (per axis), `extraPx` = extra overshoot.
local function AnchorConstruction(tex, icon, ratio, extraPx)
  local ext = ExtensionHeight(icon)
  local above = ExtensionAbove()
  local extT, extB = (above and ext or 0), (above and 0 or ext)
  extraPx = extraPx or 0
  local growX = icon:GetWidth() * ratio + extraPx
  local growY = (icon:GetHeight() + ext) * ratio + extraPx
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -growX, growY + extT)
  tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", growX, -(growY + extB))
end
-- Public: let other modules (Glows) anchor a texture/frame over the construction
-- (icon + extension) with the same math the overlays use.
function Skin:AnchorOverlay(tex, icon, ratio, extraPx) return AnchorConstruction(tex, icon, ratio, extraPx) end

-- The reference rect an OVERLAY (glow / cooldown / cast / animation) should span. In plate
-- mode it's the full-2:1 plateRect (so overlays trace the whole plate, not the half-height
-- square icon); otherwise the icon. plateRect exists once ApplyDecor has run in plate mode.
local function constructRef(btn, icon)
  icon = icon or btn.icon or btn.Icon
  if plateActive() and icon then
    local rec = records[btn]
    local pw = icon:GetWidth()
    if rec and pw and pw > 0 then
      -- Create + size the plate rect ON DEMAND so it's ready for ANY overlay that asks,
      -- regardless of call order (AlignCooldowns runs before ApplyDecor). W×2W, centred.
      rec.plateRect = rec.plateRect or CreateFrame("Frame", nil, btn)
      rec.plateRect:SetSize(pw, pw * 2)
      rec.plateRect:ClearAllPoints(); rec.plateRect:SetPoint("CENTER", btn, "CENTER", 0, 0)
      return rec.plateRect
    end
  end
  return icon
end
function Skin:ConstructRef(btn) return constructRef(btn, btn.icon or btn.Icon) end

-- Public: the glow art matching the CURRENT construction. Normally the shape's
-- own glow; but in continuous-OFF mode the construction is a rounded icon on a
-- SQUARE plate, so a fully-rounded glow floats off the plate — pick the MIXED-
-- corner glow instead (rounded on the icon end, sharp on the plate end). Only the
-- all-rounded family (corner-1111) has a clean mixed match; circle / square /
-- hexagon keep their own glow (a circle has no straight side to meet the plate).
function Skin:GlowArt()
  local mb = mixedCornerBase()
  if mb then return GB.MEDIA .. "art\\" .. mb .. "-glow.png" end
  return GB:GetShape().glow
end

-- Recolor every VISIBLE border to `color` ({r,g,b}) so it adopts a glow's colour
-- while the glow is active. Pass nil to restore the styled colour (re-runs decor).
function Skin:RecolorBorders(color)
  if not color then self:ReapplyDecor(); return end
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    if rec and rec.border and rec.border.tex and rec.border.tex:IsShown() then
      rec.border.tex:SetVertexColor(color[1], color[2], color[3])
    end
  end)
end

-- Apply a border's styled colour to its texture: two-tone → SetGradient (a colour
-- transition across the rim), one colour → flat SetVertexColor. Per-colour alpha ×
-- master Opacity. Shared by ApplyDecor and RecolorBorder so a glow can override the
-- rim then restore the exact styled look. `bd` = styleData.border.
local function applyBorderColor(tex, bd)
  local col = bd.color or { 0, 0, 0 }
  local a = bd.alpha or 1
  if bd.color2 then
    local c2, orient = bd.color2, (bd.gradDir == "left" or bd.gradDir == "right") and "HORIZONTAL" or "VERTICAL"
    local g1 = CreateColor(col[1], col[2], col[3], (col[4] or 1) * a)
    local g2 = CreateColor(c2[1], c2[2], c2[3], (c2[4] or 1) * a)
    if bd.gradDir == "down" or bd.gradDir == "left" then tex:SetGradient(orient, g2, g1)
    else tex:SetGradient(orient, g1, g2) end
  else
    tex:SetVertexColor(col[1], col[2], col[3], (col[4] or 1) * a)
  end
end

-- Per-button border recolour for the multi-part glow: `color` overrides ONE
-- button's rim to the glow tint while it's active; nil restores the styled
-- colour/gradient. Only a VISIBLE border is touched (no border → no-op).
function Skin:RecolorBorder(btn, color)
  local rec = records[btn]
  if not (rec and rec.border and rec.border.tex and rec.border.tex:IsShown()) then return end
  if color then rec.border.tex:SetVertexColor(color[1], color[2], color[3])
  else applyBorderColor(rec.border.tex, GB:GetStyle().border or {}) end
end

-- Skin:SetHandShape is defined lower, next to SetIconSize, so it can share the
-- full icon-geometry refresh (the size/aspect helpers live there). Activating a
-- hand silhouette sources its base for the icon, gradient plate AND border via the
-- mask pipeline (maskPlan + the two anchors above), through the proven ApplyDecor
-- rebuild — plus it re-derives the icon's W/H from the shape's aspect × size scale.

-- Public: anchor a hand texture grown by `grow` px on all sides (per-axis, caps stay
-- round) — used by the glow engine so the outer glow blooms from OUTSIDE the border.
function Skin:AnchorHandGrown(tex, icon, grow) return hgAnchor(tex, icon, grow) end

-- The current style's border thickness (0 if no border) — the amount the outer glow
-- must clear so a thick border can't bury it.
function Skin:BorderGrow()
  local bd = GB:GetStyle().border
  return (bd and bd.enabled and (bd.thickness or 0) > 0) and bd.thickness or 0
end

-- Anchor a mask over the construction EXPANDED by `t` px on every side — for the
-- border backing (a colored copy of the shape behind the icon that peeks out by
-- `t`). Same padding compensation as AnchorConstructionMask, sized for the larger
-- region so the shape silhouette lands on the border's outer edge.
local function AnchorBorderMask(mask, icon, ext, t)
  if handKey() then return hgAnchor(mask, icon, t) end
  local above = ExtensionAbove()
  local extT, extB = (above and ext or 0), (above and 0 or ext)
  local gx = (icon:GetWidth() + 2 * t) * GROW_RATIO
  local gy = (icon:GetHeight() + ext + 2 * t) * GROW_RATIO
  mask:ClearAllPoints()
  mask:SetPoint("TOPLEFT", icon, "TOPLEFT", -(t + gx), (t + gy) + extT)
  mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", (t + gx), -(extB + t + gy))
end

-- ---------------------------------------------------------------------------
-- Aspect-correct masks — the "clean pill" fix. One square mask PNG stretched
-- onto a non-square icon OVALIZES its rounded corners. Instead we ship rounded
-- masks pre-generated at a range of aspect ratios with genuinely CIRCULAR
-- corners (tools/generate-art.py → pill-<t|w>-a<ratio>-r<level>); the engine
-- picks the nearest aspect and stretches it to the icon, so a uniform-ish
-- stretch keeps the corners round — a clean pill at full radius. Square icons
-- and mixed-corner shapes keep the plain per-corner masks.
-- ---------------------------------------------------------------------------
local PILL_RATIOS = { 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0 }   -- = generate-art.py PILL_RATIOS

-- Current shape → corner pattern ("1111") + radius level. "circle" == all-round, full.
local function parseShape()
  local sh = GB.db and GB.db.shape
  if sh == "circle" then return "1111", 5 end
  local a, b, c, d, r = tostring(sh):match("^corner%-(%d)(%d)(%d)(%d)%-r(%d)$")
  if a then return a .. b .. c .. d, tonumber(r) end
  return "1111", 2
end

-- Aspect mask path for a w×h construction: an aspect-correct rounded mask when
-- the shape is NON-square and ALL-rounded (circle / corner-1111), else nil
-- (square + mixed-corner shapes keep the plain mask). Picks the nearest baked
-- aspect ratio + orientation.
-- Nearest baked aspect base id ("pill-t-a4-r5") for a NON-square, ALL-rounded
-- shape, else nil (square + mixed-corner shapes have no aspect variants).
local function aspectBase(w, h)
  if not (w and h) or w <= 0 or h <= 0 or math.abs(w - h) < 0.5 then return nil end
  -- Only circle / all-rounded corner shapes have aspect pill masks. Every other
  -- shape — square, mixed corners, AND fixed shapes like hexagon — must use the
  -- plain mask (parseShape's default is "1111", so guard on the real shape name).
  local sh = GB.db and GB.db.shape
  if sh ~= "circle" and not tostring(sh):match("^corner%-1111%-r%d$") then return nil end
  local pattern, level = parseShape()
  if pattern ~= "1111" then return nil end
  local tall = h > w
  local ratio = tall and (h / w) or (w / h)
  local bi, be = 1, math.huge
  for i, rr in ipairs(PILL_RATIOS) do
    local e = math.abs(rr - ratio)
    if e < be then be, bi = e, i end
  end
  return ("pill-%s-a%d-r%d"):format(tall and "t" or "w", bi - 1, level)
end
local function aspectMask(w, h)
  local base = aspectBase(w, h)
  return base and (GB.MEDIA .. "masks\\" .. base .. ".png")
end
function Skin:AspectMask(w, h) return aspectMask(w, h) end

-- Overlay art (state ring + cooldown swipe) matched to the icon's shape+aspect:
-- the aspect variant for a non-square all-rounded icon, else the base shape art.
-- (Proc glow is not aspect-varied yet — Glows.lua still uses the base halo.)
local function shapeArt(icon)
  -- Match the CONSTRUCTION (icon + extension), like the icon mask, so overlays
  -- follow the full pill and not the (often ~square) icon on a plated button.
  local base = aspectBase(icon:GetWidth(), icon:GetHeight() + ExtensionHeight(icon))
  if base then
    return { ring = GB.MEDIA .. "art\\" .. base .. "-ring.png",
             swipe = GB.MEDIA .. "masks\\" .. base .. "-swipe.png" }
  end
  return GB:GetShape()
end
function Skin:ShapeArt(icon) return shapeArt(icon) end
function Skin:AspectRing(w, h) local b = aspectBase(w, h); return b and (GB.MEDIA .. "art\\" .. b .. "-ring.png") end
function Skin:AspectSwipe(w, h) local b = aspectBase(w, h); return b and (GB.MEDIA .. "masks\\" .. b .. "-swipe.png") end

-- (Re)set the SetTexture-based overlay art (state rings + cooldown swipe) to
-- match the current shape + aspect. Textures re-set live with no mask quirk;
-- vertex colours / blend modes / anchors are configured once in ApplyButton.
local function applyShapeArt(btn, icon)
  local art = shapeArt(icon)
  -- Cooldown swipe: the hand shape's own squished-square swipe (generated from its
  -- base by tools/generate-hand-swipes.py) so the sweep traces the silhouette; else
  -- the SDF swipe. SetSwipeTexture needs a square pow2 texture, which both are.
  local hk = handKey()
  local swipe = (hk and GB:HandAsset(hk, "swipe")) or art.swipe
  -- Skip the SetTexture churn when the art is unchanged (e.g. dragging the size
  -- slider within one aspect bucket) — keeps the sliders smooth.
  local rec = records[btn]
  local key = tostring(art.ring) .. "|" .. tostring(swipe)
  if rec then
    if rec.artKey == key then return end
    rec.artKey = key
  end
  if btn.GetHighlightTexture then local hl = btn:GetHighlightTexture(); if hl then hl:SetTexture(art.ring) end end
  if btn.GetCheckedTexture then local ct = btn:GetCheckedTexture(); if ct then ct:SetTexture(art.ring) end end
  if btn.Flash then btn.Flash:SetTexture(art.ring) end
  for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown, btn.chargeCooldown }) do
    if cd and cd.SetSwipeTexture then cd:SetSwipeTexture(swipe) end
  end
end

-- (maskPath, cacheKey) for the construction around `icon` (+ext). src is the
-- aspect mask when the shape/aspect calls for one, else nil (plain shape mask).
-- The key lets callers skip a fresh-mask rebuild (source swaps never re-render —
-- §2) when nothing shape-relevant changed (a plain re-anchor re-clips live).
local function maskPlan(icon, ext)
  local hk = handKey()
  if hk then
    return GB:HandAsset(hk, "base"), "hand:" .. hk
  end
  local src = aspectMask(icon:GetWidth(), icon:GetHeight() + (ext or 0))
  return src, tostring(src or (GB.db and GB.db.shape))
end

-- Build a fresh mask from the given source (aspect mask, or the plain shape mask).
local function buildMask(parent, icon, ext, src)
  local m = parent:CreateMaskTexture()
  m:SetTexture(src or GB:GetShape().mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  AnchorConstructionMask(m, icon, ext or 0)
  return m
end

-- Cast/channel visuals. Blizzard draws the drain fill (CastFill) at a FIXED
-- square size independent of our resized icon — a mask can only clip, never
-- enlarge, so it stays square on a pill (verified /gb castinfo). So we SUPPRESS
-- it and draw our OWN pill-shaped LINEAR fill (a tint masked to the pill, whose
-- extent animates over the cast/channel), driven by the cast/channel timing
-- (UnitCastingInfo/UnitChannelInfo — readable, NOT the secret cooldown wall).
-- Linear (not radial) so it reads distinct from the cooldown sweep AND supports
-- a drain DIRECTION control. Colour/opacity/direction come from db (Config UI
-- controls to follow). Called from the PlaySpellCastAnim hook (frame live at
-- cast time), which also keeps mask creation off the size-slider hot path.

-- OnUpdate (runs AFTER the animation system each frame): keep Blizzard's fill
-- suppressed (its cast anim re-drives the alpha, so a one-time SetAlpha(0) won't
-- stick), then size our fill to the LIVE cast/channel progress. We read the
-- state here rather than trust the hook's castType/timing: UnitCastingInfo →
-- cast (fills up), else UnitChannelInfo → channel (drains); neither → the cast
-- ended/was interrupted → hide. `dir` = the edge the fill grows from.
-- Replay Blizzard's own completion burst (cast.EndBurst — the exact animation a
-- successful cast plays, which we already mask to the pill), tinted red. Blizzard
-- fires it on success but NOT on cancel, so we trigger it ourselves.
-- Scale the EndBurst anim group's child durations (base / speed; <1 = slower).
-- Reset to base (speed 1) at each cast start so a REAL completion stays normal.
local function setEndBurstSpeed(eb, speed)
  if not (eb and eb.GetAnimationGroups) then return end
  speed = speed or 1
  for _, ag in ipairs({ eb:GetAnimationGroups() }) do
    if ag.GetAnimations then
      for _, an in ipairs({ ag:GetAnimations() }) do
        if an.GetDuration and an.SetDuration then
          if not an.gbBaseDur then an.gbBaseDur = an:GetDuration() end
          an:SetDuration(an.gbBaseDur / speed)
        end
      end
    end
  end
end

local function PlayEndBurstRed(f)
  local cast = f.cast
  local eb = cast and cast.EndBurst
  if not eb then return end
  local c = (GB.db and GB.db.castInterruptColor) or { 1, 0.25, 0.25 }
  setEndBurstSpeed(eb, (GB.db and GB.db.castInterruptSpeed) or 0.6)   -- slower than Blizzard's default
  f.bursting = true      -- OnUpdate keeps the cast frame shown while this is set
  cast:Show(); cast:SetAlpha(1); eb:Show()
  if eb.GlowRing then eb.GlowRing:SetVertexColor(c[1], c[2], c[3]); eb.GlowRing:Show() end
  if eb.GetAnimationGroups then
    for _, ag in ipairs({ eb:GetAnimationGroups() }) do
      -- Stop re-asserting + hide the cast frame when the burst ANIMATION finishes
      -- (not on a fixed timer), so slowing it down doesn't cut it off. Hook once.
      if not ag.gbHooked then
        ag.gbHooked = true
        ag:HookScript("OnFinished", function()
          f.bursting = false
          if not (UnitCastingInfo("player") or UnitChannelInfo("player")) then cast:Hide() end
        end)
      end
      ag:Stop(); ag:Play()
    end
  end
end

-- Set by styleCast to the button whose cast anim just fired — the ONLY button that should
-- drain (UnitCastingInfo is global, so the fill frames can't tell casts apart on their own).
local castCurrentBtn
local function CastFillOnUpdate(f, elapsed)
  if f.blizzFill then f.blizzFill:SetAlpha(0) end
  if f.innerGlow then f.innerGlow:SetAlpha(0) end   -- hand shape: shaped glow replaces the rounded-square inner glow
  -- InterruptDisplay (the red rounded-square cancel flash, atlas UI-HUD-ActionBar-
  -- Interrupt) plays right at cast-cancel — inside the grace below — so keep it
  -- suppressed each frame too. Its anim re-drives alpha, hence per-frame.
  if f.interrupt then f.interrupt:SetAlpha(0) end
  -- While our red burst plays, Blizzard keeps trying to fade/hide its cast frame
  -- (cancel handling) — force it visible each frame so the burst plays through.
  if f.bursting and f.cast then f.cast:Show(); f.cast:SetAlpha(1) end
  local s, e, channel
  local _, _, _, cs, ce = UnitCastingInfo("player")
  if cs then s, e, channel = cs, ce, false
  else
    local _, _, _, hs, he = UnitChannelInfo("player")
    if hs then s, e, channel = hs, he, true end
  end
  -- UnitCastingInfo is GLOBAL — it can't tell which button's spell is casting. Gate the
  -- drain on the CURRENT caster (castCurrentBtn, set in styleCast when THIS button's cast
  -- anim fired); else a button still in its 1.5s post-cast grace re-drains to your NEXT
  -- cast → the "channel drain on multiple buttons" bug.
  local mine = (f.gbBtn == castCurrentBtn) and s and e and e > s
  if not mine then
    if f.draining then
      -- THIS button's cast just ended (finished/cancelled, or another button took over):
      -- clear its shaped glow; if interrupted (lastP < ~1) replay the red completion burst
      -- (a clean finish already showed its own gold EndBurst).
      f.draining = false
      if f.gbBtn and GB.Glows and GB.Glows.SetCast then GB.Glows:SetCast(f.gbBtn, nil) end
      if f.lastP and f.lastP < 0.85 and not f.flashed then f.flashed = true; PlayEndBurstRed(f) end
    end
    f.tex:Hide()
    -- Grace window: keep suppressing Blizzard's fill/interrupt square while the burst plays.
    f.grace = (f.grace or 1.5) - (elapsed or 0)
    if f.grace <= 0 then f.lastP, f.flashed = nil, nil; f:Hide() end
    return
  end
  f.draining = true
  f.grace, f.flashed = nil, nil
  local p = (GetTime() - s / 1000) / ((e - s) / 1000)
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  f.lastP = p
  local frac = channel and (1 - p) or p       -- cast fills up; channel drains
  local tex, W, H = f.tex, f:GetWidth(), f:GetHeight()
  tex:Show()
  tex:ClearAllPoints()
  local dir = f.dir or "up"
  if dir == "up" then
    tex:SetPoint("BOTTOMLEFT", f); tex:SetPoint("BOTTOMRIGHT", f); tex:SetHeight(math.max(0.01, H * frac))
  elseif dir == "down" then
    tex:SetPoint("TOPLEFT", f); tex:SetPoint("TOPRIGHT", f); tex:SetHeight(math.max(0.01, H * frac))
  elseif dir == "left" then
    tex:SetPoint("TOPRIGHT", f); tex:SetPoint("BOTTOMRIGHT", f); tex:SetWidth(math.max(0.01, W * frac))
  else -- "right"
    tex:SetPoint("TOPLEFT", f); tex:SetPoint("BOTTOMLEFT", f); tex:SetWidth(math.max(0.01, W * frac))
  end
end

local function styleCast(btn, rec, icon, castType)
  local cast = btn.SpellCastAnimFrame
  if not cast then return end
  local ext = ExtensionHeight(icon)
  local ref = constructRef(btn, icon)   -- full 2:1 plate in plate mode; else the icon
  -- Cast fill spans the whole construction, so in continuous-OFF it needs the
  -- mixed-corner mask (rounded icon end, square plate end) to hug the square plate
  -- — otherwise it draws rounded bottom corners floating off the plate.
  local mb = mixedCornerBase()
  local hk = handKey()
  local src = (hk and GB:HandAsset(hk, "base"))               -- hand silhouette (icon + burst + fill all trace it)
    or (mb and (GB.MEDIA .. "masks\\" .. mb .. ".png"))
    or aspectMask(icon:GetWidth(), icon:GetHeight() + ext)     -- nil → base shape mask
  -- 2. Shape the end-burst completion flash to the silhouette (used by successful
  --    casts AND replayed red for cancels). Reset its tint to the COMPLETE colour
  --    each cast so a real completion shows it (and a prior cancel's red doesn't linger).
  local burst = cast.EndBurst
  if burst and burst.GlowRing then
    local slot = rec.castBurst or {}; rec.castBurst = slot
    if burst.EndMask and not slot.blizzRemoved then burst.GlowRing:RemoveMaskTexture(burst.EndMask); slot.blizzRemoved = true end
    if slot.mask then burst.GlowRing:RemoveMaskTexture(slot.mask) end
    slot.mask = buildMask(burst, ref, ext, src)
    burst.GlowRing:AddMaskTexture(slot.mask)
    local cc = (GB.db and GB.db.castCompleteColor) or { 1, 0.9, 0.5 }
    burst.GlowRing:SetVertexColor(cc[1], cc[2], cc[3])
    setEndBurstSpeed(burst, 1)   -- normal speed for a real completion (cancel slows it)
  end
  -- 3. Our own pill-shaped linear cast/channel fill.
  if not rec.castFillFrame then
    local f = CreateFrame("Frame", nil, btn)
    f.tex = f:CreateTexture(nil, "OVERLAY")   -- WHITE8X8 = maskable (masks don't clip SetColorTexture)
    f.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    f:SetScript("OnUpdate", CastFillOnUpdate)
    f:Hide()
    rec.castFillFrame = f
  end
  local f = rec.castFillFrame
  f:SetFrameLevel(btn:GetFrameLevel() + 3)    -- above icon, below text (TextOverlayContainer = +4)
  -- The fill is a DRAINING rectangle, so the frame must stay icon-sized (drains over
  -- the icon height); the mask (hand base via buildMask → hgAnchor) does the shaping.
  -- (Do NOT hgAnchor the frame — that's the 2x hand-canvas size and would drain over 2x.)
  AnchorConstruction(f, ref, GROW_RATIO)      -- span the full plate in plate mode (ref); else the icon
  if f.mask then f.tex:RemoveMaskTexture(f.mask) end
  f.mask = buildMask(f, ref, ext, src)        -- fresh shape mask, clips the tint to the silhouette
  f.tex:AddMaskTexture(f.mask)
  local col = (GB.db and GB.db.castFillColor) or { 1, 0.85, 0.4 }
  local a = (GB.db and GB.db.castFillAlpha) or 0.55
  f.tex:SetVertexColor(col[1], col[2], col[3], a)
  f.dir = (GB.db and GB.db.castDrainDir) or "up"
  f.cast = cast                                    -- for the cancel → red EndBurst replay
  f.gbBtn = btn                                    -- for clearing the "cast" shaped glow at cast end
  f.blizzFill = cast.Fill and cast.Fill.CastFill   -- OnUpdate force-suppresses this each frame
  -- Hand shape: the shaped multi-part glow (Glows "cast" source) replaces Blizzard's
  -- inner glow, so suppress it EACH FRAME too (its cast anim re-drives the alpha, so
  -- the one-shot in StyleCastInnerGlow alone leaves a rounded-square overlay).
  f.innerGlow = hk and cast.Fill and cast.Fill.InnerGlowTexture or nil
  f.interrupt = btn.InterruptDisplay               -- and Blizzard's red square (we replay EndBurst instead)
  f.grace, f.lastP, f.flashed, f.bursting, f.draining = nil, nil, nil, nil, nil   -- fresh cast
  castCurrentBtn = btn                        -- THIS button is the current caster (gates the drain)
  f:Show()                                    -- OnUpdate polls the live cast/channel + hides at the end
end

-- Resolve a hotkey `font` value to a TTF path. The Config picker stores an LSM
-- font NAME (our bundled fonts + every other addon's registered fonts); fall back
-- to our bundled-name map if LSM is absent, then to a legacy GB.FONT key (older
-- saved styles stored "label"/"head"/…), then the default.
local function resolveFont(key)
  key = key or "label"
  local lsm = GB.GetLSM and GB.GetLSM()
  if lsm then local p = lsm:Fetch("font", key, true); if p then return p end end
  return (GB.BUNDLED_FONTS and GB.BUNDLED_FONTS[key]) or GB.FONT[key] or GB.FONT.label
end

-- Mac modifier display (opt-in per style: styleData.keybindMods == "symbols").
-- Rewrite Blizzard's abbreviated modifier PREFIXES (s-/c-/a-/m- = Shift/Ctrl/Alt/
-- Cmd) into inline symbol icons, hyphen removed — e.g. "s-m-Z" → ⇧⌘Z. GENERAL:
-- it strips whatever known modifier prefixes lead the text, for any bind / user;
-- nothing is hardcoded to a specific keybind. We only edit the display fontstring
-- (never a binding). `|T...:0|t` scales each glyph to the keybind's line height.
-- White glyph, scaled to the keybind's line height (`:0`). Inline textures don't
-- inherit the fontstring colour, so these stay white regardless of the keybind
-- tint — which reads clean/legible (Jason's call, 2026-07-19).
local MOD_ICON = {
  s = "|T" .. GB.MEDIA .. "ui\\shift.png:0|t",
  c = "|T" .. GB.MEDIA .. "ui\\ctrl.png:0|t",
  a = "|T" .. GB.MEDIA .. "ui\\opt.png:0|t",
  m = "|T" .. GB.MEDIA .. "ui\\cmd.png:0|t",
}
local function symbolizeHotkey(text)
  local prefix = ""
  while true do
    local mod, rest = text:match("^([scam])%-(.*)$")   -- peel one modifier prefix off the front
    if not mod then break end
    prefix = prefix .. MOD_ICON[mod]
    text = rest
  end
  return prefix .. text
end
-- Custom keybind master switch: the styling table exists AND enabled ~= false.
-- Mac symbols are a SUB-feature of it (they only apply when it's on) — turning
-- Custom keybind off returns the keybind to Blizzard's default, symbols and all.
local function hotkeyEnabled()
  local h = GB:GetStyle().hotkey
  return h ~= nil and h.enabled ~= false
end
-- Rewrite a button's CURRENT hotkey text if the style opts in. Idempotent: once
-- rewritten the text leads with "|T", so the [scam]- match no longer fires.
local function symbolizeButton(btn)
  local hk = btn.HotKey
  if not hk or not hotkeyEnabled() or (GB:GetStyle().keybindMods) ~= "symbols" then return end
  local raw = hk:GetText()
  if raw and raw:match("^[scam]%-") then hk:SetText(symbolizeHotkey(raw)) end
end

local function ApplyHotkeyOverride(btn)
  local rec = records[btn]
  local hk = btn.HotKey
  local icon = btn.icon or btn.Icon
  if not (rec and hk and icon) then return end
  local conf = GB:GetStyle().hotkey
  if not conf or conf.enabled == false then
    if rec.hkOverridden then
      -- Full revert: restore the pristine font (Blizzard won't) + let Blizzard
      -- re-anchor/re-size via UpdateHotkeys.
      rec.hkOverridden = nil
      hk:SetJustifyH(rec.hkJustify or "RIGHT")
      if rec.hkFont and rec.hkFont[1] then hk:SetFont(rec.hkFont[1], rec.hkFont[2], rec.hkFont[3] or "") end
      if rec.hkColor then hk:SetTextColor(rec.hkColor[1], rec.hkColor[2], rec.hkColor[3], rec.hkColor[4] or 1) end
      if btn.UpdateHotkeys then btn:UpdateHotkeys(btn.buttonType) end
    end
    return
  end
  local ext = ExtensionHeight(icon)
  hk:ClearAllPoints()
  if conf.zone == "extension" and ext > 0 then
    if ExtensionAbove() then
      hk:SetPoint("CENTER", icon, "TOP", conf.offsetX or 0, (ext / 2) + (conf.offsetY or 0))
    else
      hk:SetPoint("CENTER", icon, "BOTTOM", conf.offsetX or 0, -(ext / 2) + (conf.offsetY or 0))
    end
  else
    hk:SetPoint("CENTER", icon, "CENTER", conf.offsetX or 0, conf.offsetY or 0)
  end
  hk:SetSize(icon:GetWidth(), (conf.size or 13) + 4)
  hk:SetJustifyH("CENTER")
  hk:SetFont(resolveFont(conf.font), conf.size or 13, conf.flags or "OUTLINE")
  if conf.color then hk:SetTextColor(unpack(conf.color)) end
  rec.hkOverridden = true
end

local function ApplyDecor(btn)
  local rec = records[btn]
  local icon = btn.icon or btn.Icon
  if not (rec and icon) then return end
  local style = GB:GetStyle()
  local plate = plateActive()   -- 2:1 portrait shape split into a square icon half + a colour plate half
  rec.plates = rec.plates or {}
  rec.plateFresh = false   -- set by getPlate when a plate texture is first created (mask-retry, below)
  local ext = ExtensionHeight(icon)
  local above = ExtensionAbove()
  local extT, extB = (above and ext or 0), (above and 0 or ext)   -- extension split per direction
  -- "Continuous shape" (default) masks the icon + extension as ONE shape — a pill
  -- wrapping both (Jason's mock). Continuous OFF masks the icon to its OWN shape
  -- (icon-only) and leaves the plate a square rectangle → a rounded icon on a
  -- crisp square plate. So the MASKS (icon + border) span the construction only
  -- when continuous; the plate positioning always uses the real extension.
  local continuous = not (style.construction and style.construction.continuous == false)
  -- Continuous-OFF only means something when there's a PLATE to square off. With no
  -- extension — or for a circle (no straight side to meet a square plate) — force
  -- continuous, else getPlate strips the gradient's mask and it draws as an unmasked
  -- square (the hexagon-gradient regression: continuous was toggled off globally).
  if ext == 0 or (GB.db and GB.db.shape) == "circle" then continuous = true end
  local maskExt = continuous and ext or 0
  local mExtT, mExtB = (above and maskExt or 0), (above and 0 or maskExt)
  -- The aspect mask comes from the (masked) construction's aspect; a fresh mask is
  -- built only when the plan changes (source swaps never re-render — §2), else a
  -- plain re-anchor re-clips live. Fold `continuous` into the key so toggling it
  -- rebuilds even when the aspect happens to match.
  -- Plate mode routes the SHAPE mask to a full-2:1 construction rect (plateRect), so a
  -- SQUARE icon (only half the height) doesn't squish the silhouette; the same mask then
  -- clips BOTH the icon and the plate fill, each showing only in its own half.
  local shapeRef = constructRef(btn, icon)   -- plateRect (create-on-demand) in plate mode; else icon
  local maskSrc, maskKey = maskPlan(icon, maskExt)
  maskKey = maskKey .. (continuous and "|c1" or "|c0") .. (plate and "|plate" or "")
  if rec.mask and rec.maskKey == maskKey then
    AnchorConstructionMask(rec.mask, shapeRef, maskExt)
  else
    if rec.mask then icon:RemoveMaskTexture(rec.mask); if rec.platefill then rec.platefill:RemoveMaskTexture(rec.mask) end end
    rec.mask = buildMask(btn, shapeRef, maskExt, maskSrc)
    icon:AddMaskTexture(rec.mask)
    rec.maskKey = maskKey
    rec.platefillMask = nil   -- force a re-attach to the plate fill below
  end
  -- Plate fill: the solid-colour half OPPOSITE the icon, clipped by the shared silhouette
  -- mask (rec.mask spans the full 2:1 → this shows only in its half). Solid for now; the
  -- gradient fading up over the icon is the next step.
  if plate then
    if not rec.platefill then
      rec.platefill = btn:CreateTexture(nil, "ARTWORK", nil, -1)
      rec.platefill:SetTexture("Interface\\Buttons\\WHITE8X8")   -- masks clip a FILE, not SetColorTexture (§4)
      rec.plateFresh = true                                       -- first AddMaskTexture may need the mask-retry
    end
    local pf, pw = rec.platefill, icon:GetWidth()
    local pdy = (plateIconSide() == "bottom") and (pw * 0.5) or (-pw * 0.5)   -- the half OPPOSITE the icon
    local pc = (plateStyle() and plateStyle().color) or { 0.1, 0.1, 0.13 }
    pf:ClearAllPoints(); pf:SetPoint("CENTER", btn, "CENTER", 0, pdy); pf:SetSize(pw, pw)
    pf:SetVertexColor(pc[1], pc[2], pc[3])
    if rec.forcePlateMask or rec.platefillMask ~= rec.mask then
      if rec.platefillMask then pf:RemoveMaskTexture(rec.platefillMask) end
      pf:AddMaskTexture(rec.mask); rec.platefillMask = rec.mask
    end
    pf:Show()
  elseif rec.platefill then
    rec.platefill:Hide()
  end
  -- Plate gradient: the plate colour, opaque where it meets the plate (the midline) and
  -- fading OUT over the icon across `fadeStart` of the icon half. Same silhouette mask so
  -- it can't spill past the shape. Drawn above the icon, below the text container (+4).
  if plate then
    if not rec.plategrad then
      local _, isub = icon:GetDrawLayer()
      rec.plategrad = btn:CreateTexture(nil, "ARTWORK", nil, (isub or 0) + 1)
      rec.plategrad:SetTexture("Interface\\Buttons\\WHITE8X8")
      rec.plateFresh = true
    end
    local pg, pw = rec.plategrad, icon:GetWidth()
    local pc = (plateStyle() and plateStyle().color) or { 0.1, 0.1, 0.13 }
    local fadeStart = (plateStyle() and plateStyle().fadeStart) or 0.5
    local fromC, toC = CreateColor(pc[1], pc[2], pc[3], 1), CreateColor(pc[1], pc[2], pc[3], 0)
    pg:ClearAllPoints(); pg:SetHeight(math.max(0.01, pw * fadeStart))   -- the icon half is pw tall
    if plateIconSide() == "bottom" then   -- icon in the BOTTOM half → opaque at its TOP, fading DOWN
      pg:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0); pg:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
      pg:SetGradient("VERTICAL", toC, fromC)
    else                                   -- icon in the TOP half → opaque at its BOTTOM, fading UP
      pg:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0); pg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
      pg:SetGradient("VERTICAL", fromC, toC)
    end
    if rec.forcePlateMask or rec.plategradMask ~= rec.mask then
      if rec.plategradMask then pg:RemoveMaskTexture(rec.plategradMask) end
      pg:AddMaskTexture(rec.mask); rec.plategradMask = rec.mask
    end
    pg:Show()
  elseif rec.plategrad then
    rec.plategrad:Hide()
  end
  -- Border: a colored copy of the shape, oversized by `thickness` px and drawn
  -- BEHIND the icon, so a rim of colour shows around the whole construction. Any
  -- shape (reuses the shape mask). thickness/color/opacity from styleData.border.
  local bd = style.border
  if bd and bd.enabled and (bd.thickness or 0) > 0 then
    if not rec.border then
      local tex = btn:CreateTexture(nil, "BACKGROUND")   -- masks clip a FILE, not SetColorTexture (§4)
      tex:SetTexture("Interface\\Buttons\\WHITE8X8")
      rec.border = { tex = tex }
    end
    local b, t = rec.border, bd.thickness
    local _, isub = icon:GetDrawLayer()
    b.tex:SetDrawLayer("BACKGROUND", math.max(-8, (isub or 0) - 1))   -- just behind the icon
    applyBorderColor(b.tex, bd)   -- two-tone gradient or flat colour (shared with the glow recolour)
    b.tex:ClearAllPoints()
    b.tex:SetPoint("TOPLEFT", shapeRef, "TOPLEFT", -t, t + mExtT)      -- frames the masked region (plateRect in plate mode)
    b.tex:SetPoint("BOTTOMRIGHT", shapeRef, "BOTTOMRIGHT", t, -(mExtB + t))
    -- Same shape source as the icon; rebuild only on a shape/plan change (source
    -- swaps never re-render, §2) — thickness/size are a live re-anchor.
    if b.mask and b.maskKey == maskKey then
      AnchorBorderMask(b.mask, shapeRef, maskExt, t)
    else
      if b.mask then b.tex:RemoveMaskTexture(b.mask) end
      b.mask = btn:CreateMaskTexture()
      b.mask:SetTexture(maskSrc or GB:GetShape().mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      AnchorBorderMask(b.mask, shapeRef, maskExt, t)
      b.tex:AddMaskTexture(b.mask)
      b.maskKey = maskKey
    end
    b.tex:Show()
  elseif rec.border then
    rec.border.tex:Hide()
  end
  local function getPlate(idx)
    local plate = rec.plates[idx]
    if not plate then
      rec.decorFrame = rec.decorFrame or CreateFrame("Frame", nil, btn)
      rec.decorFrame:SetAllPoints(icon)
      rec.decorFrame:SetFrameLevel(btn:GetFrameLevel() + 2)
      local tex = rec.decorFrame:CreateTexture(nil, "ARTWORK")
      -- A white texture FILE, not SetColorTexture: masks don't clip
      -- solid-color textures (QA 2026-07-18 — square plate corners).
      tex:SetTexture("Interface\\Buttons\\WHITE8X8")
      plate = { tex = tex }
      rec.plates[idx] = plate
      rec.plateFresh = true   -- brand-new texture: its first AddMaskTexture will silently fail (see mask-retry)
    end
    -- Continuous: the plate shares the icon's mask so it joins the pill (rebuild
    -- on plan change, else re-anchor). NOT continuous: no mask → a plain square
    -- rectangle (the crisp plate that squares off the junction).
    if not continuous then
      if plate.mask then plate.tex:RemoveMaskTexture(plate.mask); plate.mask = nil; plate.maskKey = nil end
    elseif plate.mask and plate.maskKey == maskKey and not rec.forcePlateMask then
      AnchorConstructionMask(plate.mask, icon, maskExt)
    else
      if plate.mask then plate.tex:RemoveMaskTexture(plate.mask) end
      plate.mask = buildMask(rec.decorFrame, icon, maskExt, maskSrc)
      plate.tex:AddMaskTexture(plate.mask)
      plate.maskKey = maskKey
    end
    plate.tex:ClearAllPoints()
    return plate
  end
  -- Gradient layers. A layer is a directional fade masked to the shape (so it
  -- follows a hexagon, pill, etc.). `dir` = the way the fade travels FROM its
  -- solid edge (up = solid at bottom fading up; down/left/right mirror it).
  -- `bleedPct` ("Fade start") = how far the fade reaches from that solid edge,
  -- as a fraction of the icon — works on EVERY shape now (was extension-only).
  -- When an extension lies on the solid edge it's drawn as a flat SOLID zone
  -- first (the "plate" look): solid through the extension, fading into the icon.
  -- In plate mode the plate draws its OWN gradient (below), so skip the decoration layers.
  local used = 0
  for _, layer in ipairs((not plate and style.layers) or {}) do
    if layer.enabled ~= false and layer.kind == "gradient" then
      local c = layer.color or { 1, 1, 1 }
      local fromA, toA = layer.fromAlpha or 1, layer.toAlpha or 0
      local fromC = CreateColor(c[1], c[2], c[3], fromA)
      local toC = CreateColor(c[1], c[2], c[3], toA)
      local dir = layer.dir or "up"
      local reach = layer.bleedPct or 0.5              -- fraction of the icon the fade spans
      if dir == "left" or dir == "right" then
        -- Horizontal fade across the whole construction; solid at the far edge.
        local solidRight = (dir == "left")             -- fades left ⇒ solid on the right
        local edge = solidRight and "RIGHT" or "LEFT"
        used = used + 1
        local fade = getPlate(used)
        fade.tex:SetPoint("TOP" .. edge, icon, "TOP" .. edge, 0, extT)
        fade.tex:SetPoint("BOTTOM" .. edge, icon, "BOTTOM" .. edge, 0, -extB)
        fade.tex:SetWidth(math.max(0.01, icon:GetWidth() * reach))
        -- HORIZONTAL gradient: min = left, max = right.
        if solidRight then fade.tex:SetGradient("HORIZONTAL", toC, fromC)
        else fade.tex:SetGradient("HORIZONTAL", fromC, toC) end
        fade.tex:Show()
      else
        -- Vertical fade; solid at the bottom for "up", the top for "down".
        local solidBottom = (dir == "up")
        local edge = solidBottom and "BOTTOM" or "TOP"
        -- Extension on the solid edge → a flat SOLID zone through it (plate look).
        local extAligned = ext > 0 and ((solidBottom and not above) or (not solidBottom and above))
        if extAligned then
          used = used + 1
          local solid = getPlate(used)
          local outward = solidBottom and -ext or ext
          solid.tex:SetPoint(edge .. "LEFT", icon, edge .. "LEFT", 0, outward)
          solid.tex:SetPoint(edge .. "RIGHT", icon, edge .. "RIGHT", 0, outward)
          solid.tex:SetHeight(ext)
          solid.tex:SetGradient("VERTICAL", fromC, fromC)
          solid.tex:Show()
        end
        used = used + 1
        local fade = getPlate(used)
        fade.tex:SetPoint(edge .. "LEFT", icon, edge .. "LEFT", 0, 0)
        fade.tex:SetPoint(edge .. "RIGHT", icon, edge .. "RIGHT", 0, 0)
        fade.tex:SetHeight(math.max(0.01, icon:GetHeight() * reach))
        -- VERTICAL gradient: min = bottom, max = top. Full colour at the solid edge.
        if solidBottom then fade.tex:SetGradient("VERTICAL", fromC, toC)
        else fade.tex:SetGradient("VERTICAL", toC, fromC) end
        fade.tex:Show()
      end
    end
  end
  for i = used + 1, #rec.plates do rec.plates[i].tex:Hide() end
  -- Text must render above plates: raise Blizzard's text container once.
  if btn.TextOverlayContainer then
    btn.TextOverlayContainer:SetFrameLevel(btn:GetFrameLevel() + 4)
  end
  ApplyHotkeyOverride(btn)
  -- Mask-retry: a plate texture created THIS frame hasn't rendered yet, so its
  -- first AddMaskTexture silently fails (never-rendered-texture quirk, API-NOTES
  -- §2) and the gradient draws UNMASKED — e.g. a square bottom on a hexagon,
  -- whose fixed aspect never changes maskKey to trigger a rebuild. Once the plate
  -- has drawn one frame it accepts the mask, so force ONE mask rebuild next frame.
  if rec.plateFresh and not rec.plateRetryPending then
    rec.plateRetryPending = true
    C_Timer.After(0, function()
      rec.plateRetryPending = nil
      if not (Skin.enabled and rec.active) then return end
      rec.forcePlateMask = true
      ApplyDecor(btn)
      rec.forcePlateMask = nil
    end)
  end
end

function Skin:ReapplyDecor()
  if not self.enabled then return end
  GB:ForEachButton(function(btn)
    if records[btn] and records[btn].active then ApplyDecor(btn) end
  end)
  if GB.Glows then GB.Glows:RefreshShape(); GB.Glows:RefreshSize() end   -- glow art + span follow continuous/extension edits
end

-- Apply (or revert) the Mac modifier rewrite across all buttons — call when the
-- setting changes. Revert asks Blizzard to re-set the original text; the hook
-- then leaves it alone (mods != "symbols"), so nothing re-symbolizes it.
function Skin:RefreshHotkeyText()
  if not self.enabled then return end
  -- Symbols only render when Custom keybind is on; otherwise ask Blizzard to
  -- re-set the plain (un-symbolized) text.
  local symbols = (GB:GetStyle().keybindMods == "symbols") and hotkeyEnabled()
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    if not (rec and rec.active and btn.HotKey) then return end
    if symbols then symbolizeButton(btn)
    elseif btn.UpdateHotkeys then btn:UpdateHotkeys(btn.buttonType) end
  end)
end

-- The cast/channel InnerGlowTexture can't be masked at runtime (see
-- ApplyButton), so its square art is REPLACED with our shaped ring on every
-- cast start — Blizzard re-sets its atlas per cast type inside
-- PlaySpellCastAnim, so this re-asserts in a post-hook of that method,
-- tinted lime for channels / gold for casts (matching Blizzard's two looks).
local CAST_TINT = { cast = { 1, 0.85, 0.4 }, channel = { 0.6, 1, 0.4 } }
-- The ring art's bright rim peaks at 112/128 of its canvas (8px inside the
-- shape edge at 120) — fitted edge-to-edge it reads undersized, same symptom
-- as the cooldown sweep (QA 2026-07-18). Scale the region so the RIM lands on
-- the icon edge; the soft outer falloff then slightly overlaps it (good, ADD).
local RING_FIT = (256 / 240) * (120 / 112)
local function StyleCastInnerGlow(btn, castType)
  local icon = btn.icon or btn.Icon
  local fill = btn.SpellCastAnimFrame and btn.SpellCastAnimFrame.Fill
  local glow = fill and fill.InnerGlowTexture
  if not (icon and glow) then return end
  local isChannel = ActionButtonCastType and castType == ActionButtonCastType.Channel
  -- Hand shape: suppress Blizzard's inner glow and drive the multi-part SHAPED glow
  -- (lime channel / gold cast) via the "cast" source; the drain fill shows progress.
  -- Cleared when the cast ends (CastFillOnUpdate). SDF fallback keeps the shaped ring.
  if handKey() then
    glow:SetAlpha(0)
    if GB.Glows and GB.Glows.SetCast then GB.Glows:SetCast(btn, isChannel and "channel" or "cast") end
    return
  end
  glow:SetTexture(shapeArt(icon).ring)   -- construction-aspect ring
  AnchorConstruction(glow, icon, (RING_FIT - 1) / 2)
  local tint = isChannel and CAST_TINT.channel or CAST_TINT.cast
  glow:SetVertexColor(tint[1], tint[2], tint[3])
  -- The ring art was made BOLDER for state highlights (peak ~0.65 → 1.0 alpha,
  -- 2026-07-20); this glow SHARES that texture, so scale its alpha back to the
  -- old effective peak to keep the QA'd cast/channel look unchanged.
  glow:SetAlpha(0.65)
end

-- Make the round sweep circle coincide with the icon circle: anchor the
-- cooldown widgets to the icon oversized by the art-padding ratio (same math
-- as the icon mask). Blizzard insets the cooldown inside the icon (+1.7/-1
-- points, small-button UpdateButtonArt re-anchors it) — which made the v0
-- sweep visibly smaller than the icon.
local function AlignCooldowns(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return end
  -- Overshoot: the sweep must extend slightly PAST the icon circle or the
  -- icon's anti-aliased rim leaks full brightness at the edge (QA-observed).
  -- A sub-pixel dark fringe on the outside is invisible; a bright rim isn't.
  -- Live-tunable via /gb sweep <px> for pixel-perfect QA.
  -- Fill the icon exactly: GROW_RATIO compensates the art padding so the shape
  -- edge lands ON the icon edge, and a fixed +0.75px kills the anti-aliased rim
  -- leak (QA 2026-07-18). This was the whole point of the old "overshoot" — it
  -- fixed Blizzard's undershoot — so it's baked, not a user slider (Jason 2026-07-20).
  -- Hand swipe fills its texture edge-to-edge (the -swipe crop has no art padding),
  -- so anchor the cooldown to the ICON BOUNDS + a hair for the AA rim — NOT the
  -- GROW_RATIO compensation the padded SDF swipe needs (that overshot, worst on the
  -- long axis of 2:1/3:2). The SDF path keeps the ratio grow.
  -- Hand swipe + icon mask both derive from the SAME reference rect, so the cooldown
  -- anchors to the icon bounds EXACTLY (no overshoot) — the sweep edge lands on the
  -- silhouette edge. (A white sweep makes any overshoot fringe visible; 0 is right.)
  local hk = handKey()
  for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown, btn.chargeCooldown }) do
    if cd then
      if hk then
        local ref = constructRef(btn, icon)   -- full 2:1 plate in plate mode; else the icon
        cd:ClearAllPoints()
        cd:SetPoint("TOPLEFT", ref, "TOPLEFT", 0, 0)
        cd:SetPoint("BOTTOMRIGHT", ref, "BOTTOMRIGHT", 0, 0)
      else
        AnchorConstruction(cd, icon, GROW_RATIO, 0.75)
      end
    end
  end
end

-- Cooldown-sweep appearance: tint (SetSwipeColor rgb) + opacity (its alpha, on top
-- of the 0.8 baked into the swipe art). Blizzard's rotating EDGE and finish BLING
-- are SUPPRESSED here (SetDrawEdge/Bling false): they're drawn to the square frame
-- bounds and can't follow a circle/hex, and can't be recoloured cleanly — our own
-- shaped finish flash (below) replaces the bling. Blizzard resets the sweep colour
-- to (0,0,0,1) after a cast (ActionButton OnHide → ActionButton_UpdateCooldown),
-- so a custom colour is re-asserted in a hook of that global (installed once).
local function applySwipe(cd)
  if not cd then return end
  local db = GB.db or {}
  local c = db.swipeColor or { 0, 0, 0 }
  if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end    -- charge recharge is edge-only by default → force the shaped swipe
  if cd.SetSwipeColor then cd:SetSwipeColor(c[1], c[2], c[3], db.swipeAlpha or 0.8) end
  if cd.SetDrawEdge then cd:SetDrawEdge(false) end     -- can't be shaped → off
  if cd.SetDrawBling then cd:SetDrawBling(false) end   -- replaced by our shaped flash
end
-- Public: style an arbitrary Cooldown frame (the Config preview reuses this so it
-- stays in sync with the bars — one source of truth for the sweep look).
function Skin:StyleCooldown(cd) applySwipe(cd) end
local function applySwipeAll()
  if not Skin.enabled then return end
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    if rec and rec.active then applySwipe(btn.cooldown); applySwipe(btn.lossOfControlCooldown); applySwipe(btn.chargeCooldown) end
  end)
end
function Skin:SetSwipeColor(c) if GB.db then GB.db.swipeColor = c end; applySwipeAll() end
function Skin:SetSwipeAlpha(v) if GB.db then GB.db.swipeAlpha = v end; applySwipeAll() end
function Skin:SetFinishFlash(b) if GB.db then GB.db.finishFlash = b end end
function Skin:SetFinishFlashColor(c) if GB.db then GB.db.finishFlashColor = c end end

-- ---------------------------------------------------------------------------
-- Finish flash — OUR OWN shape-masked burst when a real cooldown ends (replaces
-- Blizzard's square bling, which can't follow a non-square shape). Fired from the
-- Cooldown finish flash. The GCD also fires OnCooldownDone, so it's filtered by the GAME
-- CLOCK: a SetCooldown hook stamps gbStart = GetTime() and we flash only when the elapsed
-- wall-time clears FLASH_MIN_CD. The cooldown DURATION is a protected/secret value —
-- comparing it taints (confirmed in-game) — so we never read it. OnCooldownDone also
-- CLEARS gbStart, so a new cooldown racing in at a GCD boundary must re-stamp instead of
-- inheriting a stale start that spanned several GCDs (which false-flashed whole rotations).
-- The flash reuses the shape's soft glow bloom, tinted + anchored fresh each play.
-- ---------------------------------------------------------------------------
local FLASH_MIN_CD = 2.0        -- seconds of real cooldown below which we skip (≈ GCD)
local FLASH_DURATION = 0.45
local FLASH_SCALE = 128 / 80    -- same bloom sizing as the proc glow (art edge at 80/128)
local function playFinishFlash(btn)
  local db = GB.db or {}
  if not db.finishFlash then return end
  local rec = records[btn]
  local icon = btn.icon or btn.Icon
  if not (rec and rec.active and icon and rec.flashFrame) then return end
  local hk = handKey()
  rec.flashTex:SetTexture(hk and GB:HandAsset(hk, "outer") or Skin:GlowArt())
  local c = db.finishFlashColor or { 1, 0.9, 0.5 }
  rec.flashTex:SetVertexColor(c[1], c[2], c[3])
  -- Hand shape: the outer glow art's silhouette maps to the icon (bloom in the
  -- margin), and the burst's scale-out expands it. Else the SDF construction anchor.
  if hk then hgAnchor(rec.flashFrame, constructRef(btn, icon), 0)   -- full 2:1 plate in plate mode
  else AnchorConstruction(rec.flashFrame, icon, (FLASH_SCALE - 1) / 2) end
  rec.flashFrame:SetAlpha(1)
  rec.flashAnim:Stop(); rec.flashAnim:Play()
end
-- Hook ONE cooldown frame for the flash. SetCooldown records whether THIS cooldown is a
-- real one (duration > a GCD); OnCooldownDone flashes only if so. Reacting to the length
-- Blizzard draws sidesteps the old wall-clock timer's race at GCD boundaries (which
-- false-flashed whole rotations). Normal + charge cooldowns each keep their own flag.
local function hookFlashCooldown(btn, cd)
  if not (cd and cd.HookScript) then return end
  cd:HookScript("OnCooldownDone", function()
    local elapsed = cd.gbStart and (GetTime() - cd.gbStart)
    cd.gbRunning, cd.gbStart = false, nil   -- clear: a new cooldown must re-stamp (kills the
                                            -- GCD-boundary race where a stale start false-flashed)
    if elapsed and elapsed >= FLASH_MIN_CD then playFinishFlash(btn) end
  end)
  hooksecurefunc(cd, "SetCooldown", function()   -- no args read → the secret duration is never touched
    if not cd.gbRunning then cd.gbStart = GetTime(); cd.gbRunning = true end
  end)
end
-- One-time per-button setup: the flash frame/texture + an EXPANDING burst (alpha
-- fade + scale-out, so it reads as a shaped burst, not a static glow) + the flash
-- hooks on both the normal and charge cooldowns.
local function setupFinishFlash(btn, rec)
  if rec.flashFrame then return end
  local f = CreateFrame("Frame", nil, btn)
  f:SetFrameLevel(btn:GetFrameLevel() + 5)   -- above the cooldown + text
  local tex = f:CreateTexture(nil, "OVERLAY")
  tex:SetBlendMode("ADD"); tex:SetAllPoints(f)
  local ag = f:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(FLASH_DURATION); a:SetSmoothing("OUT")
  local sc = ag:CreateAnimation("Scale")
  sc:SetScaleFrom(0.85, 0.85); sc:SetScaleTo(1.5, 1.5); sc:SetOrigin("CENTER", 0, 0)
  sc:SetDuration(FLASH_DURATION); sc:SetSmoothing("OUT")
  if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
  ag:SetScript("OnFinished", function() f:SetAlpha(0) end)
  f:SetAlpha(0)
  rec.flashFrame, rec.flashTex, rec.flashAnim = f, tex, ag
  hookFlashCooldown(btn, btn.cooldown)
  hookFlashCooldown(btn, btn.chargeCooldown)
end

-- ---------------------------------------------------------------------------
-- Availability restyle — Blizzard's UpdateUsable sets the icon vertex colour
-- (usable 1,1,1 / out-of-mana 0.5,0.5,1 / unusable 0.4,0.4,0.4). We REACT to that
-- rendered colour — never calling IsUsableAction — and swap in the user's tint +
-- optional desaturation. The detected state is stashed on rec so a live settings
-- change can re-apply without re-reading (our own tint would misread as the
-- state). Only OUR desaturation is cleared (rec.gbDesat) so Blizzard's level-link
-- desaturation is left intact.
-- ---------------------------------------------------------------------------
-- Apply the icon tint from the two REACTED-TO signals stashed on rec: availState
-- (from UpdateUsable's vertex colour) and outOfRange (from UpdateRangeIndicator's
-- inRange arg). Out-of-range wins (it's the actionable one, matching Blizzard's red
-- keybind); else usable/oom/unusable. Only OUR desaturation is cleared (rec.gbDesat).
local function computeIconTint(btn)
  local rec = records[btn]
  local icon = btn.icon or btn.Icon
  if not (rec and rec.active and icon) then return end
  local db = GB.db or {}
  -- Track OUR desaturation on rec.gbDesat so we only ever clear what we set (leaves
  -- Blizzard's level-link desaturation alone).
  local function setDesat(on)
    if on then icon:SetDesaturated(true); rec.gbDesat = true
    elseif rec.gbDesat then icon:SetDesaturated(false); rec.gbDesat = nil end
  end
  if db.rangeTint and rec.outOfRange then
    -- Desaturate FIRST, then tint → a clean red wash over greyscale (not a multiply
    -- that lets the icon's own colours bleed through). Jason 2026-07-20.
    local c = db.rangeColor or { 1, 0.2, 0.2 }
    setDesat(true); icon:SetVertexColor(c[1], c[2], c[3])
    -- Recolour Blizzard's red out-of-range keybind to match (it sets the HotKey
    -- VERTEX colour; ours overrides it. In range, Blizzard restores the default —
    -- our range hook doesn't fire the else, so we leave the keybind to Blizzard).
    if btn.HotKey then btn.HotKey:SetVertexColor(c[1], c[2], c[3]) end
  elseif rec.availState == "oom" then
    local c = db.availOOM or { 0.5, 0.5, 1 }; setDesat(false); icon:SetVertexColor(c[1], c[2], c[3])
  elseif rec.availState == "unusable" then
    local c = db.availUnusable or { 0.4, 0.4, 0.4 }; icon:SetVertexColor(c[1], c[2], c[3])
    setDesat(db.availDesaturate and true or false)
  else   -- usable / in range: reset to full colour (the range hook doesn't touch the
    setDesat(false); icon:SetVertexColor(1, 1, 1)   -- icon, so we must clear our own tint here)
  end
end
-- Post-hook of UpdateUsable: the icon vertex is Blizzard's fresh state → read it to
-- detect the state (never our own tint: Blizzard re-sets the canonical colour at the
-- top of UpdateUsable, before this runs), then re-apply our combined tint.
local function refreshAvailability(btn)
  local rec = records[btn]
  local icon = btn.icon or btn.Icon
  if not (rec and rec.active and icon) then return end
  local r, _, b = icon:GetVertexColor()
  rec.availState = (r and r >= 0.9) and "usable" or ((b and b >= 0.9) and "oom" or "unusable")
  computeIconTint(btn)
end
-- Post-hook of ActionButton_UpdateRangeIndicator: Blizzard hands us checksRange +
-- inRange (we never call IsActionInRange), so just stash + recompute.
local function refreshRange(btn, checksRange, inRange)
  local rec = records[btn]
  if not (rec and rec.active) then return end
  rec.outOfRange = checksRange and not inRange and true or false
  computeIconTint(btn)
end
local function applyAvailabilityAll()
  if not Skin.enabled then return end
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    if rec and rec.active then computeIconTint(btn) end
  end)
end
function Skin:SetAvailDesaturate(b) if GB.db then GB.db.availDesaturate = b end; applyAvailabilityAll() end
function Skin:SetAvailUnusable(c) if GB.db then GB.db.availUnusable = c end; applyAvailabilityAll() end
function Skin:SetAvailOOM(c) if GB.db then GB.db.availOOM = c end; applyAvailabilityAll() end
function Skin:SetRangeTint(b) if GB.db then GB.db.rangeTint = b end; applyAvailabilityAll() end
function Skin:SetRangeColor(c) if GB.db then GB.db.rangeColor = c end; applyAvailabilityAll() end

-- Icon W/H for the active hand shape: short side = the button's Edit-Mode size ×
-- sizeScale; the long side = short × the shape's aspect on its long axis. Returns
-- nil when no hand shape is set (legacy free-size path). This is the pivot: the
-- silhouette dictates the proportion, so the icon can never be sized to the wrong
-- aspect (which is what warped the old glows/overlays).
local function handIconSize(btn)
  local hk = handKey()
  if not hk then return nil end
  local info = GB:HandShapeInfo(hk)
  local nat = (btn.GetWidth and btn:GetWidth()) or 0
  if not (nat and nat > 0) then nat = 45 end
  local scale = (GB.db and GB.db.sizeScale) or 1
  local short = math.max(8, math.floor(nat * scale + 0.5))
  if info.orient == "portrait" then return short, math.floor(short * info.aspect + 0.5)
  elseif info.orient == "landscape" then return math.floor(short * info.aspect + 0.5), short
  else return short, short end
end

-- Resize the VISIBLE icon (centered on the button). The secure button's hit area
-- is untouched (textures aren't protected). With a hand shape active, W/H come
-- from the shape's aspect × size scale (and are mirrored into db.iconW/iconH so
-- downstream anchor/preview math stays consistent). Otherwise the legacy free
-- iconW/iconH ("auto"/nil = leave Blizzard's anchoring). Defined before its callers.
local function applyIconSize(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return end
  local w, h = handIconSize(btn)
  if w and h and plateActive() then
    -- Plate mode: SQUARE icon (w×w) in one half of the w×2w (=w×h) construction; the
    -- construction stays centred on the button, so the icon's half-centre is ±w/2.
    local dy = (plateIconSide() == "bottom") and (-w * 0.5) or (w * 0.5)
    if GB.db then GB.db.iconW, GB.db.iconH = w, w end
    icon:ClearAllPoints(); icon:SetPoint("CENTER", btn, "CENTER", 0, dy); icon:SetSize(w, w)
    return
  end
  if w and h then
    if GB.db then GB.db.iconW, GB.db.iconH = w, h end
  else
    w, h = GB.db and GB.db.iconW, GB.db and GB.db.iconH
  end
  if not (w and h) then return end
  icon:ClearAllPoints()
  icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  icon:SetSize(w, h)
end

-- `silent` = suppress the chat message (the Config slider calls this every tick;
-- only the /gb sweep slash command wants the feedback line).
function Skin:SetSweepOvershoot(px, silent)
  if px then
    GB.db.sweepOvershoot = px
    if not silent then GB.msg(("sweep overshoot set to %.2f px."):format(px)) end
  elseif not silent then
    GB.msg(("sweep overshoot is %.2f px (usage: /gb sweep 1.25)"):format(GB.db.sweepOvershoot or 0.75))
  end
  if self.enabled then
    GB:ForEachButton(function(btn) AlignCooldowns(btn) end)
  end
end

-- Icon zoom-crop is a plain SetTexCoord (no mask re-render, no Blizzard re-set —
-- API-NOTES §3), so it's safe to change LIVE: just re-apply the texcoord to every
-- skinned icon. Driven by the Config UI's zoom slider.
function Skin:SetZoom(v)
  v = math.max(0, math.min(0.45, tonumber(v) or ZOOM))
  if GB.db then GB.db.zoom = v end
  if self.enabled then
    GB:ForEachButton(function(btn)
      local rec = records[btn]
      local icon = btn.icon or btn.Icon
      if rec and rec.active and icon then applyTexCoord(icon) end
    end)
  end
end

-- Live icon fill mode: "fill" (cover, keeps aspect + crops) or "stretch". Pure
-- SetTexCoord re-apply, safe live. Driven by the Config UI's "Crop to fill" toggle.
function Skin:SetIconFill(mode)
  if GB.db then GB.db.iconFill = mode end
  if not self.enabled then return end
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    local icon = btn.icon or btn.Icon
    if rec and rec.active and icon then applyTexCoord(icon) end
  end)
end

-- Live shape change. Editing a live mask's texture never re-renders (API-NOTES
-- §2), so swap the shape by creating FRESH masks — for the icon AND every
-- decoration plate — and re-setting the SetTexture-based shaped art (swipe,
-- state rings). The old mask objects are orphaned (can't be destroyed); the
-- churn is bounded per session and cleared on /reload.
function Skin:SetShape(name)
  if name then GB.db.shape = name end
  if not self.enabled then return end
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    local icon = btn.icon or btn.Icon
    if not (rec and rec.active and icon) then return end
    -- Icon + plate masks are rebuilt by ApplyDecor below — it picks the aspect
    -- mask for the new shape (and detects the change via the mask cache key).
    -- Here we only re-set the SetTexture-based overlay art, which re-sets live.
    -- (Cast/channel fill is re-shaped lazily in the PlaySpellCastAnim hook.)
    applyShapeArt(btn, icon)
    ApplyDecor(btn)
  end)
  if GB.Glows then GB.Glows:RefreshShape() end   -- proc halo art follows the new shape
end

-- Live state-highlight tint. `which` = hover | selected | flash → the matching
-- highlight/checked/flash texture on every button. Pure SetVertexColor, safe live.
function Skin:SetStateColor(which, c)
  GB.db.stateColors = GB.db.stateColors or {}
  GB.db.stateColors[which] = c
  if not (self.enabled and c) then return end
  -- Hand shape: hover/selected/flash are the multi-part glow → re-tint via Glows.
  if handKey() then if GB.Glows and GB.Glows.RefreshState then GB.Glows:RefreshState() end; return end
  GB:ForEachButton(function(btn)
    local tex
    if which == "hover" and btn.GetHighlightTexture then tex = btn:GetHighlightTexture()
    elseif which == "selected" and btn.GetCheckedTexture then tex = btn:GetCheckedTexture()
    elseif which == "flash" then tex = btn.Flash end
    if tex then tex:SetVertexColor(c[1], c[2], c[3]) end
  end)
end

function Skin:SetStateIntensity(v)
  GB.db.stateIntensity = v
  if not self.enabled then return end
  if handKey() then if GB.Glows and GB.Glows.RefreshState then GB.Glows:RefreshState() end; return end
  GB:ForEachButton(function(btn)
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    local ct = btn.GetCheckedTexture and btn:GetCheckedTexture()
    if hl then hl:SetAlpha(v) end
    if ct then ct:SetAlpha(v) end
    if btn.Flash then btn.Flash:SetAlpha(v) end
  end)
end

-- Live "Glow width": re-anchor the three state rings (hover/checked/flash) to the
-- new spread. Pure re-anchor (no art swap, no mask) → safe live, no secret reads.
-- (No-op for hand shapes: the multi-part glow's size is baked into the art.)
function Skin:SetStateWidth(v)
  GB.db.stateWidth = v
  if not self.enabled then return end
  if handKey() then return end
  local r = stateWidthRatio()
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    local icon = btn.icon or btn.Icon
    if not (rec and rec.active and icon) then return end
    local function fit(tex) if tex then AnchorConstruction(tex, icon, r) end end
    if btn.GetHighlightTexture then fit(btn:GetHighlightTexture()) end
    if btn.GetCheckedTexture then fit(btn:GetCheckedTexture()) end
    fit(btn.Flash)
  end)
end

-- Full per-button geometry refresh after a size- or shape-affecting change: re-size
-- the icon, re-crop (cover-fit), re-pick overlay art for the aspect, re-anchor the
-- state rings + cooldowns, and rebuild masks/plates via ApplyDecor. All plain
-- re-anchors + file swaps — the secure hit area is never touched.
local function refreshIconGeometry(btn)
  local rec = records[btn]
  local icon = btn.icon or btn.Icon
  if not (rec and rec.active and icon) then return end
  applyIconSize(btn)
  applyTexCoord(icon)        -- cover-fit crop follows the new aspect (no art stretch)
  applyShapeArt(btn, icon)   -- swap overlay art to the new aspect (ring/swipe)
  local function fit(tex) if tex then AnchorConstruction(tex, icon, stateWidthRatio()) end end
  if btn.GetHighlightTexture then fit(btn:GetHighlightTexture()) end
  if btn.GetCheckedTexture then fit(btn:GetCheckedTexture()) end
  fit(btn.Flash)
  AlignCooldowns(btn)
  ApplyDecor(btn)
end

-- Plate-mode apply. Enable / icon-side change the icon geometry (square-in-half) → a full
-- per-button refreshIconGeometry; colour / fade are decoration-only, so those callers use
-- ReapplyDecor instead. No-op unless a 2:1 portrait shape + plate.enabled is live.
function Skin:RefreshPlate()
  if not self.enabled then return end
  GB:ForEachButton(refreshIconGeometry)
  if GB.Glows then GB.Glows:RefreshShape(); GB.Glows:RefreshSize() end
end

-- Live icon resize (legacy free-size path; a hand shape overrides these dims in
-- applyIconSize). Kept for the SDF fallback; the hand-shape UI drives size via
-- SetSizeScale instead.
function Skin:SetIconSize(w, h)
  GB.db.iconW, GB.db.iconH = w, h
  if not self.enabled then return end
  GB:ForEachButton(refreshIconGeometry)
  if GB.Glows then GB.Glows:RefreshSize() end   -- proc halo tracks the new icon size/aspect
end

-- Activate a hand-authored silhouette (a GB.HAND_SHAPES key) — persisted. Sourcing
-- its base for the icon/plate/border AND re-deriving the icon's W/H from the shape's
-- aspect × size scale, so the whole construction takes the exact silhouette with no
-- manual sizing. Falls back through refreshIconGeometry's proven ApplyDecor rebuild.
function Skin:SetHandShape(key)
  if key then GB.db.handShape = key end
  if not self.enabled then return end
  GB:ForEachButton(refreshIconGeometry)
  if GB.Glows then GB.Glows:RefreshShape(); GB.Glows:RefreshSize() end
end

-- Live uniform size scale (× the Edit-Mode button size). The hand shape keeps its
-- aspect; only the overall scale changes. Pure re-anchors + file swaps, safe live.
function Skin:SetSizeScale(v)
  if GB.db then GB.db.sizeScale = v end
  if not self.enabled then return end
  GB:ForEachButton(refreshIconGeometry)
  if GB.Glows then GB.Glows:RefreshSize() end
end

local function ApplyButton(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return end
  local rec = records[btn]
  if rec and rec.active then return end
  applyIconSize(btn)
  if not rec then
    rec = {}
    records[btn] = rec
    local ext0 = ExtensionHeight(icon)
    local src0, key0 = maskPlan(icon, ext0)
    rec.mask = buildMask(btn, icon, ext0, src0)
    rec.maskKey = key0
    rec.texCoord = { icon:GetTexCoord() }
    -- Capture the pristine keybind font/justify BEFORE we ever override it, so
    -- turning Custom keybind OFF restores it exactly (Blizzard's UpdateHotkeys
    -- re-anchors + re-sizes but never re-sets the font — API-NOTES §3).
    if btn.HotKey then rec.hkFont = { btn.HotKey:GetFont() }; rec.hkJustify = btn.HotKey:GetJustifyH(); rec.hkColor = { btn.HotKey:GetTextColor() } end
    if btn.UpdateButtonArt then
      hooksecurefunc(btn, "UpdateButtonArt", function(b)
        if Skin.enabled then
          applyIconSize(b)
          Suppress(b)
          AlignCooldowns(b)
        end
      end)
    end
    if btn.UpdateAssistedCombatRotationFrame then
      hooksecurefunc(btn, "UpdateAssistedCombatRotationFrame", function(b)
        if Skin.enabled then StyleAssistedFrame(b) end
      end)
    end
    if btn.PlaySpellCastAnim then
      hooksecurefunc(btn, "PlaySpellCastAnim", function(b, castType)
        if Skin.enabled and records[b] then
          -- Suppress Blizzard's fill + drive our own here (frame live at cast
          -- time; keeps mask creation off the size-slider hot path).
          styleCast(b, records[b], b.icon or b.Icon, castType)
          StyleCastInnerGlow(b, castType)
        end
      end)
    end
    if btn.UpdateHotkeys then
      hooksecurefunc(btn, "UpdateHotkeys", function(b)
        if not (Skin.enabled and records[b]) then return end
        symbolizeButton(b)                                    -- Mac modifier icons (if opted in)
        if records[b].hkOverridden then ApplyHotkeyOverride(b) end
      end)
    end
    if btn.UpdateUsable then
      hooksecurefunc(btn, "UpdateUsable", function(b)
        if Skin.enabled and records[b] then refreshAvailability(b) end   -- restyle usable/unusable/OOM
      end)
    end
  end
  if btn.IconMask then
    icon:RemoveMaskTexture(btn.IconMask)
    rec.iconMaskRemoved = true
  end
  applyTexCoord(icon)   -- zoom crop, cover-fit to the icon's aspect (part a)
  icon:AddMaskTexture(rec.mask)
  -- Round state art. One-time: originals aren't recoverable without /reload
  -- (Disable() says so). Anchored to the icon oversized by the padding ratio
  -- so the ring rim coincides with the icon circle.
  if not rec.stateArt then
    local ring = shapeArt(icon).ring
    -- Hand shape (the norm): hover / selected / flash are ALL driven by the multi-
    -- part glow (Glows.lua), so SUPPRESS Blizzard's square hover/checked/flash rings
    -- (alpha 0). SDF fallback shows all three. Ring rim sits inset from the shape
    -- edge → oversize so it reaches/spreads past the edge.
    local sa = handKey() and 0 or stateIntensity()
    local function fit(tex) AnchorConstruction(tex, icon, stateWidthRatio()) end
    if btn.SetHighlightTexture and btn.GetHighlightTexture then
      btn:SetHighlightTexture(ring, "ADD")
      local hl = btn:GetHighlightTexture()
      hl:SetVertexColor(unpack(stateColor("highlight"))); hl:SetAlpha(sa)
      fit(hl)
    end
    if btn.SetCheckedTexture and btn.GetCheckedTexture then
      btn:SetCheckedTexture(ring)
      local ct = btn:GetCheckedTexture()
      ct:SetBlendMode("ADD")
      ct:SetVertexColor(unpack(stateColor("checked"))); ct:SetAlpha(sa)
      fit(ct)
    end
    if btn.Flash then
      btn.Flash:SetTexture(ring)
      btn.Flash:SetVertexColor(unpack(stateColor("flash"))); btn.Flash:SetAlpha(sa)   -- hand shape → glow drives it
      fit(btn.Flash)
    end
    -- Blizzard's UpdateFlash re-drives GetCheckedTexture():SetAlpha(1.0) on the
    -- auto-attacking (flashing) button (ActionButton.lua:1306) — defeating our one-
    -- time alpha-0 above and un-hiding the square checked ring over the shaped glow.
    -- Re-assert alpha 0 AFTER Blizzard's call for hand shapes (the glow owns the look).
    if btn.UpdateFlash then
      hooksecurefunc(btn, "UpdateFlash", function(b)
        if Skin.enabled and handKey() and b.GetCheckedTexture then
          local c = b:GetCheckedTexture(); if c then c:SetAlpha(0) end
        end
      end)
    end
    rec.stateArt = true
  end
  -- Shaped cooldown sweep: the swipe respects its texture's alpha, and Blizzard's
  -- cooldown path never re-sets swipe textures (only SetCooldown/Clear +
  -- SetSwipeColor around cast anims — API-NOTES §3), so one-time setup persists.
  -- chargeCooldown IS included now (it was edge-only → the recharge showed a bare
  -- square edge and no shaped sweep); applySwipe forces its swipe on + edge off.
  if not rec.cooldownStyled then
    local hk = handKey()
    local swipe = (hk and GB:HandAsset(hk, "swipe")) or shapeArt(icon).swipe
    for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown, btn.chargeCooldown }) do
      if cd and cd.SetSwipeTexture then
        cd:SetSwipeTexture(swipe)
        -- Sweep tint/opacity, force the swipe on, suppress the square edge/bling.
        applySwipe(cd)
      end
    end
    rec.cooldownStyled = true
  end
  setupFinishFlash(btn, rec)   -- our shaped cooldown-end burst (once per button)
  -- Re-assert the custom sweep colour after Blizzard resets it to (0,0,0,1) at
  -- cast-end (ActionButton.lua). One global hook, installed once; gated to our
  -- skinned buttons. If the global isn't present, a custom colour just reverts
  -- to black after a cast (graceful) rather than erroring.
  if not Skin._swipeHook and type(ActionButton_UpdateCooldown) == "function" then
    Skin._swipeHook = true
    hooksecurefunc("ActionButton_UpdateCooldown", function(b)
      local r = b and records[b]
      if Skin.enabled and r and r.active then applySwipe(b.cooldown) end
    end)
  end
  -- Out-of-range icon tint: react to Blizzard's own range determination (passed as
  -- inRange), never IsActionInRange. One global hook, installed once.
  if not Skin._rangeHook and type(ActionButton_UpdateRangeIndicator) == "function" then
    Skin._rangeHook = true
    hooksecurefunc("ActionButton_UpdateRangeIndicator", function(b, checksRange, inRange)
      local r = b and records[b]
      if Skin.enabled and r and r.active then refreshRange(b, checksRange, inRange) end
    end)
  end
  if not rec.textStyled then
    StyleText(btn)
    rec.textStyled = true
  end
  -- Cast/channel visuals (suppress Blizzard's square fill + draw our own pill
  -- fill, shape the end burst, replace the inner-glow art) are all applied in the
  -- PlaySpellCastAnim hook — the Fill frames are live at cast time, and it keeps
  -- mask/fill work off the size-slider hot path. See styleCast / StyleCastInnerGlow.
  StyleAssistedFrame(btn)
  AlignCooldowns(btn)
  Suppress(btn)
  rec.active = true
  ApplyDecor(btn)
  symbolizeButton(btn)   -- symbolize the already-set hotkey text (the hook covers later updates)
end

local function RestoreButton(btn)
  local rec = records[btn]
  local icon = btn.icon or btn.Icon
  if not (rec and rec.active and icon) then return end
  icon:RemoveMaskTexture(rec.mask)
  if rec.iconMaskRemoved and btn.IconMask then
    icon:AddMaskTexture(btn.IconMask)
    rec.iconMaskRemoved = nil
  end
  if rec.texCoord then icon:SetTexCoord(unpack(rec.texCoord)) end
  if btn.NormalTexture then btn.NormalTexture:SetAlpha(1) end
  if btn.PushedTexture then btn.PushedTexture:SetAlpha(1) end
  if btn.Border then btn.Border:SetAlpha(1) end
  if rec.plates then
    for _, plate in ipairs(rec.plates) do plate.tex:Hide() end
  end
  -- Custom cast fill: hide ours + un-suppress Blizzard's (a /reload is exact).
  if rec.castFillFrame then rec.castFillFrame:Hide() end
  local caf = btn.SpellCastAnimFrame
  if caf and caf.Fill and caf.Fill.CastFill then caf.Fill.CastFill:SetAlpha(1) end
  if rec.hkOverridden then
    rec.hkOverridden = nil
    btn.HotKey:SetJustifyH(rec.hkJustify or "RIGHT")
    if rec.hkFont and rec.hkFont[1] then btn.HotKey:SetFont(rec.hkFont[1], rec.hkFont[2], rec.hkFont[3] or "") end
    if rec.hkColor then btn.HotKey:SetTextColor(rec.hkColor[1], rec.hkColor[2], rec.hkColor[3], rec.hkColor[4] or 1) end
    if btn.UpdateHotkeys then btn:UpdateHotkeys(btn.buttonType) end
  end
  rec.active = false
  -- Blizzard restores correct slot-art state itself (branching on the bar's
  -- Edit-Mode hide-bar-art setting).
  if btn.UpdateButtonArt then btn:UpdateButtonArt() end
  -- Cooldown swipe/edge/bling defaults live in the template with no reliable
  -- getters — a /reload fully restores them (Disable() says so).
end

function Skin:Enable()
  self.enabled = true
  if GB.db then GB.db.skinEnabled = true end
  local count = 0
  GB:ForEachButton(function(btn)
    ApplyButton(btn)
    count = count + 1
  end)
  GB.msg(("skin ON — %d buttons styled. Persists across /reload; /gb skin to turn off."):format(count))
  if GB.Glows then GB.Glows:SetEnabled(true) end
end

function Skin:Disable()
  self.enabled = false
  if GB.db then GB.db.skinEnabled = false end
  GB:ForEachButton(function(btn) RestoreButton(btn) end)
  if GB.Glows then GB.Glows:SetEnabled(false) end
  GB.msg("skin OFF — Blizzard defaults restored (/reload to also restore cooldown sweep shape).")
end

function Skin:Toggle()
  if self.enabled then self:Disable() else self:Enable() end
end

-- Re-apply on login when persisted (all bar buttons exist by PLAYER_LOGIN;
-- GB.db is ready — ADDON_LOADED fires earlier).
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  if GB.db and GB.db.skinEnabled then
    Skin:Enable()
  end
end)

-- Re-assert suppression on equip / action-placement / world-enter: Blizzard
-- re-shows the equipped-item green .Border (and slot art) on these, undoing our
-- one-time Suppress (verified /gb borderinfo: .Border back at alpha 0.5). These
-- events are infrequent, and Suppress is cheap (mostly no-op Hide/SetAlpha).
local reassert = CreateFrame("Frame")
reassert:RegisterEvent("PLAYER_ENTERING_WORLD")
reassert:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
reassert:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
reassert:SetScript("OnEvent", function()
  if Skin.enabled then GB:ForEachButton(function(b) Suppress(b) end) end
end)
