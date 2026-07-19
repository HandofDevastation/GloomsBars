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
end

-- ---------------------------------------------------------------------------
-- Decoration engine — interprets GB.STYLES recipes (the design north star).
-- Plates are pooled per button (textures can't be destroyed, only reused) and
-- clipped by fresh per-plate shape masks (our-own-texture + fresh-mask = the
-- provably safe path). The HotKey override re-asserts via an UpdateHotkeys
-- post-hook (Blizzard re-anchors it top-right on every update).
-- ---------------------------------------------------------------------------
-- The construction = the icon plus an optional extension zone below it (extra
-- visible real estate — textures may draw beyond the secure button's bounds).
-- Returns the extension height in px for the current style.
local function ExtensionHeight(icon)
  local construction = GB:GetStyle().construction
  return icon:GetHeight() * ((construction and construction.extendBottomPct) or 0)
end

-- Anchor a mask over the whole construction (padding-compensated per axis).
local function AnchorConstructionMask(mask, icon, ext)
  local growX = icon:GetWidth() * GROW_RATIO
  local growY = (icon:GetHeight() + ext) * GROW_RATIO
  mask:ClearAllPoints()
  mask:SetPoint("TOPLEFT", icon, "TOPLEFT", -growX, growY)
  mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", growX, -(growY + ext))
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
local function aspectMask(w, h)
  if not (w and h) or w <= 0 or h <= 0 or math.abs(w - h) < 0.5 then return nil end
  local pattern, level = parseShape()
  if pattern ~= "1111" then return nil end
  local tall = h > w
  local ratio = tall and (h / w) or (w / h)
  local bi, be = 1, math.huge
  for i, rr in ipairs(PILL_RATIOS) do
    local e = math.abs(rr - ratio)
    if e < be then be, bi = e, i end
  end
  return GB.MEDIA .. "masks\\" .. ("pill-%s-a%d-r%d"):format(tall and "t" or "w", bi - 1, level) .. ".png"
end
function Skin:AspectMask(w, h) return aspectMask(w, h) end

-- (maskPath, cacheKey) for the construction around `icon` (+ext). src is the
-- aspect mask when the shape/aspect calls for one, else nil (plain shape mask).
-- The key lets callers skip a fresh-mask rebuild (source swaps never re-render —
-- §2) when nothing shape-relevant changed (a plain re-anchor re-clips live).
local function maskPlan(icon, ext)
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

local function ApplyHotkeyOverride(btn)
  local rec = records[btn]
  local hk = btn.HotKey
  local icon = btn.icon or btn.Icon
  if not (rec and hk and icon) then return end
  local conf = GB:GetStyle().hotkey
  if not conf then
    if rec.hkOverridden then
      -- Best-effort revert: Blizzard restores anchors/size; /reload is exact.
      rec.hkOverridden = nil
      hk:SetJustifyH("RIGHT")
      if btn.UpdateHotkeys then btn:UpdateHotkeys(btn.buttonType) end
    end
    return
  end
  local ext = ExtensionHeight(icon)
  hk:ClearAllPoints()
  if conf.zone == "extension" and ext > 0 then
    hk:SetPoint("CENTER", icon, "BOTTOM", conf.offsetX or 0, -(ext / 2) + (conf.offsetY or 0))
  else
    hk:SetPoint("CENTER", icon, "CENTER", conf.offsetX or 0, conf.offsetY or 0)
  end
  hk:SetSize(icon:GetWidth(), (conf.size or 13) + 4)
  hk:SetJustifyH("CENTER")
  hk:SetFont(GB.FONT[conf.font or "label"], conf.size or 13, conf.flags or "OUTLINE")
  if conf.color then hk:SetTextColor(unpack(conf.color)) end
  rec.hkOverridden = true
end

local function ApplyDecor(btn)
  local rec = records[btn]
  local icon = btn.icon or btn.Icon
  if not (rec and icon) then return end
  local style = GB:GetStyle()
  rec.plates = rec.plates or {}
  local ext = ExtensionHeight(icon)
  -- The ICON's own mask spans the whole construction, so icon + extension read
  -- as one continuous shape (a single clean pill wrapping both — Jason's mock).
  -- The aspect mask comes from the construction's aspect (maskPlan); a fresh
  -- mask is built only when that plan changes (source swaps never re-render —
  -- §2), otherwise a plain re-anchor re-clips live.
  local maskSrc, maskKey = maskPlan(icon, ext)
  if rec.mask and rec.maskKey == maskKey then
    AnchorConstructionMask(rec.mask, icon, ext)
  else
    if rec.mask then icon:RemoveMaskTexture(rec.mask) end
    rec.mask = buildMask(btn, icon, ext, maskSrc)
    icon:AddMaskTexture(rec.mask)
    rec.maskKey = maskKey
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
    end
    -- The plate shares the icon's mask plan so it joins the pill; rebuild the
    -- mask only when the plan changes, else re-anchor (re-clips live).
    if plate.mask and plate.maskKey == maskKey then
      AnchorConstructionMask(plate.mask, icon, ext)
    else
      if plate.mask then plate.tex:RemoveMaskTexture(plate.mask) end
      plate.mask = buildMask(rec.decorFrame, icon, ext, maskSrc)
      plate.tex:AddMaskTexture(plate.mask)
      plate.maskKey = maskKey
    end
    plate.tex:ClearAllPoints()
    return plate
  end
  local used = 0
  for i, layer in ipairs(style.layers or {}) do
    if layer.enabled ~= false and layer.kind == "gradient" then
      local c = layer.color or { 1, 1, 1 }
      local fromA, toA = layer.fromAlpha or 1, layer.toAlpha or 0
      if layer.zone == "extension" and ext > 0 then
        -- Mock-matched (QA 2026-07-18): the extension is FULL opacity all the
        -- way to the icon's bottom edge; the fade lives INSIDE the icon.
        used = used + 1
        local solid = getPlate(used)
        solid.tex:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, -ext)
        solid.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, -ext)
        solid.tex:SetHeight(ext)
        solid.tex:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], fromA), CreateColor(c[1], c[2], c[3], fromA))
        solid.tex:Show()
        used = used + 1
        local fade = getPlate(used)
        fade.tex:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        fade.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        fade.tex:SetHeight(icon:GetHeight() * (layer.bleedPct or 0.4))
        fade.tex:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], fromA), CreateColor(c[1], c[2], c[3], toA))
        fade.tex:Show()
      else
        used = used + 1
        local plate = getPlate(used)
        plate.tex:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        plate.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        plate.tex:SetHeight(icon:GetHeight() * (layer.sizePct or 0.4))
        -- VERTICAL gradient: min color = bottom, max color = top.
        plate.tex:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], fromA), CreateColor(c[1], c[2], c[3], toA))
        plate.tex:Show()
      end
    end
  end
  for i = used + 1, #rec.plates do rec.plates[i].tex:Hide() end
  -- Text must render above plates: raise Blizzard's text container once.
  if btn.TextOverlayContainer then
    btn.TextOverlayContainer:SetFrameLevel(btn:GetFrameLevel() + 4)
  end
  ApplyHotkeyOverride(btn)
end

function Skin:ReapplyDecor()
  if not self.enabled then return end
  GB:ForEachButton(function(btn)
    if records[btn] and records[btn].active then ApplyDecor(btn) end
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
  local grow = icon:GetWidth() * (RING_FIT - 1) / 2
  glow:SetTexture(GB:GetShape().ring)
  glow:ClearAllPoints()
  glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
  glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
  local isChannel = ActionButtonCastType and castType == ActionButtonCastType.Channel
  local tint = isChannel and CAST_TINT.channel or CAST_TINT.cast
  glow:SetVertexColor(tint[1], tint[2], tint[3])
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
  local grow = icon:GetWidth() * GROW_RATIO + (GB.db and GB.db.sweepOvershoot or 0.75)
  for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
    if cd then
      cd:ClearAllPoints()
      cd:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
      cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
    end
  end
end

-- Resize the VISIBLE icon to db.iconW/iconH (centered on the button). The secure
-- button's hit area is untouched (textures aren't protected). "auto" (nil) leaves
-- Blizzard's anchoring. Defined before the setters that call it (SetIconSize).
local function applyIconSize(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return end
  local w, h = GB.db and GB.db.iconW, GB.db and GB.db.iconH
  if not (w and h) then return end
  icon:ClearAllPoints()
  icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  icon:SetSize(w, h)
end

function Skin:SetSweepOvershoot(px)
  if px then
    GB.db.sweepOvershoot = px
    GB.msg(("sweep overshoot set to %.2f px."):format(px))
  else
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
  local shp = GB:GetShape()
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    local icon = btn.icon or btn.Icon
    if not (rec and rec.active and icon) then return end
    -- Icon + plate masks are rebuilt by ApplyDecor below — it picks the 9-slice
    -- plan for the new shape (and detects the change via the slice cache key).
    -- Here we only re-set the SetTexture-based shaped art, which re-sets live.
    for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
      if cd and cd.SetSwipeTexture then cd:SetSwipeTexture(shp.swipe) end
    end
    if btn.GetHighlightTexture then local hl = btn:GetHighlightTexture(); if hl then hl:SetTexture(shp.ring) end end
    if btn.GetCheckedTexture then local ct = btn:GetCheckedTexture(); if ct then ct:SetTexture(shp.ring) end end
    if btn.Flash then btn.Flash:SetTexture(shp.ring) end
    ApplyDecor(btn)
  end)
end

-- Live state-highlight tint. `which` = hover | selected | flash → the matching
-- highlight/checked/flash texture on every button. Pure SetVertexColor, safe live.
function Skin:SetStateColor(which, c)
  GB.db.stateColors = GB.db.stateColors or {}
  GB.db.stateColors[which] = c
  if not (self.enabled and c) then return end
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
  GB:ForEachButton(function(btn)
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    local ct = btn.GetCheckedTexture and btn:GetCheckedTexture()
    if hl then hl:SetAlpha(v) end
    if ct then ct:SetAlpha(v) end
    if btn.Flash then btn.Flash:SetAlpha(v) end
  end)
end

-- Live icon resize: re-anchor the visible icon, then everything that follows it
-- (state art, cooldowns, and mask + plates + hotkey via ApplyDecor). All plain
-- re-anchors — the secure hit area is never touched.
function Skin:SetIconSize(w, h)
  GB.db.iconW, GB.db.iconH = w, h
  if not self.enabled then return end
  GB:ForEachButton(function(btn)
    local rec = records[btn]
    local icon = btn.icon or btn.Icon
    if not (rec and rec.active and icon) then return end
    applyIconSize(btn)
    applyTexCoord(icon)   -- cover-fit crop follows the new aspect (no art stretch)
    local grow = icon:GetWidth() * GROW_RATIO
    local function fit(tex)
      if not tex then return end
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
      tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
    end
    if btn.GetHighlightTexture then fit(btn:GetHighlightTexture()) end
    if btn.GetCheckedTexture then fit(btn:GetCheckedTexture()) end
    fit(btn.Flash)
    AlignCooldowns(btn)
    ApplyDecor(btn)
  end)
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
        if Skin.enabled then StyleCastInnerGlow(b, castType) end
      end)
    end
    if btn.UpdateHotkeys then
      hooksecurefunc(btn, "UpdateHotkeys", function(b)
        if Skin.enabled and records[b] and records[b].hkOverridden then
          ApplyHotkeyOverride(b)
        end
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
    local grow = icon:GetWidth() * GROW_RATIO
    local function fit(tex)
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
      tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
    end
    if btn.SetHighlightTexture and btn.GetHighlightTexture then
      btn:SetHighlightTexture(GB:GetShape().ring, "ADD")
      local hl = btn:GetHighlightTexture()
      hl:SetVertexColor(unpack(stateColor("highlight"))); hl:SetAlpha(stateIntensity())
      fit(hl)
    end
    if btn.SetCheckedTexture and btn.GetCheckedTexture then
      btn:SetCheckedTexture(GB:GetShape().ring)
      local ct = btn:GetCheckedTexture()
      ct:SetBlendMode("ADD")
      ct:SetVertexColor(unpack(stateColor("checked"))); ct:SetAlpha(stateIntensity())
      fit(ct)
    end
    if btn.Flash then
      btn.Flash:SetTexture(GB:GetShape().ring)
      btn.Flash:SetVertexColor(unpack(stateColor("flash"))); btn.Flash:SetAlpha(stateIntensity())
      fit(btn.Flash)
    end
    rec.stateArt = true
  end
  -- Shaped cooldown sweep: the swipe respects its texture's alpha, and
  -- Blizzard's cooldown path never re-sets swipe textures (only SetCooldown/
  -- Clear + SetSwipeColor around cast anims — API-NOTES §3), so one-time
  -- setup persists. chargeCooldown is edge-only by default — left untouched.
  if not rec.cooldownStyled then
    for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
      if cd and cd.SetSwipeTexture then
        cd:SetSwipeTexture(GB:GetShape().swipe)
        -- The rotating edge line + finish bling are drawn to the SQUARE frame
        -- bounds and poke past a round sweep — off for the clean look.
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetDrawBling then cd:SetDrawBling(false) end
      end
    end
    rec.cooldownStyled = true
  end
  if not rec.textStyled then
    StyleText(btn)
    rec.textStyled = true
  end
  -- Shaped cast/channel fill: Blizzard clips the sliding CastFill with its
  -- rounded-square FillMask and leaves InnerGlowTexture unmasked (square).
  -- Replace with fresh per-texture shape masks (the proven-safe path — never
  -- multi-attach one mask, never mutate Blizzard's). Blizzard re-sets these
  -- textures' ATLASES per cast type (cast vs channel) but never their masks,
  -- so one-time setup persists (API-NOTES §3).
  if not rec.castStyled then
    local cast = btn.SpellCastAnimFrame
    local grow = icon:GetWidth() * GROW_RATIO
    -- Only for ALREADY-MASKED textures (the case where runtime mask swap
    -- provably renders — API-NOTES §2): remove Blizzard's rounded-square
    -- mask, attach a fresh shaped one.
    local function shapeClip(parent, target, blizzMask)
      if not (parent and target and blizzMask) then return end
      target:RemoveMaskTexture(blizzMask)
      local m = parent:CreateMaskTexture()
      m:SetTexture(GB:GetShape().mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
      m:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
      target:AddMaskTexture(m)
    end
    local fill = cast and cast.Fill
    if fill then shapeClip(fill, fill.CastFill, fill.FillMask) end
    local burst = cast and cast.EndBurst
    if burst then shapeClip(burst, burst.GlowRing, burst.EndMask) end
    -- Fill.InnerGlowTexture is never-rendered never-masked (runtime attach
    -- silently fails) → art replaced per-cast in the PlaySpellCastAnim hook.
    rec.castStyled = true
  end
  StyleAssistedFrame(btn)
  AlignCooldowns(btn)
  Suppress(btn)
  rec.active = true
  ApplyDecor(btn)
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
  if rec.plates then
    for _, plate in ipairs(rec.plates) do plate.tex:Hide() end
  end
  if rec.hkOverridden then
    rec.hkOverridden = nil
    btn.HotKey:SetJustifyH("RIGHT")
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
