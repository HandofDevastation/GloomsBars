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
  -- Equipped-item green border (rounded-square, mismatched on a pill) — suppress
  -- via alpha-0 (Blizzard toggles it Show/Hide, so alpha sticks). API-NOTES §1.
  if btn.Border then btn.Border:SetAlpha(0) end
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

-- Anchor a mask over the whole construction (padding-compensated per axis). `ext`
-- is the magnitude; the extension sits ABOVE or BELOW the icon per ExtensionAbove.
local function AnchorConstructionMask(mask, icon, ext)
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

-- Anchor a mask over the construction EXPANDED by `t` px on every side — for the
-- border backing (a colored copy of the shape behind the icon that peeks out by
-- `t`). Same padding compensation as AnchorConstructionMask, sized for the larger
-- region so the shape silhouette lands on the border's outer edge.
local function AnchorBorderMask(mask, icon, ext, t)
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
  -- Skip the SetTexture churn when the art is unchanged (e.g. dragging the size
  -- slider within one aspect bucket) — keeps the sliders smooth.
  local rec = records[btn]
  local key = tostring(art.ring) .. "|" .. tostring(art.swipe)
  if rec then
    if rec.artKey == key then return end
    rec.artKey = key
  end
  if btn.GetHighlightTexture then local hl = btn:GetHighlightTexture(); if hl then hl:SetTexture(art.ring) end end
  if btn.GetCheckedTexture then local ct = btn:GetCheckedTexture(); if ct then ct:SetTexture(art.ring) end end
  if btn.Flash then btn.Flash:SetTexture(art.ring) end
  for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
    if cd and cd.SetSwipeTexture then cd:SetSwipeTexture(art.swipe) end
  end
end

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

local function CastFillOnUpdate(f, elapsed)
  if f.blizzFill then f.blizzFill:SetAlpha(0) end
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
  if not (s and e and e > s) then
    -- Cast ended BEFORE completing (interrupted/cancelled)? Replay Blizzard's real
    -- completion burst, red. A clean finish (lastP ≈ 1) does nothing here — its own
    -- (gold) EndBurst already played.
    if f.lastP and f.lastP < 0.85 and not f.flashed then
      f.flashed = true
      PlayEndBurstRed(f)
    end
    f.tex:Hide()
    -- Keep suppressing Blizzard's fill + interrupt square for a grace window (the
    -- cast frame itself is hidden by the EndBurst OnFinished, so the burst plays
    -- through fully regardless of its speed).
    f.grace = (f.grace or 1.5) - (elapsed or 0)
    if f.grace <= 0 then f.lastP, f.flashed = nil, nil; f:Hide() end
    return
  end
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
  local src = aspectMask(icon:GetWidth(), icon:GetHeight() + ext)   -- nil → base shape mask
  -- 2. Shape the end-burst completion flash to the pill (used by successful casts
  --    AND replayed red for cancels). Reset its tint to white each cast so a real
  --    completion stays gold after a prior cancel tinted it red.
  local burst = cast.EndBurst
  if burst and burst.GlowRing then
    local slot = rec.castBurst or {}; rec.castBurst = slot
    if burst.EndMask and not slot.blizzRemoved then burst.GlowRing:RemoveMaskTexture(burst.EndMask); slot.blizzRemoved = true end
    if slot.mask then burst.GlowRing:RemoveMaskTexture(slot.mask) end
    slot.mask = buildMask(burst, icon, ext, src)
    burst.GlowRing:AddMaskTexture(slot.mask)
    burst.GlowRing:SetVertexColor(1, 1, 1)
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
  AnchorConstruction(f, icon, GROW_RATIO)     -- frame spans the pill construction
  if f.mask then f.tex:RemoveMaskTexture(f.mask) end
  f.mask = buildMask(f, icon, ext, src)       -- fresh aspect pill mask, clips the tint to the shape
  f.tex:AddMaskTexture(f.mask)
  local col = (GB.db and GB.db.castFillColor) or { 1, 0.85, 0.4 }
  local a = (GB.db and GB.db.castFillAlpha) or 0.55
  f.tex:SetVertexColor(col[1], col[2], col[3], a)
  f.dir = (GB.db and GB.db.castDrainDir) or "up"
  f.cast = cast                                    -- for the cancel → red EndBurst replay
  f.blizzFill = cast.Fill and cast.Fill.CastFill   -- OnUpdate force-suppresses this each frame
  f.interrupt = btn.InterruptDisplay               -- and Blizzard's red square (we replay EndBurst instead)
  f.grace, f.lastP, f.flashed, f.bursting = nil, nil, nil, nil   -- fresh cast (clear prior interrupt state)
  f:Show()                                    -- OnUpdate polls the live cast/channel + hides at the end
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
  local above = ExtensionAbove()
  local extT, extB = (above and ext or 0), (above and 0 or ext)   -- extension split per direction
  -- "Continuous shape" (default) masks the icon + extension as ONE shape — a pill
  -- wrapping both (Jason's mock). Continuous OFF masks the icon to its OWN shape
  -- (icon-only) and leaves the plate a square rectangle → a rounded icon on a
  -- crisp square plate. So the MASKS (icon + border) span the construction only
  -- when continuous; the plate positioning always uses the real extension.
  local continuous = not (style.construction and style.construction.continuous == false)
  local maskExt = continuous and ext or 0
  local mExtT, mExtB = (above and maskExt or 0), (above and 0 or maskExt)
  -- The aspect mask comes from the (masked) construction's aspect; a fresh mask is
  -- built only when the plan changes (source swaps never re-render — §2), else a
  -- plain re-anchor re-clips live. Fold `continuous` into the key so toggling it
  -- rebuilds even when the aspect happens to match.
  local maskSrc, maskKey = maskPlan(icon, maskExt)
  maskKey = maskKey .. (continuous and "|c1" or "|c0")
  if rec.mask and rec.maskKey == maskKey then
    AnchorConstructionMask(rec.mask, icon, maskExt)
  else
    if rec.mask then icon:RemoveMaskTexture(rec.mask) end
    rec.mask = buildMask(btn, icon, maskExt, maskSrc)
    icon:AddMaskTexture(rec.mask)
    rec.maskKey = maskKey
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
    local col = bd.color or { 0, 0, 0 }
    local _, isub = icon:GetDrawLayer()
    b.tex:SetDrawLayer("BACKGROUND", math.max(-8, (isub or 0) - 1))   -- just behind the icon
    b.tex:SetVertexColor(col[1], col[2], col[3], bd.alpha or 1)
    b.tex:ClearAllPoints()
    b.tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -t, t + mExtT)      -- frames the masked region
    b.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", t, -(mExtB + t))
    -- Same shape source as the icon; rebuild only on a shape/plan change (source
    -- swaps never re-render, §2) — thickness/size are a live re-anchor.
    if b.mask and b.maskKey == maskKey then
      AnchorBorderMask(b.mask, icon, maskExt, t)
    else
      if b.mask then b.tex:RemoveMaskTexture(b.mask) end
      b.mask = btn:CreateMaskTexture()
      b.mask:SetTexture(maskSrc or GB:GetShape().mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      AnchorBorderMask(b.mask, icon, maskExt, t)
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
    end
    -- Continuous: the plate shares the icon's mask so it joins the pill (rebuild
    -- on plan change, else re-anchor). NOT continuous: no mask → a plain square
    -- rectangle (the crisp plate that squares off the junction).
    if not continuous then
      if plate.mask then plate.tex:RemoveMaskTexture(plate.mask); plate.mask = nil; plate.maskKey = nil end
    elseif plate.mask and plate.maskKey == maskKey then
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
  local used = 0
  for i, layer in ipairs(style.layers or {}) do
    if layer.enabled ~= false and layer.kind == "gradient" then
      local c = layer.color or { 1, 1, 1 }
      local fromA, toA = layer.fromAlpha or 1, layer.toAlpha or 0
      if layer.zone == "extension" and ext > 0 then
        -- Mock-matched (QA 2026-07-18): the extension is FULL opacity to the
        -- icon's edge; the fade lives INSIDE the icon. Mirrored for an ABOVE
        -- extension (solid above the top edge, fade running down into the icon).
        local iconEdge = above and "TOP" or "BOTTOM"
        local outward = above and ext or -ext              -- solid extends away from the icon
        local fromC = CreateColor(c[1], c[2], c[3], fromA)
        local toC = CreateColor(c[1], c[2], c[3], toA)
        used = used + 1
        local solid = getPlate(used)
        solid.tex:SetPoint(iconEdge .. "LEFT", icon, iconEdge .. "LEFT", 0, outward)
        solid.tex:SetPoint(iconEdge .. "RIGHT", icon, iconEdge .. "RIGHT", 0, outward)
        solid.tex:SetHeight(ext)
        solid.tex:SetGradient("VERTICAL", fromC, fromC)
        solid.tex:Show()
        used = used + 1
        local fade = getPlate(used)
        fade.tex:SetPoint(iconEdge .. "LEFT", icon, iconEdge .. "LEFT", 0, 0)
        fade.tex:SetPoint(iconEdge .. "RIGHT", icon, iconEdge .. "RIGHT", 0, 0)
        fade.tex:SetHeight(icon:GetHeight() * (layer.bleedPct or 0.4))
        -- VERTICAL gradient min = bottom, max = top → full colour sits at the
        -- icon edge (bottom for a below plate, top for an above plate).
        if above then fade.tex:SetGradient("VERTICAL", toC, fromC)
        else fade.tex:SetGradient("VERTICAL", fromC, toC) end
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
  glow:SetTexture(shapeArt(icon).ring)   -- construction-aspect ring
  AnchorConstruction(glow, icon, (RING_FIT - 1) / 2)
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
  local os = (GB.db and GB.db.sweepOvershoot or 0.75)
  for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
    if cd then AnchorConstruction(cd, icon, GROW_RATIO, os) end
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
    applyShapeArt(btn, icon)   -- swap overlay art to the new aspect (ring/swipe)
    local function fit(tex) if tex then AnchorConstruction(tex, icon, (RING_FIT - 1) / 2) end end
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
    local ring = shapeArt(icon).ring
    -- Ring rim sits inset from the shape edge → oversize by RING_FIT (not just
    -- the mask's GROW_RATIO) so the rim reaches the icon/pill edge.
    local function fit(tex) AnchorConstruction(tex, icon, (RING_FIT - 1) / 2) end
    if btn.SetHighlightTexture and btn.GetHighlightTexture then
      btn:SetHighlightTexture(ring, "ADD")
      local hl = btn:GetHighlightTexture()
      hl:SetVertexColor(unpack(stateColor("highlight"))); hl:SetAlpha(stateIntensity())
      fit(hl)
    end
    if btn.SetCheckedTexture and btn.GetCheckedTexture then
      btn:SetCheckedTexture(ring)
      local ct = btn:GetCheckedTexture()
      ct:SetBlendMode("ADD")
      ct:SetVertexColor(unpack(stateColor("checked"))); ct:SetAlpha(stateIntensity())
      fit(ct)
    end
    if btn.Flash then
      btn.Flash:SetTexture(ring)
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
    local swipe = shapeArt(icon).swipe
    for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
      if cd and cd.SetSwipeTexture then
        cd:SetSwipeTexture(swipe)
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
  -- Cast/channel visuals (suppress Blizzard's square fill + draw our own pill
  -- fill, shape the end burst, replace the inner-glow art) are all applied in the
  -- PlaySpellCastAnim hook — the Fill frames are live at cast time, and it keeps
  -- mask/fill work off the size-slider hot path. See styleCast / StyleCastInnerGlow.
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
