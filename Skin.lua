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

local function Suppress(btn)
  if btn.SlotBackground then btn.SlotBackground:Hide() end
  if btn.SlotArt then btn.SlotArt:Hide() end
  if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
  if btn.PushedTexture then btn.PushedTexture:SetAlpha(0) end
end

-- Make the round sweep circle coincide with the icon circle: anchor the
-- cooldown widgets to the icon oversized by the art-padding ratio (same math
-- as the icon mask). Blizzard insets the cooldown inside the icon (+1.7/-1
-- points, small-button UpdateButtonArt re-anchors it) — which made the v0
-- sweep visibly smaller than the icon.
local function AlignCooldowns(btn)
  local icon = btn.icon or btn.Icon
  if not icon then return end
  local grow = icon:GetWidth() * GROW_RATIO
  for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
    if cd then
      cd:ClearAllPoints()
      cd:SetPoint("TOPLEFT", icon, "TOPLEFT", -grow, grow)
      cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", grow, -grow)
    end
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
    rec.mask:SetTexture(GB.MASK.circle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
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
  end
  if btn.IconMask then
    icon:RemoveMaskTexture(btn.IconMask)
    rec.iconMaskRemoved = true
  end
  icon:SetTexCoord(ZOOM, 1 - ZOOM, ZOOM, 1 - ZOOM)
  icon:AddMaskTexture(rec.mask)
  -- Shaped cooldown sweep: the swipe respects its texture's alpha, and
  -- Blizzard's cooldown path never re-sets swipe textures (only SetCooldown/
  -- Clear + SetSwipeColor around cast anims — API-NOTES §3), so one-time
  -- setup persists. chargeCooldown is edge-only by default — left untouched.
  if not rec.cooldownStyled then
    for _, cd in ipairs({ btn.cooldown, btn.lossOfControlCooldown }) do
      if cd and cd.SetSwipeTexture then
        cd:SetSwipeTexture(GB.MASK.circleSwipe)
        -- The rotating edge line + finish bling are drawn to the SQUARE frame
        -- bounds and poke past a round sweep — off for the clean look.
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetDrawBling then cd:SetDrawBling(false) end
      end
    end
    rec.cooldownStyled = true
  end
  AlignCooldowns(btn)
  Suppress(btn)
  rec.active = true
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
  GB.msg(("skin ON — %d buttons styled (round icons, slot art suppressed). Persists across /reload; /gb skin to turn off."):format(count))
end

function Skin:Disable()
  self.enabled = false
  if GB.db then GB.db.skinEnabled = false end
  GB:ForEachButton(function(btn) RestoreButton(btn) end)
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
