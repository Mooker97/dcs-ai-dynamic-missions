-- watch_spec.lua: watch missions (stand-in player, comms/intel to all, beat camera cues) on the
-- full runtime and the DCS mock.

local function focus(x, y)
  MOCK.addGroup({
    name = "Dusty_dusty",
    coalition = 2,
    country = "USA",
    category = "helicopter",
    units = { { name = "Dusty_dusty-1", type = "UH-60A", x = x or 0, y = y or 0, alt = 150 } },
  })
end

local function config(extra)
  local c = {
    seed = 9,
    missionId = "w01",
    players = { coalition = 2 },
    budgets = { maxActiveGround = 100, maxActiveAir = 10, spawnsPerMin = 60 },
    director = { enabled = false },
    zones = { gate = { kind = "circle", x = 10000, y = 0, radius = 1000 } },
    narrative = { minGapSec = 1, zonePollSec = 1 },
    speakers = { ops = { callsign = "Magic", frequency = 251, modulation = 0 } },
    voice = { a = { file = "a.ogg", text = "Alpha", durSec = 3, speaker = "ops" } },
    watch = { enabled = true, focus = "Dusty_dusty", cues = true },
    flights = {},
    beats = {
      {
        id = "at_gate",
        when = { event = "zone.entered", zone = "gate", playersOnly = true },
        cue = "F2 on Dusty",
      },
    },
  }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

describe("watch missions", function()
  it("core: standInGroups / isWatch follow DMS_CONFIG (test proxy wins)", function()
    DMS_CONFIG = nil
    assert.is_false(DMS.isWatch())
    assert.are.same({}, DMS.standInGroups())
    DMS_CONFIG = { watch = { enabled = true, focus = "Dusty_dusty" } }
    assert.is_true(DMS.isWatch())
    assert.are.same({ "Dusty_dusty" }, DMS.standInGroups())
    assert.is_true(DMS.isStandInGroup("Dusty_dusty"))
    DMS_CONFIG.test = { enabled = true, playerProxy = "Proxy-1" }
    assert.are.same({ "Proxy-1" }, DMS.standInGroups())
    DMS_CONFIG.test.enabled = false
    assert.are.same({ "Dusty_dusty" }, DMS.standInGroups())
    assert.are.same({}, DMS.standInUnits()) -- group does not exist
  end)

  it("registers the focus flight as the player; zone beats fire and show the camera cue to all", function()
    focus(0, 0)
    DMS_CONFIG = config()
    DMS.boot()
    MOCK.advance(2)
    local p = DMS.Bus._players["Dusty_dusty-1"]
    assert.is_truthy(p)
    assert.are.equal("WATCH", p.playerName)
    assert.are.equal(1, #DMS.Spawner.playerUnits())
    MOCK.moveUnit("Dusty_dusty-1", 10000, 0)
    MOCK.advance(3)
    assert.are.equal(1, DMS.Narrative.firedCount("at_gate"))
    local c = MOCK.lastCall("trigger.action.outText")
    assert.is_truthy(c)
    assert.are.equal("CAMERA: F2 on Dusty", c.args[1])
    assert.are.equal(10, c.args[2])
  end)

  it("ignores cues when watch.cues is false or the mission is not a watch mission", function()
    focus(10000, 0)
    DMS_CONFIG = config({ watch = { enabled = true, focus = "Dusty_dusty", cues = false } })
    DMS.boot()
    MOCK.advance(5)
    assert.are.equal(1, DMS.Narrative.firedCount("at_gate"))
    assert.are.equal(0, MOCK.countCalls("trigger.action.outText"))
  end)

  it("comms: text and sound to all, radio transmitter at the focus flight", function()
    focus(5000, 7000)
    DMS_CONFIG = config({ beats = {} })
    DMS.boot()
    MOCK.advance(2)
    DMS.Comms.say("ops", "a", nil, { coalition = 2 })
    MOCK.advance(5)
    local rt = MOCK.callsTo("trigger.action.radioTransmission")
    assert.are.equal(1, #rt)
    assert.are.equal(5000, rt[1].args[2].x)
    assert.are.equal(7000, rt[1].args[2].z)
    assert.are.equal("Magic: Alpha", MOCK.lastCall("trigger.action.outText").args[1])
    assert.are.equal(0, MOCK.countCalls("trigger.action.outTextForCoalition"))
    -- no frequency: plain outSound to all
    DMS_CONFIG.speakers.ops.frequency = nil
    DMS.Comms.say("ops", "a", nil, { coalition = 2 })
    MOCK.advance(10)
    assert.are.equal("l10n/DEFAULT/a.ogg", MOCK.lastCall("trigger.action.outSound").args[1])
    assert.are.equal(0, MOCK.countCalls("trigger.action.outSoundForCoalition"))
  end)

  it("intel: marks are drawn for all coalitions (-1)", function()
    focus(0, 0)
    DMS_CONFIG = config({ beats = {} })
    DMS.boot()
    MOCK.advance(2)
    assert.is_truthy(DMS.Intel.mark("zone:gate"))
    assert.are.equal(1, MOCK.countCalls("trigger.action.markToAll"))
    assert.are.equal(0, MOCK.countCalls("trigger.action.markToCoalition"))
    for _, m in pairs(DMS.Intel.liveMarks()) do
      assert.are.equal(-1, m.coalition)
    end
  end)
end)
