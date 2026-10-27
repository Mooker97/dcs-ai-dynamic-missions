-- lua/mocks/busted_shim.lua
-- Minimal busted-compatible test API for Lua 5.1 (runs inside lupa via lua/test_lua_specs.py).
--
-- Supported: describe, it, pending, before_each, after_each, setup/teardown (run per test),
-- assert.equals/equal/are.equal, same/are.same, is_true, is_false, is_nil, is_not_nil,
-- truthy, falsy, has_error/has_no_error/error_matches, near, matches, is_table/is_function/
-- is_string/is_number, negations via assert.is_not.<x> / assert.are_not.<x> / assert.not_<x>,
-- plus spy.new(fn), spy.on(tbl, key), assert.spy(s).was_called(n) / was_called_with(...) /
-- was_not_called().
--
-- The runner calls SHIM.list() to enumerate tests and SHIM.run(i) to run exactly one test.

local S = { tests = {}, stack = {} }
SHIM = S

local function currentNames()
  local names = {}
  for i, d in ipairs(S.stack) do names[i] = d.name end
  return names
end

function describe(name, fn)
  local block = { name = tostring(name), before = {}, after = {} }
  S.stack[#S.stack + 1] = block
  local ok, err = pcall(fn)
  S.stack[#S.stack] = nil
  if not ok then error(err, 0) end
end
context = describe

function before_each(fn) S.stack[#S.stack].before[#S.stack[#S.stack].before + 1] = fn end
function after_each(fn) S.stack[#S.stack].after[#S.stack[#S.stack].after + 1] = fn end
setup = before_each
teardown = after_each
lazy_setup = before_each
lazy_teardown = after_each

local function register(name, fn, isPending)
  local chain = {}
  for i, d in ipairs(S.stack) do chain[i] = d end
  local names = currentNames()
  names[#names + 1] = tostring(name)
  S.tests[#S.tests + 1] = { name = table.concat(names, " > "), fn = fn, chain = chain, pending = isPending }
end

function it(name, fn) register(name, fn, fn == nil) end
function pending(name) register(name, nil, true) end

function S.list()
  local r = {}
  for i, t in ipairs(S.tests) do r[i] = t.name end
  return r
end

local function tb(err)
  if type(err) == "table" and err.__assertion then return err.msg end
  return debug.traceback(tostring(err), 2)
end

-- returns status ("pass"|"fail"|"pending"), message
function S.run(i)
  local t = S.tests[i]
  if not t then return "fail", "no such test #" .. tostring(i) end
  if t.pending then return "pending", t.name end
  local errMsg
  local ran = {}
  for _, block in ipairs(t.chain) do
    for _, b in ipairs(block.before) do
      local ok, e = xpcall(b, tb)
      if not ok then errMsg = "before_each failed: " .. tostring(e); break end
    end
    ran[#ran + 1] = block
    if errMsg then break end
  end
  if not errMsg then
    local ok, e = xpcall(t.fn, tb)
    if not ok then errMsg = e end
  end
  for k = #ran, 1, -1 do
    for _, a in ipairs(ran[k].after) do
      local ok, e = xpcall(a, tb)
      if not ok and not errMsg then errMsg = "after_each failed: " .. tostring(e) end
    end
  end
  if errMsg then return "fail", errMsg end
  return "pass", ""
end

-- ---------------------------------------------------------------------------
-- assertions
-- ---------------------------------------------------------------------------

local function fmt(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" or depth > 2 then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for idx, k in ipairs(keys) do
    if idx > 12 then parts[#parts + 1] = "..."; break end
    parts[#parts + 1] = tostring(k) .. "=" .. fmt(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end
S.fmt = fmt

local function deepEq(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not deepEq(v, b[k], seen) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
S.deepEq = deepEq

local function fail(msg, level)
  local info = debug.getinfo(level or 4, "Sl")
  local where = info and (info.short_src .. ":" .. tostring(info.currentline)) or "?"
  error({ __assertion = true, msg = where .. ": " .. msg }, 0)
end

-- each checker returns ok, message-when-positive-fails, message-when-negated-fails
local checks = {}
checks.equals = function(e, a) return e == a, "expected " .. fmt(e) .. ", got " .. fmt(a), "expected value other than " .. fmt(e) end
checks.same = function(e, a) return deepEq(e, a), "expected (deep) " .. fmt(e) .. ", got " .. fmt(a), "expected tables to differ: " .. fmt(a) end
checks.is_true = function(v) return v == true, "expected true, got " .. fmt(v), "expected not true" end
checks.is_false = function(v) return v == false, "expected false, got " .. fmt(v), "expected not false" end
checks.is_nil = function(v) return v == nil, "expected nil, got " .. fmt(v), "expected non-nil value" end
checks.truthy = function(v) return v ~= nil and v ~= false, "expected truthy, got " .. fmt(v), "expected falsy, got " .. fmt(v) end
checks.falsy = function(v) return v == nil or v == false, "expected falsy, got " .. fmt(v), "expected truthy, got " .. fmt(v) end
checks.near = function(e, a, tol) return type(a) == "number" and math.abs(e - a) <= tol, "expected " .. tostring(e) .. " +/- " .. tostring(tol) .. ", got " .. fmt(a), "expected value outside " .. tostring(e) .. " +/- " .. tostring(tol) end
checks.matches = function(p, s) return type(s) == "string" and string.find(s, p) ~= nil, "expected " .. fmt(s) .. " to match " .. fmt(p), "expected " .. fmt(s) .. " not to match " .. fmt(p) end
checks.has_error = function(fn, msg)
  local ok, err = pcall(fn)
  if ok then return false, "expected an error", "expected no error" end
  if msg ~= nil then
    local s = type(err) == "string" and err or tostring(err)
    if s ~= msg and not string.find(s, msg, 1, true) then return false, "expected error containing " .. fmt(msg) .. ", got " .. fmt(s), "" end
  end
  return true, "", "expected no error, got " .. tostring(err)
end
checks.error_matches = function(fn, pat)
  local ok, err = pcall(fn)
  if ok then return false, "expected an error", "" end
  return string.find(tostring(err), pat) ~= nil, "error " .. fmt(tostring(err)) .. " does not match " .. fmt(pat), "error matched " .. fmt(pat)
end
for _, ty in ipairs({ "table", "function", "string", "number", "boolean" }) do
  checks["is_" .. ty] = function(v) return type(v) == ty, "expected " .. ty .. ", got " .. type(v), "expected non-" .. ty end
end

local aliases = {
  equals = { "equals", "equal", "are_equal", "is_equal" },
  same = { "same", "are_same", "is_same" },
  is_true = { "is_true", "True" },
  is_false = { "is_false", "False" },
  is_nil = { "is_nil", "Nil" },
  truthy = { "truthy", "is_truthy" },
  falsy = { "falsy", "is_falsy" },
  has_error = { "has_error", "has_errors", "error" },
  error_matches = { "error_matches", "has_error_match" },
  near = { "near", "are_near", "is_near" },
  matches = { "matches", "match", "is_match" },
}

local function makeAssert(name, negate)
  local c = checks[name]
  return function(...)
    local ok, pmsg, nmsg = c(...)
    if negate then ok = not ok end
    if not ok then fail(negate and nmsg or pmsg, 3) end
    return ...
  end
end

local pos, neg = {}, {}
for name in pairs(checks) do
  local names = aliases[name] or { name }
  for _, n in ipairs(names) do
    pos[n] = makeAssert(name, false)
    neg[n] = makeAssert(name, true)
  end
end
-- "base" names usable after assert.is./assert.are./assert.is_not.
local base = { equals = "equals", equal = "equals", same = "same", ["true"] = "is_true", ["false"] = "is_false",
               ["nil"] = "is_nil", truthy = "truthy", falsy = "falsy", near = "near", matches = "matches",
               error = "has_error", table = "is_table", ["function"] = "is_function", string = "is_string",
               number = "is_number", boolean = "is_boolean" }
local isT, isNotT = {}, {}
for k, v in pairs(base) do isT[k] = makeAssert(v, false); isNotT[k] = makeAssert(v, true) end

assert = setmetatable({}, {
  __call = function(_, v, msg, ...)
    if not v then fail(msg and tostring(msg) or "assertion failed!", 3) end
    return v, msg, ...
  end,
})
for k, f in pairs(pos) do assert[k] = f end
for k, f in pairs(neg) do assert["not_" .. k] = f end
assert.is_not_nil = neg.is_nil
assert.has_no_error = neg.has_error
assert.has_no_errors = neg.has_error
assert.not_equals = neg.equals
assert.is = isT
assert.are = isT
assert.is_not = isNotT
assert.are_not = isNotT
assert.fail = function(msg) fail(tostring(msg or "failed"), 3) end

-- ---------------------------------------------------------------------------
-- spies
-- ---------------------------------------------------------------------------

spy = {}
local spyMeta = {}
spyMeta.__index = spyMeta
spyMeta.__call = function(self, ...)
  self.calls[#self.calls + 1] = { n = select("#", ...), ... }
  if self.fn then return self.fn(...) end
end
function spyMeta:clear() self.calls = {} end
function spy.new(fn) return setmetatable({ calls = {}, fn = fn }, spyMeta) end
function spy.on(tbl, key)
  local s = spy.new(tbl[key])
  tbl[key] = s
  return s
end

local function argsMatch(call, expected)
  if call.n ~= expected.n then return false end
  for i = 1, expected.n do if not deepEq(expected[i], call[i]) then return false end end
  return true
end

function assert.spy(s)
  local w = {}
  function w.was_called(n)
    if n == nil then
      if #s.calls == 0 then fail("expected spy to be called", 3) end
    elseif #s.calls ~= n then fail("expected spy to be called " .. n .. " times, was called " .. #s.calls, 3) end
  end
  function w.was_not_called()
    if #s.calls ~= 0 then fail("expected spy not to be called, was called " .. #s.calls .. " times", 3) end
  end
  function w.was_called_with(...)
    local exp = { n = select("#", ...), ... }
    for _, c in ipairs(s.calls) do if argsMatch(c, exp) then return end end
    fail("no call matched args " .. fmt(exp) .. "; calls: " .. fmt(s.calls), 3)
  end
  w.was = { called = w.was_called, called_with = w.was_called_with }
  w.was_not = { called = w.was_not_called }
  return w
end
assert.stub = assert.spy
