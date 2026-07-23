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
  -- In plate mode the animation spans the full 2:1 plate (ConstructRef), not the half icon.
  local icon = (GB.Skin and GB.Skin.ConstructRef and GB.Skin:ConstructRef(btn)) or btn.icon or btn.Icon
  local key = (GB.Skin and GB.Skin.ShapeKeyFor and GB.Skin:ShapeKeyFor(btn)) or (GB.db and GB.db.handShape)
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
-- All animation modules attach their clip mask with a DEFERRED C_Timer.After(0) because
-- AddMaskTexture silently fails on a never-rendered texture (§2). To avoid the graphic
-- flashing UNMASKED for that one render frame (visible on the FIRST trigger of each host),
-- prime the texture near-invisible (PRIME_ALPHA — non-zero so it still definitely renders),
-- then attach the mask AND reveal together in the deferred callback.
local PRIME_ALPHA = 0.02

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
    { key = "count", kind = "range",   label = "Comets", min = 1, max = 8, step = 1, fmt = "int" },
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
  local n = math.max(1, math.min(8, math.floor(p.count or 1)))
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
    tex:Show(); tex:SetAlpha(PRIME_ALPHA)   -- prime near-invisible; revealed once the mask binds
  end
  for i = n + 1, #inst.texs do inst.texs[i]:Hide() end
  inst.n = n
  inst.w = w
  inst.frame:Show()
  shineActive[inst] = true; shineDriver:Show()
  C_Timer.After(0, function()   -- attach the mask + REVEAL after the first render (§2 defers the mask)
    if not inst.frame:IsShown() then return end
    for i = 1, inst.n do
      local tex = inst.texs[i]
      if tex and tex:IsShown() then
        if not inst.masked[i] then tex:AddMaskTexture(inst.mask); inst.masked[i] = true end
        tex:SetAlpha(1)
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

-- ===========================================================================
-- MODULE: MARCHING LINES — N dashes marching around the shape's rim. The dash
-- (Media/art/march.png) is a symmetric angular wedge spun over the icon and clipped to
-- the shape's THIN LINE mask (<key>-line.png — its OWN tight band, NOT the comet's wide
-- soft <key>-rim; the mask sets the line's radial thickness, so a thin band reads as a
-- crisp dash and the comet band read as a fat blob). N dashes are phase-spaced 360/N
-- apart and driven by one OnUpdate, so they read as an evenly-spaced dashed track
-- marching around any silhouette. Same mechanic as Comet Chase, minus the tail/mirroring
-- — the dash is symmetric, so it's direction-agnostic.
-- ===========================================================================
local MARCH_TEX = GB.MEDIA .. "art\\march.png"
local marchInst = {}    -- [host] = { frame, mask, texs, masked, n, w, phase }
local marchActive = {}  -- set of running instances

local marchDriver = CreateFrame("Frame"); marchDriver:Hide()
marchDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(marchActive) do
    inst.phase = (inst.phase + dt * inst.w) % (2 * math.pi)   -- inst.w is SIGNED (spin carries direction)
    local step = (2 * math.pi) / inst.n
    for i = 1, inst.n do
      if inst.texs[i] then inst.texs[i]:SetRotation(inst.phase + (i - 1) * step) end
    end
  end
end)

-- spin is a single SIGNED velocity in [-1,1] (sign = direction, magnitude = speed, 0 =
-- still); |spin| = 1 is MARCH_MIN_REV sec/revolution. Slower than the comet: a dashed
-- ring reads best marching gently, and with more dashes each covers less arc per second.
local MARCH_MIN_REV = 2.2
local March = {
  id = "march",
  label = "Marching Lines",
  defaults = { color = { 0.8, 0.92, 1 }, count = 8, spin = 0.35 },
  params = {
    { key = "color", kind = "color",   label = "Colour" },
    { key = "count", kind = "range",   label = "Dashes", min = 2, max = 12, step = 1, fmt = "int" },
    { key = "spin",  kind = "bispeed", label = "March", minRev = MARCH_MIN_REV },
  },
}

function March:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = marchInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    inst = { frame = frame, mask = frame:CreateMaskTexture(), texs = {}, masked = {}, phase = 0 }
    marchInst[host] = inst
  end
  local n = math.max(2, math.min(12, math.floor(p.count or 8)))
  local spin = p.spin; if spin == nil then spin = 0.35 end
  -- WoW rotation is CCW-positive; negate so positive spin = CLOCKWISE (matches the UI's CW side).
  local w = -spin * ((2 * math.pi) / MARCH_MIN_REV)   -- signed angular velocity (rad/sec)
  local color = p.color or { 1, 1, 1 }
  local s = 1.6 * math.max(icon:GetWidth(), icon:GetHeight())   -- oversize so the spin covers the rim
  if GB.Skin and GB.Skin.AnchorHandGrown then GB.Skin:AnchorHandGrown(inst.mask, icon, 0) end
  inst.mask:SetTexture(GB:HandAsset(key, "line"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  for i = 1, n do
    local tex = inst.texs[i]
    if not tex then
      tex = inst.frame:CreateTexture(nil, "OVERLAY")
      -- BLEND, not ADD: a marching line should be its ACTUAL colour. ADD only adds light
      -- (washes every tint toward white, can't be deeply saturated, vanishes over a bright
      -- icon); BLEND paints the true tint over the background. Glows want ADD; a line wants BLEND.
      tex:SetTexture(MARCH_TEX); tex:SetBlendMode("BLEND")
      tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
      inst.texs[i] = tex
    end
    tex:ClearAllPoints(); tex:SetSize(s, s); tex:SetPoint("CENTER", icon, "CENTER")
    tex:SetVertexColor(color[1], color[2], color[3])
    tex:SetTexCoord(0, 1, 0, 1)   -- symmetric dash: no tail, so no direction-mirroring
    tex:Show(); tex:SetAlpha(PRIME_ALPHA)   -- prime near-invisible; revealed once the mask binds
  end
  for i = n + 1, #inst.texs do inst.texs[i]:Hide() end
  inst.n = n
  inst.w = w
  inst.frame:Show()
  marchActive[inst] = true; marchDriver:Show()
  C_Timer.After(0, function()   -- attach the mask + REVEAL after the first render (§2 defers the mask)
    if not inst.frame:IsShown() then return end
    for i = 1, inst.n do
      local tex = inst.texs[i]
      if tex and tex:IsShown() then
        if not inst.masked[i] then tex:AddMaskTexture(inst.mask); inst.masked[i] = true end
        tex:SetAlpha(1)
      end
    end
  end)
end

function March:Stop(host)
  local inst = marchInst[host]
  if inst then
    inst.frame:Hide()
    marchActive[inst] = nil
    if not next(marchActive) then marchDriver:Hide() end
  end
end

Anims:Register(March)

-- ===========================================================================
-- MODULE: SHEEN SWEEP — a bright diagonal bar that slides across the icon FACE (not the
-- rim). Unlike the rim effects, the bar (Media/art/sheen.png, a plain vertical stripe)
-- is clipped by the icon's OWN silhouette (<key>-base.png), tilted (SetRotation), scaled
-- for thickness (SetSize width), and TRANSLATED under the fixed base mask (SetPoint
-- offset) — so a gleam sweeps the whole face of any shape, with a pause between passes.
-- Style toggle: Glow = ADD (a light gleam) · Solid = BLEND (a true-colour bar).
-- ===========================================================================
local SHEEN_TEX = GB.MEDIA .. "art\\sheen.png"
local sheenInst = {}    -- [host] = { frame, tex, mask, masked, icon, dir, travel, period, t }
local sheenActive = {}  -- set of running instances

local SHEEN_TILT = math.rad(20)   -- baked-in lean of the sweep bar
local SHEEN_SCALE = 1.8            -- texture size vs the icon's long side (oversize to cover when tilted)
local SHEEN_MIN_PERIOD = 1.0       -- full cycle (sweep + pause) in seconds at |sweep| = 1
local SHEEN_SWEEP_FRAC = 0.42      -- portion of the cycle that is the actual sweep; the rest is a pause

local sheenDriver = CreateFrame("Frame"); sheenDriver:Hide()
sheenDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(sheenActive) do
    if not inst.ready then
      -- priming: leave the tiny prime alpha untouched so the texture renders for the
      -- mask attach (§2); the C_Timer flips ready once the mask is bound.
    elseif not inst.period then
      inst.tex:SetAlpha(0)                       -- ~zero speed = no sweep
    else
      inst.t = inst.t + dt
      local ph = (inst.t % inst.period) / inst.period
      if ph < SHEEN_SWEEP_FRAC then
        local p = ph / SHEEN_SWEEP_FRAC          -- 0..1 across the sweep
        inst.tex:SetPoint("CENTER", inst.icon, "CENTER", inst.dir * (-1 + 2 * p) * inst.travel, 0)
        inst.tex:SetAlpha(1)
      else
        inst.tex:SetAlpha(0)                     -- pause between gleams
      end
    end
  end
end)

-- sweep is a SIGNED velocity in [-1,1]: sign = direction (L/R), magnitude = speed,
-- 0 = no sweep; |sweep| = 1 is SHEEN_MIN_PERIOD sec/cycle.
local Sheen = {
  id = "sheen",
  label = "Sheen Sweep",
  defaults = { color = { 1, 1, 0.9 }, width = 1.0, sweep = 0.5, blend = "add" },
  params = {
    { key = "color", kind = "color",   label = "Colour" },
    { key = "width", kind = "range",   label = "Width", min = 0.4, max = 2.0, step = 0.1 },
    { key = "sweep", kind = "bispeed", label = "Sweep", minRev = SHEEN_MIN_PERIOD, neg = "L", pos = "R" },
    { key = "blend", kind = "choice",  label = "Style", choices = { { "add", "Glow" }, { "blend", "Solid" } } },
  },
}

function Sheen:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = sheenInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(SHEEN_TEX)
    tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
    tex:SetRotation(SHEEN_TILT)
    inst = { frame = frame, tex = tex, mask = frame:CreateMaskTexture(), masked = false, t = 0 }
    sheenInst[host] = inst
  end
  local dim = math.max(icon:GetWidth(), icon:GetHeight())
  local width = p.width or 1.0
  local speed = p.sweep; if speed == nil then speed = 0.5 end
  local aspd = math.abs(speed)
  inst.icon = icon
  inst.dir = (speed >= 0) and 1 or -1
  inst.travel = 0.85 * dim
  inst.period = (aspd < 0.04) and nil or (SHEEN_MIN_PERIOD / aspd)
  inst.t = 0   -- restart the cycle on every (re)trigger so a hover sweeps IMMEDIATELY,
               -- not after the leftover pause from the last time it ran (the felt "lag")
  local color = p.color or { 1, 1, 1 }
  inst.tex:SetSize(SHEEN_SCALE * dim * width, SHEEN_SCALE * dim)     -- width scales thickness only
  inst.tex:SetVertexColor(color[1], color[2], color[3])
  -- Glow = ADD (a light gleam; deep colours wash — that's physics). Solid = BLEND (true-colour bar).
  inst.tex:SetBlendMode(p.blend == "blend" and "BLEND" or "ADD")
  if GB.Skin and GB.Skin.AnchorHandGrown then GB.Skin:AnchorHandGrown(inst.mask, icon, 0) end
  inst.mask:SetTexture(GB:HandAsset(key, "base"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  -- Prime near-invisible OFF-icon so the mask can attach (AddMaskTexture fails on a
  -- never-rendered texture — §2) WITHOUT a visible flash; the driver holds until `ready`,
  -- then sweeps it under the fixed base mask.
  inst.ready = false
  inst.tex:ClearAllPoints(); inst.tex:SetPoint("CENTER", icon, "CENTER", 3 * inst.travel, 0)
  inst.tex:SetAlpha(PRIME_ALPHA); inst.tex:Show()
  inst.frame:Show()
  sheenActive[inst] = true; sheenDriver:Show()
  C_Timer.After(0, function()   -- attach the mask, then let the driver reveal (kills the 1st-trigger flash)
    if inst.frame:IsShown() and inst.tex:IsShown() then
      if not inst.masked then inst.tex:AddMaskTexture(inst.mask); inst.masked = true end
      inst.ready = true
    end
  end)
end

function Sheen:Stop(host)
  local inst = sheenInst[host]
  if inst then
    inst.frame:Hide()
    sheenActive[inst] = nil
    if not next(sheenActive) then sheenDriver:Hide() end
  end
end

Anims:Register(Sheen)

-- ===========================================================================
-- MODULE: SPARKLES — N little twinkles scattered at RANDOM spots on the icon face, each
-- fading in -> peak -> out then respawning elsewhere. Unlike the looping modules, every
-- sparkle runs its own randomised lifecycle (position, size, rotation, duration), so the
-- effect reads as organic glitter rather than a mechanical path. One shared star
-- (Media/art/sparkle.png) clipped to the icon's own silhouette (<key>-base.png).
-- ===========================================================================
local SPARKLE_TEX = GB.MEDIA .. "art\\sparkle.png"
local sparkleInst = {}    -- [host] = { frame, mask, sparks = { {tex, masked, t, life}, .. }, n, icon, iconW, iconH, base, rate }
local sparkleActive = {}  -- set of running instances

local SPARK_SIZE_DEFAULT = 0.40  -- default sparkle size (fraction of the icon's long side); live via the Size param
local SPARK_SPREAD = 0.40  -- placement box half-extent as a fraction of the icon W/H
local SPARK_LIFE = 0.9     -- base lifecycle (fade in+out) in seconds, before the rate scale

local function frand(a, b) return a + math.random() * (b - a) end

-- Re-roll a sparkle: fresh random spot inside the icon box, size, rotation, duration.
local function sparkleRespawn(inst, sp)
  sp.t = 0
  sp.life = SPARK_LIFE * frand(0.7, 1.3)
  local sc = inst.base * frand(0.7, 1.2)
  sp.tex:SetSize(sc, sc)
  sp.tex:SetRotation(frand(0, math.pi / 2))   -- 4-fold star → a quarter-turn covers every look
  sp.tex:ClearAllPoints()
  sp.tex:SetPoint("CENTER", inst.icon, "CENTER",
    frand(-SPARK_SPREAD, SPARK_SPREAD) * inst.iconW,
    frand(-SPARK_SPREAD, SPARK_SPREAD) * inst.iconH)
end

local sparkleDriver = CreateFrame("Frame"); sparkleDriver:Hide()
sparkleDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(sparkleActive) do
    local rate = inst.rate or 1
    for i = 1, inst.n do
      local sp = inst.sparks[i]
      if sp and sp.masked then    -- animate only once masked (per-sparkle prime → reveal, no flash)
        sp.t = sp.t + dt * rate
        if sp.t >= sp.life then sparkleRespawn(inst, sp) end
        sp.tex:SetAlpha(math.sin(math.pi * (sp.t / sp.life)))   -- 0 → peak → 0 twinkle envelope
      end
    end
  end
end)

local Sparkle = {
  id = "sparkle",
  label = "Sparkles",
  defaults = { color = { 1, 1, 0.95 }, count = 5, size = SPARK_SIZE_DEFAULT, twinkle = 1.0, blend = "add" },
  params = {
    { key = "color",   kind = "color",  label = "Colour" },
    { key = "count",   kind = "range",  label = "Count", min = 1, max = 10, step = 1, fmt = "int" },
    { key = "size",    kind = "range",  label = "Size", min = 0.15, max = 0.7, step = 0.05 },
    { key = "twinkle", kind = "range",  label = "Twinkle", min = 0.3, max = 2.5, step = 0.1 },
    { key = "blend",   kind = "choice", label = "Style", choices = { { "add", "Glow" }, { "blend", "Solid" } } },
  },
}

function Sparkle:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = sparkleInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    inst = { frame = frame, mask = frame:CreateMaskTexture(), sparks = {} }
    sparkleInst[host] = inst
  end
  local n = math.max(1, math.min(10, math.floor(p.count or 5)))
  inst.icon = icon
  inst.iconW = icon:GetWidth(); inst.iconH = icon:GetHeight()
  inst.base = (p.size or SPARK_SIZE_DEFAULT) * math.max(inst.iconW, inst.iconH)
  inst.rate = p.twinkle or 1.0
  local color = p.color or { 1, 1, 1 }
  local blend = (p.blend == "blend") and "BLEND" or "ADD"   -- Glow = ADD twinkle; Solid = BLEND true-colour star
  if GB.Skin and GB.Skin.AnchorHandGrown then GB.Skin:AnchorHandGrown(inst.mask, icon, 0) end
  inst.mask:SetTexture(GB:HandAsset(key, "base"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  for i = 1, n do
    local sp = inst.sparks[i]
    if not sp then
      local tex = inst.frame:CreateTexture(nil, "OVERLAY")
      tex:SetTexture(SPARKLE_TEX); tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
      sp = { tex = tex, masked = false }
      inst.sparks[i] = sp
    end
    sp.tex:SetBlendMode(blend)
    sp.tex:SetVertexColor(color[1], color[2], color[3])
    sparkleRespawn(inst, sp)
    sp.t = math.random() * sp.life   -- stagger initial ages so they don't twinkle in unison
    sp.tex:Show(); sp.tex:SetAlpha(PRIME_ALPHA)   -- prime near-invisible; masked & revealed by the driver
  end
  for i = n + 1, #inst.sparks do inst.sparks[i].tex:Hide() end
  inst.n = n
  inst.frame:Show()
  sparkleActive[inst] = true; sparkleDriver:Show()
  C_Timer.After(0, function()   -- attach each sparkle's mask after its first render (§2)
    if not inst.frame:IsShown() then return end
    for i = 1, inst.n do
      local sp = inst.sparks[i]
      if sp and sp.tex:IsShown() and not sp.masked then sp.tex:AddMaskTexture(inst.mask); sp.masked = true end
    end
  end)
end

function Sparkle:Stop(host)
  local inst = sparkleInst[host]
  if inst then
    inst.frame:Hide()
    sparkleActive[inst] = nil
    if not next(sparkleActive) then sparkleDriver:Hide() end
  end
end

Anims:Register(Sparkle)

-- ===========================================================================
-- MODULE: BREATHE — a shape-matched outline that rhythmically scales up/down and pulses
-- brightness, so the button "breathes". The only SCALE-based module. It draws the shape's
-- soft outline (<key>-rim, tinted — shown DIRECTLY as art, not as a clip mask, so nothing
-- to attach and no first-trigger flash) and oscillates its SIZE about the icon centre.
-- hgAnchor's grow-0 span == icon + min(w,h) per axis, centred — reproduced here via a
-- centred SetSize so scaling stays shape-aligned. Distinct from the glow's alpha-only
-- pulse: here the outline visibly grows and shrinks.
-- ===========================================================================
local breatheInst = {}    -- [host] = { frame, tex, icon, baseW, baseH, speed, depth, peak, phase }
local breatheActive = {}

local BREATHE_RATE = 9.0   -- phase advance / sec at speed 1 → ~0.7s/breath; max slider ≈ 0.23s (fast throb)
local BREATHE_LOW = 0.55   -- alpha floor as a fraction of peak (dims on the out-breath, never vanishes)

local breatheDriver = CreateFrame("Frame"); breatheDriver:Hide()
breatheDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(breatheActive) do
    inst.phase = (inst.phase + dt * inst.speed * BREATHE_RATE) % (2 * math.pi)
    local b = 0.5 - 0.5 * math.cos(inst.phase)          -- smooth 0 → 1 → 0 breath
    local scale = 1 + inst.depth * b
    inst.tex:SetSize(inst.baseW * scale, inst.baseH * scale)   -- centred anchor → scales about the icon
    inst.tex:SetAlpha(inst.peak * (BREATHE_LOW + (1 - BREATHE_LOW) * b))
  end
end)

local Breathe = {
  id = "breathe",
  label = "Breathe",
  defaults = { color = { 1, 0.85, 0.5 }, speed = 1.0, depth = 0.2, blend = "add" },
  params = {
    { key = "color", kind = "color",  label = "Colour" },
    { key = "speed", kind = "range",  label = "Speed", min = 0.3, max = 3.0, step = 0.1 },
    { key = "depth", kind = "range",  label = "Depth", min = 0.05, max = 0.5, step = 0.05 },
    { key = "blend", kind = "choice", label = "Style", choices = { { "add", "Glow" }, { "blend", "Solid" } } },
  },
}

function Breathe:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = breatheInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
    inst = { frame = frame, tex = tex, phase = 0 }
    breatheInst[host] = inst
  end
  local w, h = icon:GetWidth(), icon:GetHeight()
  local m = math.min(w, h)                     -- hgAnchor grow-0 span == icon + min(w,h) each axis
  inst.icon = icon
  inst.baseW, inst.baseH = w + m, h + m
  inst.speed = p.speed or 1.0
  inst.depth = p.depth or 0.2
  inst.peak = 1
  local color = p.color or { 1, 1, 1 }
  inst.tex:SetTexture(GB:HandAsset(key, "rim"))
  inst.tex:SetVertexColor(color[1], color[2], color[3])
  -- Glow = ADD (a breathing halo; deep colours wash — physics). Solid = BLEND (true-colour outline).
  inst.tex:SetBlendMode((p.blend == "blend") and "BLEND" or "ADD")
  inst.tex:ClearAllPoints(); inst.tex:SetPoint("CENTER", icon, "CENTER")
  inst.tex:SetSize(inst.baseW, inst.baseH); inst.tex:SetAlpha(inst.peak)   -- valid until the driver's first tick
  inst.tex:Show()
  inst.frame:Show()
  breatheActive[inst] = true; breatheDriver:Show()
end

function Breathe:Stop(host)
  local inst = breatheInst[host]
  if inst then
    inst.frame:Hide()
    breatheActive[inst] = nil
    if not next(breatheActive) then breatheDriver:Hide() end
  end
end

Anims:Register(Breathe)

-- ===========================================================================
-- MODULE: BURST RING — the shape outline expands outward from the rim while fading to
-- nothing, then restarts: a repeating shockwave. Like Breathe it draws <key>-rim
-- directly (no mask, no first-trigger flash) and scales about the icon centre, but the
-- motion is a one-way expand+fade (not an oscillation). N rings are phase-staggered so
-- they overlap into a ripple field; the cycle restarts on each (re)trigger so a hover
-- emanates immediately.
-- ===========================================================================
local burstInst = {}    -- [host] = { frame, texs, n, icon, baseW, baseH, speed, reach, peak, cyclePhase }
local burstActive = {}

local BURST_BASE = 1.2    -- seconds for one ring to fully expand+fade at speed 1
local BURST_REACH_MAX = 1.2   -- (reach param caps here) — expansion beyond the rim

local burstDriver = CreateFrame("Frame"); burstDriver:Hide()
burstDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(burstActive) do
    inst.cyclePhase = (inst.cyclePhase + dt * inst.speed / BURST_BASE) % 1
    for i = 1, inst.n do
      local tex = inst.texs[i]
      if tex then
        local p = (inst.cyclePhase + (i - 1) / inst.n) % 1   -- staggered progress 0..1
        local scale = 1 + inst.reach * p
        tex:SetSize(inst.baseW * scale, inst.baseH * scale)  -- centred → expands about the icon
        tex:SetAlpha(inst.peak * (1 - p))                    -- fades out as it grows
      end
    end
  end
end)

local Burst = {
  id = "burst",
  label = "Burst Ring",
  defaults = { color = { 1, 0.8, 0.4 }, count = 2, speed = 1.0, reach = 0.7, blend = "add" },
  params = {
    { key = "color", kind = "color",  label = "Colour" },
    { key = "count", kind = "range",  label = "Rings", min = 1, max = 3, step = 1, fmt = "int" },
    { key = "speed", kind = "range",  label = "Speed", min = 0.3, max = 3.0, step = 0.1 },
    { key = "reach", kind = "range",  label = "Reach", min = 0.3, max = BURST_REACH_MAX, step = 0.1 },
    { key = "blend", kind = "choice", label = "Style", choices = { { "add", "Glow" }, { "blend", "Solid" } } },
  },
}

function Burst:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = burstInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    inst = { frame = frame, texs = {}, cyclePhase = 0 }
    burstInst[host] = inst
  end
  local n = math.max(1, math.min(3, math.floor(p.count or 2)))
  local w, h = icon:GetWidth(), icon:GetHeight()
  local m = math.min(w, h)                      -- hgAnchor grow-0 span == icon + min(w,h) each axis
  inst.icon = icon
  inst.baseW, inst.baseH = w + m, h + m
  inst.speed = p.speed or 1.0
  inst.reach = p.reach or 0.7
  inst.peak = 1
  inst.cyclePhase = 0   -- restart the ripple on every (re)trigger so a hover emanates at once
  local color = p.color or { 1, 1, 1 }
  local blend = (p.blend == "blend") and "BLEND" or "ADD"   -- Glow = ADD shockwave; Solid = BLEND true-colour ring
  local rim = GB:HandAsset(key, "rim")
  for i = 1, n do
    local tex = inst.texs[i]
    if not tex then
      tex = inst.frame:CreateTexture(nil, "OVERLAY")
      tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
      inst.texs[i] = tex
    end
    tex:SetTexture(rim); tex:SetBlendMode(blend); tex:SetVertexColor(color[1], color[2], color[3])
    tex:ClearAllPoints(); tex:SetPoint("CENTER", icon, "CENTER")
    tex:SetSize(inst.baseW, inst.baseH); tex:SetAlpha(0)   -- driver sets real size/alpha next tick
    tex:Show()
  end
  for i = n + 1, #inst.texs do inst.texs[i]:Hide() end
  inst.n = n
  inst.frame:Show()
  burstActive[inst] = true; burstDriver:Show()
end

function Burst:Stop(host)
  local inst = burstInst[host]
  if inst then
    inst.frame:Hide()
    burstActive[inst] = nil
    if not next(burstActive) then burstDriver:Hide() end
  end
end

Anims:Register(Burst)

-- ===========================================================================
-- MODULE: RIM FLASH — the shape outline blinks: a sharp bright flash, mostly dim between.
-- Same <key>-rim-drawn-directly base as Breathe/Burst (no mask, no flash), but FIXED size
-- with an ALPHA-only blink (a sharpened cosine → brief bright peak, long dim tail), so it
-- reads as an alert beacon rather than a smooth breath. Restarts on trigger → flashes at once.
-- ===========================================================================
local rimflashInst = {}
local rimflashActive = {}

local FLASH_RATE = 6.3     -- phase advance / sec at speed 1 → ~1 flash/sec
local FLASH_SHARP = 3       -- waveform power: higher = briefer bright peak, longer dim gap
local FLASH_LOW = 0.06      -- alpha floor between flashes (a faint resting outline, not fully gone)

local rimflashDriver = CreateFrame("Frame"); rimflashDriver:Hide()
rimflashDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(rimflashActive) do
    inst.phase = (inst.phase + dt * inst.speed * FLASH_RATE) % (2 * math.pi)
    local f = (0.5 + 0.5 * math.cos(inst.phase)) ^ FLASH_SHARP   -- sharp bright peak, mostly dim
    inst.tex:SetAlpha(inst.peak * (FLASH_LOW + (1 - FLASH_LOW) * f))
  end
end)

local RimFlash = {
  id = "rimflash",
  label = "Rim Flash",
  defaults = { color = { 1, 0.45, 0.3 }, speed = 1.0, blend = "add" },
  params = {
    { key = "color", kind = "color",  label = "Colour" },
    { key = "speed", kind = "range",  label = "Speed", min = 0.3, max = 3.0, step = 0.1 },
    { key = "blend", kind = "choice", label = "Style", choices = { { "add", "Glow" }, { "blend", "Solid" } } },
  },
}

function RimFlash:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = rimflashInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
    inst = { frame = frame, tex = tex, phase = 0 }
    rimflashInst[host] = inst
  end
  local w, h = icon:GetWidth(), icon:GetHeight()
  local m = math.min(w, h)                     -- hgAnchor grow-0 span == icon + min(w,h) each axis
  inst.speed = p.speed or 1.0
  inst.peak = 1
  inst.phase = 0   -- flash immediately on (re)trigger
  local color = p.color or { 1, 1, 1 }
  inst.tex:SetTexture(GB:HandAsset(key, "rim"))
  inst.tex:SetVertexColor(color[1], color[2], color[3])
  -- Glow = ADD (a bright flash; deep colours wash — physics). Solid = BLEND (true-colour blink).
  inst.tex:SetBlendMode((p.blend == "blend") and "BLEND" or "ADD")
  inst.tex:ClearAllPoints(); inst.tex:SetPoint("CENTER", icon, "CENTER")
  inst.tex:SetSize(w + m, h + m); inst.tex:SetAlpha(inst.peak)
  inst.tex:Show()
  inst.frame:Show()
  rimflashActive[inst] = true; rimflashDriver:Show()
end

function RimFlash:Stop(host)
  local inst = rimflashInst[host]
  if inst then
    inst.frame:Hide()
    rimflashActive[inst] = nil
    if not next(rimflashActive) then rimflashDriver:Hide() end
  end
end

Anims:Register(RimFlash)

-- ===========================================================================
-- MODULE: RADAR SWEEP — a wide fading wedge (a scanner / clock hand) rotating over the
-- icon FACE (<key>-base), clipped to the shape: a glowing beam sweeps across the button
-- with its trail fading behind it. Comet Chase's rotation+mask mechanic, but a wide
-- face-filling wedge instead of a point on the rim. Bidirectional (CW/CCW).
-- ===========================================================================
local RADAR_TEX = GB.MEDIA .. "art\\radar.png"
local radarInst = {}
local radarActive = {}

local RADAR_MIN_REV = 1.4   -- sec/revolution at |spin| = 1

local radarDriver = CreateFrame("Frame"); radarDriver:Hide()
radarDriver:SetScript("OnUpdate", function(_, dt)
  for inst in pairs(radarActive) do
    inst.phase = (inst.phase + dt * inst.w) % (2 * math.pi)   -- inst.w is SIGNED (spin carries direction)
    inst.tex:SetRotation(inst.phase)
  end
end)

local Radar = {
  id = "radar",
  label = "Radar Sweep",
  defaults = { color = { 0.5, 1, 0.7 }, spin = 0.5, blend = "add" },
  params = {
    { key = "color", kind = "color",   label = "Colour" },
    { key = "spin",  kind = "bispeed", label = "Spin", minRev = RADAR_MIN_REV },
    { key = "blend", kind = "choice",  label = "Style", choices = { { "add", "Glow" }, { "blend", "Solid" } } },
  },
}

function Radar:Start(host, icon, key, p)
  if not (host and icon and key) then return end
  local inst = radarInst[host]
  if not inst then
    local frame = CreateFrame("Frame", nil, host)
    frame:SetFrameLevel(host:GetFrameLevel() + 3)   -- above the glow, below the text (+4)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(RADAR_TEX)
    tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
    inst = { frame = frame, tex = tex, mask = frame:CreateMaskTexture(), masked = false, phase = 0 }
    radarInst[host] = inst
  end
  local spin = p.spin; if spin == nil then spin = 0.5 end
  -- WoW rotation is CCW-positive; negate so positive spin = CLOCKWISE (matches the UI's CW side).
  local w = -spin * ((2 * math.pi) / RADAR_MIN_REV)   -- signed angular velocity (rad/sec)
  local cw = w < 0                                     -- mirror the wedge for CW so the trail always TRAILS
  local color = p.color or { 1, 1, 1 }
  local s = 1.6 * math.max(icon:GetWidth(), icon:GetHeight())   -- oversize so the sweep covers the face
  inst.w = w
  if GB.Skin and GB.Skin.AnchorHandGrown then GB.Skin:AnchorHandGrown(inst.mask, icon, 0) end
  inst.mask:SetTexture(GB:HandAsset(key, "base"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  inst.tex:ClearAllPoints(); inst.tex:SetSize(s, s); inst.tex:SetPoint("CENTER", icon, "CENTER")
  inst.tex:SetVertexColor(color[1], color[2], color[3])
  -- Glow = ADD (a glowing scan; deep colours wash — physics). Solid = BLEND (true-colour beam).
  inst.tex:SetBlendMode((p.blend == "blend") and "BLEND" or "ADD")
  if cw then inst.tex:SetTexCoord(1, 0, 0, 1) else inst.tex:SetTexCoord(0, 1, 0, 1) end   -- trail follows motion
  inst.tex:Show(); inst.tex:SetAlpha(PRIME_ALPHA)   -- prime near-invisible; revealed once the mask binds
  inst.frame:Show()
  radarActive[inst] = true; radarDriver:Show()
  C_Timer.After(0, function()   -- attach the mask + REVEAL after the first render (§2 defers the mask)
    if inst.frame:IsShown() and inst.tex:IsShown() then
      if not inst.masked then inst.tex:AddMaskTexture(inst.mask); inst.masked = true end
      inst.tex:SetAlpha(1)
    end
  end)
end

function Radar:Stop(host)
  local inst = radarInst[host]
  if inst then
    inst.frame:Hide()
    radarActive[inst] = nil
    if not next(radarActive) then radarDriver:Hide() end
  end
end

Anims:Register(Radar)
