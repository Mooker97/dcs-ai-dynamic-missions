-- DMS rng: own deterministic generator (L'Ecuyer combined LCG, exact in doubles),
-- independent of math.random so other scripts cannot disturb it.

DMS = DMS or {}
DMS.Rng = DMS.Rng or {}

local Rng = DMS.Rng

local M1, A1 = 2147483563, 40014
local M2, A2 = 2147483399, 40692

Rng._s1 = Rng._s1 or 12345
Rng._s2 = Rng._s2 or 67890

local function step()
  Rng._s1 = (A1 * Rng._s1) % M1
  Rng._s2 = (A2 * Rng._s2) % M2
  local z = Rng._s1 - Rng._s2
  if z < 1 then z = z + (M1 - 1) end
  return z -- 1 .. M1-1
end

-- DMS.Rng.seed(n): deterministic for a given n. With n nil, mixes the sub-second part of
-- timer.getTime()/getAbsTime() with DMS_CONFIG.seed. Returns the effective seed.
function Rng.seed(n)
  if n == nil then
    local cfg = DMS_CONFIG
    local base = (type(cfg) == "table" and tonumber(cfg.seed)) or 0
    local t = (timer and timer.getTime and timer.getTime()) or 0
    local abs = (timer and timer.getAbsTime and timer.getAbsTime()) or 0
    local frac = t - math.floor(t)
    n = base + math.floor(frac * 1000003) + math.floor(abs * 7919) % 1000003 + math.floor(t * 31)
  end
  n = math.floor(math.abs(tonumber(n) or 0))
  Rng._s1 = (n % (M1 - 1)) + 1
  Rng._s2 = ((math.floor(n / (M1 - 1)) + n * 7 + 1013904223) % (M2 - 1)) + 1
  for _ = 1, 12 do step() end
  Rng.lastSeed = n
  return n
end

function Rng.random()
  return (step() - 1) / (M1 - 1)
end

-- int(a, b) inclusive; int(b) == int(1, b)
function Rng.int(a, b)
  if b == nil then a, b = 1, a end
  a, b = math.floor(a), math.floor(b)
  if a > b then a, b = b, a end
  return a + math.floor(Rng.random() * (b - a + 1))
end

function Rng.chance(pct)
  pct = tonumber(pct) or 0
  if pct <= 0 then return false end
  if pct >= 100 then return true end
  return Rng.random() * 100 < pct
end

-- items: { {w=3, ...}, {w=1, ...} }; w defaults to 1; w<=0 never picked.
function Rng.weighted(items)
  if type(items) ~= "table" then return nil end
  local total = 0
  for _, it in ipairs(items) do
    local w = tonumber(type(it) == "table" and it.w or nil) or 1
    if w > 0 then total = total + w end
  end
  if total <= 0 then return nil end
  local r = Rng.random() * total
  local last
  for _, it in ipairs(items) do
    local w = tonumber(type(it) == "table" and it.w or nil) or 1
    if w > 0 then
      last = it
      if r < w then return it end
      r = r - w
    end
  end
  return last
end

function Rng.shuffle(list)
  for i = #list, 2, -1 do
    local j = Rng.int(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

-- n distinct elements (by position), random order. n clamps to #list.
function Rng.pickN(list, n)
  local copy = {}
  for i, v in ipairs(list or {}) do copy[i] = v end
  n = math.min(math.max(0, math.floor(tonumber(n) or 0)), #copy)
  local out = {}
  for i = 1, n do
    local j = Rng.int(i, #copy)
    copy[i], copy[j] = copy[j], copy[i]
    out[i] = copy[i]
  end
  return out
end

-- Shuffle bag: every item once per cycle; never the same position twice in a row across refills.
local Bag = {}
Bag.__index = Bag

function Bag:refill()
  local order = {}
  for i = 1, #self.items do order[i] = i end
  Rng.shuffle(order)
  if #order > 1 and order[1] == self.lastIdx then
    local j = Rng.int(2, #order)
    order[1], order[j] = order[j], order[1]
  end
  self.order, self.pos = order, 1
end

function Bag:next()
  if #self.items == 0 then return nil end
  if self.pos > #self.order then self:refill() end
  local idx = self.order[self.pos]
  self.pos = self.pos + 1
  self.lastIdx = idx
  return self.items[idx]
end

function Bag:size() return #self.items end
function Bag:remaining() return #self.order - self.pos + 1 end

function Rng.shuffleBag(list)
  local items = {}
  for i, v in ipairs(list or {}) do items[i] = v end
  local bag = setmetatable({ items = items, order = {}, pos = 1 }, Bag)
  return bag
end

function Rng.jitter(base, spread)
  base = tonumber(base) or 0
  spread = math.abs(tonumber(spread) or 0)
  return base + (Rng.random() * 2 - 1) * spread
end

-- t: number | {min, max} | {min=, max=}
function Rng.range(t)
  if type(t) == "number" then return t end
  if type(t) ~= "table" then return tonumber(t) or 0 end
  local lo = tonumber(t[1] or t.min) or 0
  local hi = tonumber(t[2] or t.max) or lo
  if hi < lo then lo, hi = hi, lo end
  return lo + Rng.random() * (hi - lo)
end

-- integer variant of range (inclusive), e.g. pick = {2, 4}
function Rng.rangeInt(t)
  if type(t) == "table" then
    local lo = tonumber(t[1] or t.min) or 0
    local hi = tonumber(t[2] or t.max) or lo
    return Rng.int(lo, hi)
  end
  return math.floor((tonumber(t) or 0) + 0.5)
end
