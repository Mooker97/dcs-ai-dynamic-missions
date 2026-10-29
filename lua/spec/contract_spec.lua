-- contract_spec.lua: cross-module contract (docs/CONTRACTS.md) on the real modules + DCS mock.
-- Canonical DMS_CONFIG shapes as emitted by RuntimeConfig.to_lua_source(), plus the Lua aliases.

local function eq(a, b, msg)
  if a ~= b then
    error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
  end
end

local function capture(evName)
  local got = {}
  DMS.Bus.on(evName, function(p)
    got[#got + 1] = p or {}
  end)
  return got
end

local function noErrors()
  local errs = MOCK.logLines and MOCK.logLines("error") or {}
  if #errs > 0 then
    error("error log: " .. tostring(errs[1].msg or errs[1]), 2)
  end
end

local function startNarrative(cfg)
  cfg.missionId = cfg.missionId or "m-test"
  cfg.narrative = cfg.narrative or { minGapSec = 0 }
  DMS_CONFIG = cfg
  DMS.Rng.seed(cfg.seed or 1)
  DMS.Narrative.start()
end

local function fired(id)
  return DMS.Narrative.firedCount(id)
end

local function outcomes()
  local out = {}
  for _, l in ipairs(MOCK.log) do
    if string.find(l.msg, "[DMS.OUTCOME]", 1, true) then
      out[#out + 1] = l.msg
    end
  end
  return out
end

describe("bus + init contract", function()
  it("S_EVENT_MISSION_END emits mission.end and narrative writes the final outcome", function()
    startNarrative({ beats = {} })
    local ends = capture("mission.end")
    MOCK.fireEvent({ id = "MISSION_END" })
    eq(#ends, 1)
    local o = outcomes()
    assert(#o == 1 and string.find(o[1], '"kind":"end"', 1, true), "final outcome line")
    assert(string.find(o[1], '"result":"ended"', 1, true), "default result")
    assert(string.find(o[1], '"missionId":"m-test"', 1, true), "missionId")
  end)

  it("DMS.boot emits mission.start, which canonical beats can use", function()
    DMS_CONFIG = {
      missionId = "m",
      narrative = { minGapSec = 0 },
      beats = { { id = "go", when = { event = "mission.start" }, text = "Go" } },
    }
    local starts = capture("mission.start")
    assert.is_true(DMS.boot())
    eq(#starts, 1)
    eq(starts[1].missionId, "m")
    eq(fired("go"), 1)
  end)

  for _, cfg in ipairs({ {}, { missionId = "x" } }) do
    it("all modules tolerate a minimal DMS_CONFIG (" .. (cfg.missionId or "empty") .. ")", function()
      DMS_CONFIG = cfg
      assert.is_true(DMS.boot())
      MOCK.spawnPlayer({ name = "P-1", group = "P", playerName = "Mav", x = 0, y = 0, alt = 500 })
      MOCK.addGroup({
        name = "E",
        coalition = 1,
        category = "ground",
        units = { { name = "E-1", type = "T-72B", x = 3000, y = 0 } },
      })
      MOCK.advance(30)
      MOCK.hitUnit("P-1", { initiator = "E-1", damage = 0 })
      MOCK.killUnit("E-1", { killer = "P-1" })
      MOCK.fireEvent({ id = "LAND", initiator = Unit.getByName("P-1") })
      MOCK.advance(600)
      MOCK.fireEvent({ id = "MISSION_END" })
      noErrors()
    end)
  end
end)

describe("narrative canonical when/requires/effects", function()
  it("timer and flag events are state triggers", function()
    startNarrative({
      beats = {
        { id = "t", when = { event = "timer", afterSec = 5 } },
        { id = "f", when = { event = "flag", flag = "x", value = 2 } },
        { id = "fs", when = { event = "flag", flag = "y" } },
      },
    })
    MOCK.advance(3)
    eq(fired("t"), 0)
    MOCK.advance(3)
    eq(fired("t"), 1)
    DMS.Narrative.setFlag("x", 1)
    DMS.Narrative.setFlag("y")
    MOCK.advance(2)
    eq(fired("f"), 0, "value 2 required")
    eq(fired("fs"), 1)
    DMS.Narrative.setFlag("x", 2)
    MOCK.advance(2)
    eq(fired("f"), 1)
  end)

  it("event filters: beat/encounter ids, director state+flight, zone, coalition, typeName", function()
    startNarrative({
      beats = {
        { id = "src", when = { event = "mission.start" } },
        { id = "after", when = { event = "beat.fired", beat = "src" } },
        { id = "enc", when = { event = "encounter.spawned", encounter = "popup" } },
        { id = "relax", when = { event = "director.state", state = "RELAX", flight = "P" } },
        { id = "zone", when = { event = "zone.entered", zone = "box" } },
        { id = "red_hit", when = { event = "unit.hit", coalition = 1 } },
        { id = "shilka", when = { event = "unit.dead", typeName = "ZSU-23-4 Shilka" } },
      },
    })
    DMS.Bus.emit("mission.start", {})
    eq(fired("src"), 1)
    eq(fired("after"), 1)
    DMS.Bus.emit("encounter.spawned", { id = "other" })
    DMS.Bus.emit("encounter.spawned", { id = "popup" })
    eq(fired("enc"), 1)
    DMS.Bus.emit("director.state", { flight = "Q", state = "RELAX" })
    eq(fired("relax"), 0)
    DMS.Bus.emit("director.state", { flight = "P", state = "RELAX" })
    eq(fired("relax"), 1)
    DMS.Bus.emit("zone.entered", { zone = "box", unit = "u" })
    eq(fired("zone"), 1)
    DMS.Bus.emit("unit.hit", { target = "a", targetCoalition = 2 })
    eq(fired("red_hit"), 0)
    DMS.Bus.emit("unit.hit", { target = "a", targetCoalition = 1 })
    eq(fired("red_hit"), 1)
    DMS.Bus.emit("unit.dead", { unit = "a", typeName = "T-72B" })
    DMS.Bus.emit("unit.dead", { unit = "b", typeName = "ZSU-23-4 Shilka" })
    eq(fired("shilka"), 1)
  end)

  it("playersOnly uses the subject unit; groupPrefix matches DMS_-prefixed spawns", function()
    startNarrative({
      beats = {
        { id = "spawned", when = { event = "player.spawned", playersOnly = true } },
        { id = "phit", when = { event = "unit.hit", playersOnly = true }, once = false },
        { id = "pshot", when = { event = "unit.shot", playersOnly = true } },
        { id = "aa_dead", when = { event = "group.dead", groupPrefix = "hidden_aa" } },
        { id = "civ", when = { event = "unit.dead", groupPrefix = "civilians" } },
      },
    })
    MOCK.spawnPlayer({ name = "P-1", group = "P", playerName = "Mav", x = 0, y = 0 })
    eq(fired("spawned"), 1)
    DMS.Bus.emit("unit.hit", { target = "AI-1", initiator = "P-1" })
    eq(fired("phit"), 0, "player as initiator is not the subject of unit.hit")
    DMS.Bus.emit("unit.hit", { target = "P-1", initiator = "AI-1" })
    eq(fired("phit"), 1)
    DMS.Bus.emit("unit.shot", { initiator = "AI-1" })
    eq(fired("pshot"), 0)
    DMS.Bus.emit("unit.shot", { initiator = "P-1" })
    eq(fired("pshot"), 1)
    DMS.Bus.emit("group.dead", { group = "DMS_hidden_aa_3" })
    eq(fired("aa_dead"), 1)
    DMS.Bus.emit("unit.dead", { unit = "x", group = "civilians_road" })
    eq(fired("civ"), 1)
  end)

  it("beat-level delaySec wins over when.delaySec", function()
    startNarrative({
      beats = {
        { id = "d", when = { event = "mission.start", delaySec = 2 }, delaySec = 10 },
        { id = "w", when = { event = "mission.start", delaySec = 3 } },
      },
    })
    DMS.Bus.emit("mission.start", {})
    MOCK.advance(4)
    eq(fired("w"), 1)
    eq(fired("d"), 0)
    MOCK.advance(7)
    eq(fired("d"), 1)
  end)

  it("requires: flags, flagsNot, quality list and map forms", function()
    startNarrative({
      qualities = { trust = 2, aa = 1 },
      beats = {
        {
          id = "ok",
          when = { event = "x" },
          requires = {
            flags = { "a" },
            flagsNot = { "b" },
            qualities = { { quality = "trust", op = ">=", value = 2 }, { quality = "aa", op = "<", value = 2 } },
          },
        },
        {
          id = "notq",
          when = { event = "x" },
          requires = { qualities = { { quality = "trust", op = ">", value = 2 } } },
        },
        {
          id = "map",
          when = { event = "x" },
          requires = { notFlags = { "zz" }, qualities = { trust = ">=2", aa = { min = 0, max = 1 } } },
        },
        { id = "blocked", when = { event = "x" }, requires = { flagsNot = { "a" } } },
      },
    })
    DMS.Narrative.setFlag("a")
    DMS.Bus.emit("x", {})
    eq(fired("ok"), 1)
    eq(fired("notq"), 0)
    eq(fired("map"), 1)
    eq(fired("blocked"), 0)
  end)

  it("effects: flag lists, flagValue, qualityDeltas live + outcome, spawnPool, endMission", function()
    local spawned = {}
    DMS.Spawner.spawnPool = function(id, opts)
      spawned[#spawned + 1] = id
      return { "g1" }
    end
    startNarrative({
      qualities = { trust = 0 },
      beats = {
        {
          id = "e",
          when = { event = "go" },
          effects = {
            setFlag = { "f1", "f2" },
            flagValue = 3,
            clearFlag = { "old" },
            qualityDeltas = { trust = 1, harm = -1 },
            outcome = { done = true },
            spawnPool = "patrols",
          },
        },
        {
          id = "later",
          when = { event = "beat.fired", beat = "e" },
          requires = { qualities = { { quality = "trust", op = ">=", value = 1 } } },
          effects = { endMission = "success" },
        },
      },
    })
    DMS.Narrative.setFlag("old")
    DMS.Bus.emit("go", {})
    eq(DMS.Narrative.getFlag("f1"), 3)
    eq(DMS.Narrative.getFlag("f2"), 3)
    eq(DMS.Narrative.getFlag("old"), 0)
    eq(DMS.Narrative.getQuality("trust"), 1)
    eq(DMS.Narrative.qualityDeltas().harm, -1)
    eq(spawned[1], "patrols")
    eq(fired("later"), 1, "live quality delta visible to later requires")
    local o = outcomes()
    local last = o[#o]
    assert(string.find(last, '"kind":"end"', 1, true), last)
    assert(string.find(last, '"result":"success"', 1, true), last)
    assert(string.find(last, '"qualityDeltas":{"harm":-1,"trust":1}', 1, true), last)
    assert(string.find(last, '"flags":{', 1, true) and string.find(last, '"f1":true', 1, true), last)
    assert(string.find(last, '"old":false', 1, true), last)
    assert(string.find(last, '"beats":["e","later"]', 1, true), last)
  end)

  it("startEncounter list calls DMS.Encounters.trigger(id, {beat = id})", function()
    local calls = {}
    DMS.Encounters.trigger = function(id, opts)
      calls[#calls + 1] = { id = id, opts = opts }
      return true
    end
    startNarrative({ beats = { { id = "b", when = { event = "go" }, effects = { startEncounter = { "e1", "e2" } } } } })
    DMS.Bus.emit("go", {})
    eq(#calls, 2)
    eq(calls[2].id, "e2")
    eq(calls[1].opts.beat, "b")
  end)

  it("guaranteed beats ignore chance and outlive the pending TTL while requires hold", function()
    startNarrative({
      narrative = { minGapSec = 60, pendingTtlSec = 5 },
      beats = {
        { id = "first", text = "first", priority = 99, when = { event = "go" } },
        {
          id = "g",
          text = "g",
          guaranteed = true,
          when = { event = "go" },
          requires = { chance = 0, flagsNot = { "stop" } },
        },
        { id = "g2", text = "g2", guaranteed = true, when = { event = "go" }, requires = { flagsNot = { "stop2" } } },
        { id = "n", text = "n", when = { event = "go" } },
      },
    })
    DMS.Bus.emit("go", {})
    eq(fired("first"), 1)
    MOCK.advance(10)
    DMS.Narrative.setFlag("stop2") -- g2 no longer eligible -> drops on the normal TTL
    MOCK.advance(55)
    eq(fired("g"), 1, "guaranteed beat waited out the min gap past its TTL")
    eq(fired("n"), 0, "normal beat expired")
    DMS.Narrative.setFlag("stop2", 0)
    MOCK.advance(120)
    eq(fired("g2"), 0, "dropped once its requires stopped holding past the TTL")
  end)

  it("requires are checked when the trigger occurs, not only at fire time", function()
    startNarrative({
      beats = {
        { id = "late", when = { event = "gate" }, requires = { flags = { "on_station" } } },
      },
    })
    DMS.Bus.emit("gate", {})
    DMS.Narrative.setFlag("on_station")
    MOCK.advance(5)
    eq(fired("late"), 0, "not queued while ineligible")
    assert(MOCK.logContains("not eligible") or not DMS.Log.isDebug(), "debug reason")
    eq(DMS.Narrative.trigger("late", "manual"), true)
    eq(fired("late"), 1)
  end)

  it("silent beats bypass the min gap and do not delay radio beats", function()
    startNarrative({
      narrative = { minGapSec = 30 },
      beats = {
        { id = "talk", text = "Contact", priority = 10, when = { event = "kill" } },
        { id = "quiet", priority = 90, when = { event = "kill" }, effects = { outcome = { killed = true } } },
        { id = "quiet2", priority = 90, when = { event = "kill2" }, effects = { outcome = { killed2 = true } } },
        { id = "talk2", text = "Again", when = { event = "kill2" } },
      },
    })
    DMS.Bus.emit("kill", {})
    eq(fired("quiet"), 1)
    eq(fired("talk"), 1, "silent beat did not consume the gap")
    DMS.Bus.emit("kill2", {})
    eq(fired("quiet2"), 1, "silent beat fires inside the gap")
    eq(fired("talk2"), 0)
    MOCK.advance(31)
    eq(fired("talk2"), 1)
  end)

  it("beat.request from an encounter telegraph triggers the beat with normal eligibility", function()
    startNarrative({
      beats = {
        { id = "warn", when = { event = "encounter.spawned", encounter = "popup" } },
        { id = "gated", requires = { flags = { "never" } } },
      },
    })
    DMS.Bus.emit("beat.request", { id = "warn", encounter = "popup" })
    eq(fired("warn"), 1)
    DMS.Bus.emit("beat.request", { id = "warn", encounter = "popup" })
    eq(fired("warn"), 1, "once")
    DMS.Bus.emit("beat.request", { id = "gated", encounter = "x" })
    eq(fired("gated"), 0)
    DMS.Bus.emit("beat.request", { id = "nope" })
  end)
end)

describe("encounters contract", function()
  local function cfg(encounters)
    return {
      seed = 3,
      players = { coalition = 2 },
      budgets = { maxActiveGround = 200, spawnsPerMin = 50 },
      templates = {
        zu = { country = "RUSSIA", category = "ground", units = { { type = "ZU-23 Emplacement", heading = 90 } } },
      },
      zones = { box = { kind = "circle", x = 40000, y = 0, radius = 2000 } },
      pools = { aa = { members = { { tpl = "zu" } }, pick = 1, zones = { "box" } } },
      encounters = encounters,
    }
  end

  it("trigger(id, opts): {beat=} respects once, true forces", function()
    DMS_CONFIG = cfg({ { id = "e", kind = "pool", pool = "aa", gated = false, trigger = { type = "manual" } } })
    DMS.Encounters.start()
    local spawned = capture("encounter.spawned")
    assert.is_true(DMS.Encounters.trigger("e", { beat = "b1" }))
    assert.is_false(DMS.Encounters.trigger("e", { beat = "b1" }))
    eq(#spawned, 1)
    eq(spawned[1].encounter, "e")
    eq(spawned[1].id, "e")
    assert.is_true(DMS.Encounters.trigger("e", true))
    eq(#spawned, 2)
    assert(MOCK.logContains("triggered by beat b1"), "trigger reason logged")
  end)

  it("proximity emits encounter.proximity, never zone.entered", function()
    DMS_CONFIG = cfg({
      {
        id = "p",
        kind = "pool",
        pool = "aa",
        gated = false,
        trigger = { type = "proximity", zone = "box", radiusM = 10000 },
      },
    })
    DMS.Encounters.start()
    local prox, zones = capture("encounter.proximity"), capture("zone.entered")
    MOCK.spawnPlayer({ name = "P-1", group = "P", x = 32000, y = 0, alt = 300 })
    MOCK.advance(12)
    eq(#prox, 1)
    eq(prox[1].encounter, "p")
    eq(prox[1].zone, "box")
    eq(prox[1].unit, "P-1")
    eq(#zones, 0)
  end)

  it("event trigger ignores configuration keys when filtering", function()
    DMS_CONFIG = cfg({
      {
        id = "ev",
        kind = "pool",
        pool = "aa",
        gated = false,
        trigger = { type = "event", event = "convoy.halted", checkSec = 5, group = "C1" },
      },
    })
    DMS.Encounters.start()
    local spawned = capture("encounter.spawned")
    DMS.Bus.emit("convoy.halted", { group = "C2" })
    eq(#spawned, 0)
    DMS.Bus.emit("convoy.halted", { group = "C1" })
    eq(#spawned, 1)
  end)
end)

describe("comms contract", function()
  it("speaker frequency/modulation defaults, turns subtitles, keep never dropped", function()
    DMS_CONFIG = {
      speakers = { ops = { callsign = "Hatay Ops", frequency = 251.0, modulation = 0 }, kes = { callsign = "Kestrel" } },
      voice = {
        x_v1 = {
          file = "x_v1.ogg",
          text = "Kestrel, Ops. Copy.",
          durSec = 3,
          speaker = "ops",
          turns = {
            { speaker = "kes", text = "Ops, Kestrel. Routine." },
            { speaker = "ops", text = "Kestrel, Ops. Copy." },
          },
        },
      },
    }
    DMS.Comms.start()
    MOCK.addPlayer("Viper1", 2, 1000, 2000) -- radio needs a real transmitter position (the player)
    DMS.Comms.say("ops", { "x_v1" }, nil, { coalition = 2 })
    local tx = MOCK.callsTo("trigger.action.radioTransmission")
    eq(#tx, 1, "radio transmission on the speaker frequency")
    eq(tx[1].args[5], 251000000)
    local h = DMS.Comms.history()
    eq(h[1].text, "Kestrel: Ops, Kestrel. Routine.\nHatay Ops: Kestrel, Ops. Copy.")
    -- overflow: keep items survive
    DMS.Comms.say("kes", nil, "keep me", { priority = 0, keep = true })
    for i = 1, DMS.Comms.MAX_QUEUE + 3 do
      DMS.Comms.say("kes", nil, "filler " .. i, { priority = 50 })
    end
    MOCK.advance(600)
    local found = false
    for _, p in ipairs(DMS.Comms.history()) do
      if string.find(p.text, "keep me", 1, true) then
        found = true
      end
    end
    assert(found, "keep item played despite overflow")
  end)

  it("voice entries without a file (nil or empty) are subtitle-only", function()
    DMS_CONFIG = {
      voice = {
        a = { text = "Subtitle A", durSec = 2, speaker = "ops" },
        b = { file = "", text = "Subtitle B", durSec = 2, speaker = "ops" },
      },
    }
    DMS.Comms.start()
    assert(DMS.Comms.say("ops", { "a" }, nil, { coalition = 2 }))
    MOCK.advance(5)
    assert(DMS.Comms.say("ops", { "b" }, nil, { coalition = 2, frequency = 251 }))
    MOCK.advance(5)
    eq(#MOCK.callsTo("trigger.action.outSoundForCoalition"), 0)
    eq(#MOCK.callsTo("trigger.action.radioTransmission"), 0)
    local h = DMS.Comms.history()
    eq(#h, 2)
    eq(h[2].text, "ops: Subtitle B")
    eq(h[2].dur, 2)
  end)
end)

describe("intel.mark contract", function()
  it("text/point marks have no circle; radiusM, unit:, point:x,y and group prefixes resolve", function()
    DMS_CONFIG = { zones = { box = { kind = "circle", x = 1000, y = 2000, radius = 500 } } }
    DMS.Intel.start()
    MOCK.addGroup({
      name = "DMS_hidden_aa_2",
      coalition = 1,
      category = "ground",
      units = { { name = "aa-1", type = "ZU-23 Emplacement", x = 5000, y = 5000 } },
    })
    MOCK.addGroup({
      name = "Kestrel",
      coalition = 2,
      category = "ground",
      units = { { name = "kes-1", type = "Soldier M4", x = 7000, y = 100 } },
    })
    local nCircle = function()
      return #MOCK.callsTo("trigger.action.circleToAll")
    end
    assert(DMS.Intel.mark({ type = "text", at = "zone:box", text = "BOX" }))
    eq(nCircle(), 0, "text mark has no circle")
    assert(DMS.Intel.mark({ type = "circle", at = "zone:box", radiusM = 1234 }))
    eq(nCircle(), 1)
    eq(MOCK.callsTo("trigger.action.circleToAll")[1].args[4], 1234)
    assert(DMS.Intel.mark({ type = "point", at = "unit:kes-1", text = "KESTREL" }))
    local m = MOCK.callsTo("trigger.action.markToCoalition")
    eq(m[#m].args[3].x, 7000)
    assert(DMS.Intel.mark("point:300,400"))
    m = MOCK.callsTo("trigger.action.markToCoalition")
    eq(m[#m].args[3].z, 400)
    assert(DMS.Intel.mark({ type = "circle", at = "group:hidden_aa", text = "AAA (NEW)", radiusM = 1500 }))
    assert(DMS.Intel.contact("DMS_hidden_aa_2"), "prefix resolved to the DMS_ spawn")
    eq(DMS.Intel.mark("group:nothing"), nil)
    eq(DMS.Intel.mark("unit:nobody"), nil)
  end)
end)

describe("v0.9 contract keys (not implemented) are tolerated", function()
  it("boots with scope/perFlight/comms/state/resume and a v0.9 kind, no errors", function()
    DMS_CONFIG = {
      missionId = "m-v09",
      narrative = { minGapSec = 0 },
      beats = {
        { id = "go", when = { event = "mission.start" }, scope = "flight", text = "Go" },
        { id = "late", when = { event = "player.joined_late" }, scope = "flight" },
      },
      encounters = {
        { id = "arty", kind = "artillery", perFlight = true, trigger = { type = "manual" } },
      },
      comms = { maxAgeSec = 45 },
      state = { enabled = true, intervalSec = 300, chunkBytes = 2000 },
      resume = { seq = 1, t = 0, seed = 7, modules = { Narrative = { fired = {} } } },
    }
    assert.is_true(DMS.boot())
    MOCK.spawnPlayer({ name = "P-1", group = "P", playerName = "Mav", x = 0, y = 0, alt = 500 })
    MOCK.advance(60)
    eq(fired("go"), 1)
    noErrors()
  end)
end)
