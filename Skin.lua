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

local ZOOM = 0.08
-- The circle art is padded to 240/256 of its canvas (edge-bleed rule,
-- API-NOTES §2); oversize the mask region so the circle spans the icon.
local GROW_RATIO = (256 / 240 - 1) / 2

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
  -- The ICON's own mask must span the construction too, so icon + extension
  -- read as one continuous shape. (Anchor edits on a live mask: verified-by-QA
  -- pending; /reload applies pre-render and is always exact.)
  AnchorConstructionMask(rec.mask, icon, ext)
  local used = 0
  for i, layer in ipairs(style.layers or {}) do
    if layer.kind == "gradient" then
      used = used + 1
      local plate = rec.plates[used]
      if not plate then
        rec.decorFrame = rec.decorFrame or CreateFrame("Frame", nil, btn)
        rec.decorFrame:SetAllPoints(icon)
        rec.decorFrame:SetFrameLevel(btn:GetFrameLevel() + 2)
        local tex = rec.decorFrame:CreateTexture(nil, "ARTWORK")
        -- A white texture FILE, not SetColorTexture: masks don't clip
        -- solid-color textures (QA 2026-07-18 — square plate corners).
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        local mask = rec.decorFrame:CreateMaskTexture()
        mask:SetTexture(GB:GetShape().mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        tex:AddMaskTexture(mask)
        plate = { tex = tex, mask = mask }
        rec.plates[used] = plate
      end
      AnchorConstructionMask(plate.mask, icon, ext)
      local tex = plate.tex
      tex:ClearAllPoints()
      local c = layer.color or { 1, 1, 1 }
      local fromA, toA = layer.fromAlpha or 1, layer.toAlpha or 0
      if layer.zone == "extension" and ext > 0 then
        -- Fill the extension below the icon, bleeding up into the icon's
        -- bottom edge so the gradient fades across the boundary (mockup).
        tex:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, -ext)
        tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, -ext)
        tex:SetHeight(ext + icon:GetHeight() * (layer.bleedPct or 0.4))
      else
        tex:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        tex:SetHeight(icon:GetHeight() * (layer.sizePct or 0.4))
      end
      -- VERTICAL gradient: min color = bottom, max color = top.
      tex:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], fromA), CreateColor(c[1], c[2], c[3], toA))
      tex:Show()
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

local function ApplyButton(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return end
  local rec = records[btn]
  if rec and rec.active then return end
  if not rec then
    rec = {}
    records[btn] = rec
    rec.mask = btn:CreateMaskTexture()
    rec.mask:SetTexture(GB:GetShape().mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local grow = icon:GetWidth() * GROW_RATIO
    rec.mask:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
    rec.mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
    rec.texCoord = { icon:GetTexCoord() }
    if btn.UpdateButtonArt then
      hooksecurefunc(btn, "UpdateButtonArt", function(b)
        if Skin.enabled then
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
  icon:SetTexCoord(ZOOM, 1 - ZOOM, ZOOM, 1 - ZOOM)
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
      hl:SetVertexColor(unpack(STATE_TINT.highlight))
      fit(hl)
    end
    if btn.SetCheckedTexture and btn.GetCheckedTexture then
      btn:SetCheckedTexture(GB:GetShape().ring)
      local ct = btn:GetCheckedTexture()
      ct:SetBlendMode("ADD")
      ct:SetVertexColor(unpack(STATE_TINT.checked))
      fit(ct)
    end
    if btn.Flash then
      btn.Flash:SetTexture(GB:GetShape().ring)
      btn.Flash:SetVertexColor(unpack(STATE_TINT.flash))
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
