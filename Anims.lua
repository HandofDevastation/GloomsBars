-- Anims.lua — Gloom's Bars per-trigger ANIMATION SYSTEM (GB.Anims).
--
-- Each button "trigger" (the glow sources in Glows.lua: proc/cast/channel/hover/
-- selected/flash/assist) can enable one or more ANIMATIONS, each a self-contained
-- plug-in MODULE with its own params + renderer. When a trigger becomes the active
-- glow on a button (Glows:Refresh -> Anims:Reconcile), its enabled animations run with
-- that trigger's params; when it clears, they stop. Adding an animation = register a
-- new module here; the data model + Config UI pick it up generically from its schema.
--
-- Module contract:
--   { id, label, defaults = {..}, params = { {key, kind, label, ...}, .. },
--     Start(host, icon, key, p), Stop(host) }
-- Start/Stop are keyed by HOST frame (a button, OR the Config preview frame), so the
-- same module renders on the bars AND in the editor preview. Start is idempotent —
-- called repeatedly to (re)configure live; it reuses the host's instance.

local GB = _G.GloomsBars

local Anims = { modules = {}, order = {} }
GB.Anims = Anims

function Anims:Register(mod)
  if self.modules[mod.id] then return end
  self.modules[mod.id] = mod
  self.order[#self.order + 1] = mod.id
end
function Anims:Get(id) return self.modules[id] end
function Anims:Each(fn) for _, id in ipairs(self.order) do fn(self.modules[id]) end end

local function copyval(v) if type(v) == "table" then return { v[1], v[2], v[3], v[4] } else return v end end

-- A trigger's saved params for animation `id`, merged over the module defaults so the
-- engine + UI always see a full set. nil if the module is unknown.
function Anims:Params(trigger, id)
  local mod = self.modules[id]; if not mod then return nil end
  local p = {}
  for k, v in pairs(mod.defaults) do p[k] = copyval(v) end
  local saved = trigger and trigger.anims and trigger.anims[id]
  if saved then for k, v in pairs(saved) do p[k] = v end end
  return p
end
function Anims:Enabled(trigger, id)
  local saved = trigger and trigger.anims and trigger.anims[id]
  return saved and saved.enabled and true or false
end

-- Reconcile a BUTTON's animations to its winning glow trigger (called from
-- Glows:Refresh with the winning trigger key + record, or nil). Skips when the winner
-- is unchanged (Refresh fires often); Anims:Invalidate forces a re-run after edits.
local activeState = {}   -- [btn] = { key = <triggerKey>, [animId] = true }
function Anims:Reconcile(btn, triggerKey, trigger)
  local st = activeState[btn]
  if not st then st = {}; activeState[btn] = st end
  if st.key == triggerKey then return end
  st.key = triggerKey
  local icon = btn.icon or btn.Icon
  local key = GB.db and GB.db.handShape
  for _, id in ipairs(self.order) do
    local mod = self.modules[id]
    local want = triggerKey and trigger and self:Enabled(trigger, id) and icon and key
    if want then mod:Start(btn, icon, key, self:Params(trigger, id)); st[id] = true
    elseif st[id] then mod:Stop(btn); st[id] = nil end
  end
end

-- After a Config edit to `triggerKey`'s params, drop the cached winner on bars showing
-- it so the next Refresh re-reconciles with the new values (live bars, no combat wait).
function Anims:Invalidate(triggerKey)
  for _, st in pairs(activeState) do
    if st.key == triggerKey then st.key = nil end
  end
  if GB.Glows and GB.Glows.RefreshTrigger then GB.Glows:RefreshTrigger(triggerKey) end
end

-- Config PREVIEW: run the selected trigger's enabled animations on the preview host
-- (previewFrame/previewIcon), stop the rest. Same modules as the bars — host-keyed.
function Anims:PreviewReconcile(host, icon, key, trigger)
  for _, id in ipairs(self.order) do
    local mod = self.modules[id]
    if trigger and icon and key and self:Enabled(trigger, id) then
      mod:Start(host, icon, key, self:Params(trigger, id))
    else
      mod:Stop(host)
    end
  end
end

-- ===========================================================================
-- MODULE: SHINE CHASE — N glowing comets orbiting the shape's rim. The comet
-- (Media/art/shine.png) is spun over the icon and clipped to the shape's rim mask
-- (<key>-rim.png); N comets are phase-spaced 360/N apart and driven by one OnUpdate.
-- ===========================================================================
local SHINE_TEX = GB.MEDIA .. "art\\shine.png"
local shineInst = {}    -- [host] = { frame, mask, texs, masked, n, w, dir, phase }
local shineActive = {}  -- set of running instances

local shineDriver = CreateFrame("Frame"); shineDriver:Hide()
shineDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(shineActive) do
    inst.phase = (inst.phase + dt * inst.w) % (2 * math.pi)   -- inst.w is SIGNED (spin carries direction)
    local step = (2 * math.pi) / inst.n
    for i = 1, inst.n do
      if inst.texs[i] then inst.texs[i]:SetRotation(inst.phase + (i - 1) * step) end
    end
  end
end)

-- spin is a single SIGNED velocity in [-1,1]: sign = direction (CW/CCW), magnitude =
-- speed, 0 = still. |spin| = 1 is the fastest (SHINE_MIN_REV seconds/revolution).
local SHINE_MIN_REV = 0.8
local Shine = {
  id = "shine",
  label = "Comet Chase",
  defaults = { color = { 1, 0.96, 0.7 }, count = 1, spin = 0.5 },
  params = {
    { key = "color", kind = "color",   label = "Colour" },
    { key = "count", kind = "range",   label = "Comets", min = 1, max = 4, step = 1, fmt = "int" },
    { key = "spin",  kind = "bispeed", label = "Spin", minRev = SHINE_MIN_REV },
  },
}

function Shine:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = shineInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    inst = { frame = frame, mask = frame:CreateMaskTexture(), texs = {}, masked = {}, phase = 0 }
    shineInst[host] = inst
  end
  local n = math.max(1, math.min(4, math.floor(p.count or 1)))
  local spin = p.spin; if spin == nil then spin = 0.5 end
  -- WoW rotation is CCW-positive; negate so positive spin = CLOCKWISE (matches the UI's CW side).
  local w = -spin * ((2 * math.pi) / SHINE_MIN_REV)   -- signed angular velocity (rad/sec)
  local cw = w < 0                                     -- mirror the comet for CW motion so the tail trails
  local color = p.color or { 1, 1, 1 }
  local s = 1.6 * math.max(icon:GetWidth(), icon:GetHeight())   -- oversize so the spin covers the rim
  if GB.Skin and GB.Skin.AnchorHandGrown then GB.Skin:AnchorHandGrown(inst.mask, icon, 0) end
  inst.mask:SetTexture(GB:HandAsset(key, "rim"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  for i = 1, n do
    local tex = inst.texs[i]
    if not tex then
      tex = inst.frame:CreateTexture(nil, "OVERLAY")
      tex:SetTexture(SHINE_TEX); tex:SetBlendMode("ADD")
      tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
      inst.texs[i] = tex
    end
    tex:ClearAllPoints(); tex:SetSize(s, s); tex:SetPoint("CENTER", icon, "CENTER")
    tex:SetVertexColor(color[1], color[2], color[3])
    if cw then tex:SetTexCoord(1, 0, 0, 1) else tex:SetTexCoord(0, 1, 0, 1) end   -- tail trails per motion
    tex:Show()
  end
  for i = n + 1, #inst.texs do inst.texs[i]:Hide() end
  inst.n = n
  inst.w = w
  inst.frame:Show()
  shineActive[inst] = true; shineDriver:Show()
  C_Timer.After(0, function()   -- mask after first render (AddMaskTexture fails on a never-rendered texture — §2)
    if inst.frame:IsShown() then
      for i = 1, inst.n do
        local tex = inst.texs[i]
        if tex and tex:IsShown() and not inst.masked[i] then tex:AddMaskTexture(inst.mask); inst.masked[i] = true end
      end
    end
  end)
end

function Shine:Stop(host)
  local inst = shineInst[host]
  if inst then
    inst.frame:Hide()
    shineActive[inst] = nil
    if not next(shineActive) then shineDriver:Hide() end
  end
end

Anims:Register(Shine)
