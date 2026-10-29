-- test_a3_spec.lua: DMS.Test check kinds flight_strike, camera_cues, voice_files, watch_mode and
-- plugins (docs/CONTRACTS.md "Test mode") on the full runtime, the DCS mock and its fake clock.
-- Scenarios that depend on rolled values run under several seeds.

local SEEDS = { 3, 7, 42 }

local function result(name)
  for _, l in ipairs(MOCK.log) do
    local st, n, detail = string.match(l.msg, "^%[DMS%.TEST%] (%u+) (%S+) ?(.*)$")
    if n == name and st ~= "INFO" then
      return st, detail
    end
  end
  return nil
end

local function infos(name)
  local out = {}
  for _, l in ipairs(MOCK.log) do
    local detail = string.match(l.msg, "^%[DMS%.TEST%] INFO " .. name .. " (.*)$")
    if detail then
      out[#out + 1] = detail
    end
  end
  return out
end

local function done()
  return (MOCK.logContains("^%[DMS%.TEST%] DONE "))
end

local function plane(name, x, y, alt)
  MOCK.addGroup({
    name = name,
    coalition = 2,
    country = "USA",
    category = "airplane",
    units = { { name = name .. "-1", type = "F-16C_50", x = x or 0, y = y or 0, alt = alt or 4000 } },
  })
  MOCK.units[name .. "-1"].ammo = { { count = 2, desc = { category = 3, guidance = 7, typeName = "GBU-12" } } }
end

local function ground(name, x, y, n)
  local units = {}
  for i = 1, n or 1 do
    units[i] = { name = name .. "-" .. i, type = "Hummer", x = x + (i - 1) * 10, y = y, alt = 0 }
  end
  MOCK.addGroup({ name = name, coalition = 1, category = "ground", units = units })
end

local function focus(x, y)
  MOCK.addGroup({
    name = "Dusty_dusty",
    coalition = 2,
    country = "USA",
    category = "helicopter",
    units = { { name = "Dusty_dusty-1", type = "UH-60A", x = x or 0, y = y or 0, alt = 150 } },
  })
end

-- `release` beat (flag) + a `beat` check on it hold the run open until the spec sets the flag.
local RELEASE = { kind = "beat", id = "release", name = "release" }

local function config(seed, checks, extra)
  local c = {
    seed = seed,
    missionId = "a3",
    players = { coalition = 2 },
    budgets = { maxActiveGround = 100, maxActiveAir = 10, spawnsPerMin = 60 },
    director = { enabled = false },
    zones = {
      gate = { kind = "circle", x = 10000, y = 0, radius = 1000 },
      target = { kind = "circle", x = 40000, y = 0, radius = 1000 },
    },
    narrative = { minGapSec = 1, zonePollSec = 1 },
    speakers = { ops = { callsign = "Magic", frequency = 251, modulation = 0 } },
    voice = {
      a = { file = "a.ogg", text = "Alpha", durSec = 3, speaker = "ops" },
      s = { text = "Sierra", durSec = 2, speaker = "ops" },
      u = { text = "Uniform", durSec = 2, speaker = "ops" },
    },
    beats = { { id = "release", when = { flag = "release" } } },
    test = { enabled = true, minutes = 10, checks = checks },
  }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

local function release()
  DMS.Narrative.setFlag("release", 1)
  MOCK.advance(12)
end

local function strikeFlight(maxSec)
  return {
    {
      id = "hog",
      group = "Hog_hog",
      category = "airplane",
      coalition = 2,
      orders = { { kind = "strike", at = "target", group = "technicals", weapon = "guided_bomb", maxSec = maxSec } },
    },
  }
end

local function shot(unit)
  MOCK.fireEvent({ id = "SHOT", initiator = Unit.getByName(unit), weapon = MOCK.makeWeapon("GBU-12") })
end

describe("DMS.Test flight_strike", function()
  for _, seed in ipairs(SEEDS) do
    it("passes when the strike released before the target died (seed " .. seed .. ")", function()
      plane("Hog_hog", 0, 0)
      ground("DMS_technicals_1", 40100, 0, 2)
      DMS_CONFIG = config(seed, { { kind = "flight_orders" }, { kind = "flight_strike", name = "fs" } }, {
        flights = strikeFlight(360),
      })
      DMS.boot()
      MOCK.advance(3)
      shot("Hog_hog-1")
      MOCK.advance(5)
      MOCK.killGroup("DMS_technicals_1")
      MOCK.advance(15)
      assert.is_true(done())
      local st, detail = result("fs")
      assert.are.equal("PASS", st)
      assert.are.equal("1 strike order(s), 1 with a release", detail)
    end)

    it("fails when the strike ended on maxSec with no release (seed " .. seed .. ")", function()
      plane("Hog_hog", 0, 0)
      ground("DMS_technicals_1", 40100, 0, 2)
      DMS_CONFIG = config(seed, { { kind = "flight_orders" }, { kind = "flight_strike", name = "fs" } }, {
        flights = strikeFlight({ 25, 35 }),
      })
      DMS.boot()
      MOCK.advance(60)
      assert.is_true(done())
      local st, detail = result("fs")
      assert.are.equal("FAIL", st)
      local rolled = tonumber(string.match(detail, "^hog#1 ended on maxSec %((%d+) s%) with no release"))
      assert.is_truthy(rolled, detail)
      assert.is_true(rolled >= 25 and rolled <= 35)
    end)

    it("reports INFO (not FAIL) when the target died before any release (seed " .. seed .. ")", function()
      plane("Hog_hog", 0, 0)
      ground("DMS_technicals_1", 40100, 0, 1)
      DMS_CONFIG = config(seed, { { kind = "flight_orders" }, { kind = "flight_strike", name = "fs" } }, {
        flights = strikeFlight(360),
      })
      DMS.boot()
      MOCK.advance(4)
      MOCK.killGroup("DMS_technicals_1")
      MOCK.advance(15)
      assert.is_true(done())
      local st, detail = result("fs")
      assert.are.equal("PASS", st)
      assert.are.equal("1 strike order(s), 0 with a release, 1 excused (INFO)", detail)
      assert.are.same({ "hog#1 target DMS_technicals_1 died before any release" }, infos("fs"))
    end)
  end

  it("fails a strike still running at the end with no release; vacuous without strikes", function()
    plane("Hog_hog", 0, 0)
    ground("DMS_technicals_1", 40100, 0, 1)
    DMS_CONFIG = config(1, { { kind = "flight_strike", name = "fs" }, RELEASE }, { flights = strikeFlight(900) })
    DMS.boot()
    MOCK.advance(20)
    release()
    local st, detail = result("fs")
    assert.are.equal("FAIL", st)
    assert.is_truthy(string.find(detail, "hog#1 still running after %d+ s with no release"))
  end)

  it("passes vacuously when no strike order started", function()
    DMS_CONFIG = config(1, { { kind = "flight_strike", name = "fs" }, RELEASE })
    DMS.boot()
    MOCK.advance(3)
    release()
    assert.are.same({ "PASS", "no strike order started (vacuous)" }, { result("fs") })
  end)
end)

describe("DMS.Test camera_cues", function()
  local function watchCfg(seed, checks)
    return config(seed, checks, {
      watch = { enabled = true, focus = "Dusty_dusty", cues = true },
      flights = {},
      beats = {
        { id = "at_gate", when = { event = "zone.entered", zone = "gate", playersOnly = true }, cue = "F2 on Dusty" },
        { id = "release", when = { flag = "release" } },
        { id = "never", when = { flag = "never" }, cue = "never shown" },
      },
    })
  end

  for _, seed in ipairs(SEEDS) do
    it("passes when every fired cued beat showed exactly one CAMERA text to all (seed " .. seed .. ")", function()
      focus(0, 0)
      DMS_CONFIG = watchCfg(seed, { { kind = "camera_cues", name = "cc" }, RELEASE })
      DMS_CONFIG.test.playerProxy = "Dusty_dusty"
      DMS.boot()
      MOCK.advance(3)
      MOCK.moveUnit("Dusty_dusty-1", 10000, 0)
      MOCK.advance(3)
      assert.are.equal(1, DMS.Narrative.firedCount("at_gate"))
      release()
      assert.are.same({ "PASS", "1 cued beat(s) fired, 1 CAMERA text(s)" }, { result("cc") })
    end)
  end

  it("fails on a duplicate cue, a cue not sent to all and a CAMERA text with no fired beat", function()
    focus(10000, 0)
    DMS_CONFIG = watchCfg(1, { { kind = "camera_cues", name = "cc" }, RELEASE })
    DMS_CONFIG.test.playerProxy = "Dusty_dusty"
    DMS.boot()
    MOCK.advance(5)
    assert.are.equal(1, DMS.Narrative.firedCount("at_gate"))
    DMS.Comms.text("CAMERA: F2 on Dusty", { all = true, durSec = 10 })
    DMS.Comms.text("CAMERA: F2 on Dusty", { coalition = 2 })
    DMS.Comms.text("CAMERA: rogue")
    release()
    local st, detail = result("cc")
    assert.are.equal("FAIL", st)
    assert.is_truthy(string.find(detail, "at_gate: cue shown 2 time(s), want 1", 1, true))
    assert.is_truthy(string.find(detail, "not sent to all: CAMERA: F2 on Dusty", 1, true))
    assert.is_truthy(string.find(detail, "no fired beat for: CAMERA: rogue", 1, true))
  end)

  it("fails when a fired cued beat showed nothing (cues suppressed)", function()
    focus(10000, 0)
    DMS_CONFIG = watchCfg(1, { { kind = "camera_cues", name = "cc" }, RELEASE })
    DMS_CONFIG.watch.cues = false
    DMS_CONFIG.test.playerProxy = "Dusty_dusty"
    DMS.boot()
    MOCK.advance(5)
    release()
    local st, detail = result("cc")
    assert.are.equal("FAIL", st)
    assert.is_truthy(string.find(detail, "at_gate: cue shown 0 time(s), want 1", 1, true))
  end)
end)

describe("DMS.Test voice_files", function()
  for _, seed in ipairs(SEEDS) do
    it("passes: voiced lines play their file, subtitle-only lines text only (seed " .. seed .. ")", function()
      DMS_CONFIG = config(seed, { { kind = "voice_files", name = "vf", subtitleOnly = { "s" } }, RELEASE })
      DMS.boot()
      MOCK.advance(2)
      DMS.Comms.say("ops", "a", nil, { coalition = 2 })
      DMS.Comms.say("ops", "s", nil, { coalition = 2 })
      DMS.Comms.say("ops", "u", nil, { coalition = 2 })
      DMS.Comms.say("ops", nil, "free text", { coalition = 2 }) -- no line id: ignored
      MOCK.advance(20)
      release()
      local st, detail = result("vf")
      assert.are.equal("PASS", st)
      assert.are.equal("1 voiced line(s) with their file, 2 subtitle-only (1 unrendered)", detail)
      assert.are.same({ "voiced line(s) with no rendered file (subtitle only): u" }, infos("vf"))
      assert.is_true((MOCK.logContains("PLAY n=%d+ line=s speaker=ops via=text file=%- ")))
    end)
  end

  it("fails a voiced:false line that has a file and a line that played the wrong file", function()
    DMS_CONFIG = config(1, { { kind = "voice_files", name = "vf", subtitleOnly = { "a" } }, RELEASE })
    DMS.boot()
    MOCK.advance(2)
    DMS.Comms.say("ops", "a", nil, { coalition = 2 })
    MOCK.advance(10)
    release()
    local st, detail = result("vf")
    assert.are.equal("FAIL", st)
    assert.is_truthy(string.find(detail, "a is voiced:false but has file a.ogg", 1, true))
  end)

  it("fails a line whose played file is not its own", function()
    DMS_CONFIG = config(1, { { kind = "voice_files", name = "vf" }, RELEASE })
    DMS.boot()
    MOCK.advance(2)
    DMS.Comms.say("ops", "a", nil, { coalition = 2 })
    MOCK.advance(10)
    DMS_CONFIG.voice.a.file = "a2.ogg"
    release()
    local st, detail = result("vf")
    assert.are.equal("FAIL", st)
    assert.is_truthy(string.find(detail, "a played file=a.ogg, want a2.ogg", 1, true))
  end)
end)

describe("DMS.Test watch_mode", function()
  local function watchCfg(seed, checks)
    return config(seed, checks, {
      watch = { enabled = true, focus = "Dusty_dusty", cues = true },
      flights = {},
    })
  end

  for _, seed in ipairs(SEEDS) do
    it("passes: focus registered, no radio transmission, marks for all (seed " .. seed .. ")", function()
      focus(0, 0)
      DMS_CONFIG = watchCfg(seed, { { kind = "watch_mode", name = "wm" }, RELEASE })
      DMS_CONFIG.test.playerProxy = "Dusty_dusty"
      DMS.boot()
      MOCK.advance(3)
      assert.is_truthy(DMS.Intel.mark("zone:gate"))
      DMS.Comms.say("ops", "a", nil, { coalition = 2 })
      MOCK.advance(10)
      release()
      -- a zone mark is a circle plus its text label: 2 draws, both for coalition -1
      assert.are.same({ "PASS", "focus=Dusty_dusty registered=true tx=0 marks=2" }, { result("wm") })
    end)
  end

  it("fails on a radio transmission and a mark for one coalition", function()
    focus(0, 0)
    DMS_CONFIG = watchCfg(1, { { kind = "watch_mode", name = "wm" }, RELEASE })
    DMS_CONFIG.test.playerProxy = "Dusty_dusty"
    DMS.boot()
    MOCK.advance(3)
    trigger.action.radioTransmission("l10n/DEFAULT/a.ogg", { x = 0, y = 0, z = 0 }, 0, false, 251000000, 100, "x")
    trigger.action.markToCoalition(DMS.Intel.FIRST_MARK_ID + 900, "x", { x = 0, y = 0, z = 0 }, 2, true)
    MOCK.advance(3)
    release()
    local st, detail = result("wm")
    assert.are.equal("FAIL", st)
    assert.is_truthy(string.find(detail, "1 radioTransmission call(s)", 1, true))
    local want = "marks not for coalition -1 (id:coal): " .. (DMS.Intel.FIRST_MARK_ID + 900) .. ":2"
    assert.is_truthy(string.find(detail, want, 1, true))
    assert.are.equal(1, MOCK.countCalls("trigger.action.radioTransmission")) -- wrapper calls through
  end)

  it("fails when the focus group is never registered", function()
    focus(0, 0)
    DMS_CONFIG = watchCfg(1, { { kind = "watch_mode", name = "wm" }, RELEASE })
    DMS_CONFIG.watch.focus = "Nobody_nobody"
    DMS.boot()
    MOCK.advance(3)
    release()
    local st, detail = result("wm")
    assert.are.equal("FAIL", st)
    local want = "focus Nobody_nobody not registered in DMS.Bus._players (group not found)"
    assert.is_truthy(string.find(detail, want, 1, true))
  end)

  it("fails on a mission that is not a watch mission", function()
    DMS_CONFIG = config(1, { { kind = "watch_mode", name = "wm" }, RELEASE })
    DMS.boot()
    MOCK.advance(3)
    release()
    assert.are.same({ "FAIL", "not a watch mission (DMS_CONFIG.watch.enabled is off)" }, { result("wm") })
  end)
end)

describe("DMS.Test plugins", function()
  it("passes once mist 4, MOOSE globals and an active Skynet IADS with enough sites are present", function()
    rawset(_G, "mist", { majorVersion = 4, minorVersion = 5, build = 126 })
    rawset(_G, "BASE", {})
    rawset(_G, "_DATABASE", {})
    DMS.SkynetAdapter = { active = false, sites = { sa6_site_1 = true } }
    DMS_CONFIG = config(1, { { kind = "plugins", name = "pl", plugins = { "mist", "moose", "skynet" } } })
    DMS.boot()
    MOCK.advance(5)
    assert.is_nil(result("pl")) -- polled: Skynet not active yet
    DMS.SkynetAdapter.active = true
    MOCK.advance(5)
    assert.are.same(
      { "PASS", "mist 4.5.126; moose BASE=true _DATABASE=true; skynet active=true sites=1/1" },
      { result("pl") }
    )
  end)

  it("fails at the deadline on a wrong mist version or too few Skynet sites", function()
    rawset(_G, "mist", { majorVersion = 3, minorVersion = 0, build = 1 })
    DMS.SkynetAdapter = { active = true, sites = { a = true } }
    DMS_CONFIG = config(1, { { kind = "plugins", name = "pl", plugins = { "mist", "skynet" }, min = 2 } })
    DMS_CONFIG.test.minutes = 2
    DMS.boot()
    MOCK.advance(130)
    local st, detail = result("pl")
    assert.are.equal("FAIL", st)
    assert.are.equal("timeout: mist 3.0.1; skynet active=true sites=1/2", detail)
  end)

  it("fails at once on an unknown plugin and when MOOSE is absent", function()
    DMS_CONFIG = config(1, {
      { kind = "plugins", name = "bad", plugins = { "ctld" } },
      { kind = "plugins", name = "moose", plugins = { "moose" }, deadlineSec = 20 },
    })
    DMS.boot()
    MOCK.advance(30)
    assert.are.same({ "FAIL", "unknown plugin 'ctld'" }, { result("bad") })
    assert.are.same({ "FAIL", "timeout: moose BASE=false _DATABASE=false" }, { result("moose") })
  end)
end)
