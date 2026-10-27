-- DMS headless test harness hook (GameGUI state).
-- GENERATED into <writedir>/Scripts/Hooks/ by tools/dcs_harness/run_mission.py. Do not edit there.
--
-- What it does:
--   * (mode "client") once the main menu is up, starts a private local MP server with the test mission
--     (mode "server" relies on serverSettings.lua + DCS's own dedicated-server autostart instead)
--   * keeps the sim unpaused, optionally tries time acceleration
--   * watches the log history for "[DMS.TEST] DONE" and exits DCS after it,
--     or after CFG.maxModelSec of model time, or after CFG.maxRealSec of real time.
-- Every line it writes is prefixed "[DMS.HARNESS]" so run_mission.py can follow the phases.

local CFG = __CFG__

local S = Sim or DCS
local cb = {}
local st = {
    hookLoadedAt = nil, serverCalled = false, simStarted = false, done = false, doneAt = nil,
    logIdx = 0, lastPoll = -1, lastBeat = -1, exiting = false, accelTried = false, framesInMenu = 0,
}

local function L(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    log.write('DMS.HARNESS', log.INFO, '[DMS.HARNESS] ' .. (ok and msg or tostring(fmt)))
end

local function realTime()
    local ok, t = pcall(S.getRealTime)
    return ok and t or 0
end

local function modelTime()
    local ok, t = pcall(S.getModelTime)
    return ok and t or 0
end

local function exitNow(reason)
    if st.exiting then return end
    st.exiting = true
    L('EXIT reason=%s model=%.1f real=%.1f', reason, modelTime(), realTime())
    pcall(S.exitProcess)
end

local function inMission(code)
    -- Runs code in the mission scripting env. Needs Config/autoexec.cfg to allow it (the harness writes that).
    if not (net and net.dostring_in) then return nil, 'net.dostring_in unavailable' end
    local ok, res = pcall(net.dostring_in, 'mission', 'return a_do_script(' .. string.format('%q', code) .. ')')
    if not ok then return nil, res end
    return res
end

local function startServer()
    st.serverCalled = true
    local ok, err = pcall(function()
        local s = net.get_default_server_settings()
        s.missionList = { CFG.miz }
        s.listStartIndex = 1
        s.listLoop = false
        s.listShuffle = false
        s.isPublic = false
        s.name = 'DMS harness (private)'
        s.description = 'automated test run'
        s.password = CFG.password
        s.maxPlayers = 2
        s.port = CFG.port
        s.advanced = s.advanced or {}
        s.advanced.resume_mode = 1          -- 1 = run on mission load (no players needed)
        s.advanced.pause_on_load = false
        s.advanced.pause_without_clients = false
        s.advanced.voice_chat_server = false
        local res = net.start_server(s)
        L('PHASE server_start_called res=%s', tostring(res))
    end)
    if not ok then L('ERROR start_server failed: %s', tostring(err)) end
end

-- ---- main-menu ticker (client mode): wait a few GUI frames after the hook loads, then start ----
-- In server mode DCS's own dedicated-server GUI should autostart from serverSettings.lua; the ticker is
-- a fallback (longer delay) in case that path bails out (e.g. ED login failure).
if CFG.mode == 'client' or CFG.mode == 'server' then
    local okUM, UpdateManager = pcall(require, 'UpdateManager')
    if okUM and UpdateManager and UpdateManager.add then
        UpdateManager.add(function()
            if st.serverCalled or st.simStarted or st.loaded then return true end
            st.framesInMenu = st.framesInMenu + 1
            st.hookLoadedAt = st.hookLoadedAt or realTime()
            if st.framesInMenu >= CFG.menuFrames and realTime() - st.hookLoadedAt >= CFG.menuDelaySec then
                L('PHASE menu_ready frames=%d', st.framesInMenu)
                startServer()
                return true
            end
            if realTime() > CFG.maxRealSec then exitNow('wall_timeout_menu') return true end
        end)
        L('PHASE hook_loaded mode=%s (UpdateManager ticker armed, delay %ss)', CFG.mode, tostring(CFG.menuDelaySec))
    else
        L('ERROR UpdateManager unavailable (%s); falling back to immediate start_server', tostring(UpdateManager))
        startServer()
    end
else
    L('PHASE hook_loaded mode=%s', tostring(CFG.mode))
end

-- ---- simulation callbacks ----
function cb.onMissionLoadBegin() L('PHASE mission_load_begin') end

function cb.onMissionLoadEnd()
    st.loaded = true
    L('PHASE mission_loaded name=%s', tostring(S.getMissionName and S.getMissionName()))
    -- Avoid modal "script error" boxes in unattended runs (errors still go to dcs.log).
    local res, err = inMission('env.setErrorMessageBoxEnabled(false)')
    L('INFO errorbox_disable res=%s err=%s', tostring(res), tostring(err))
    if CFG.injectLua and CFG.injectLua ~= '' then
        res, err = inMission(CFG.injectLua)
        L('INFO inject res=%s err=%s', tostring(res), tostring(err))
    end
end

function cb.onSimulationStart()
    st.simStarted = true
    L('PHASE sim_start mission=%s multiplayer=%s server=%s',
        tostring(S.getMissionName and S.getMissionName()), tostring(S.isMultiplayer and S.isMultiplayer()),
        tostring(S.isServer and S.isServer()))
end

local function tryAccel()
    st.accelTried = true
    if (CFG.accelSteps or 0) <= 0 then return end
    if not (Export and Export.LoSetCommand) then
        L('WARN accel requested but Export.LoSetCommand unavailable')
        return
    end
    for _ = 1, CFG.accelSteps do pcall(Export.LoSetCommand, CFG.accelCommand) end
    L('INFO accel requested steps=%d cmd=%d', CFG.accelSteps, CFG.accelCommand)
end

function cb.onSimulationFrame()
    if st.exiting then return end
    local rt = realTime()
    if rt - st.lastPoll < 1.0 then return end
    st.lastPoll = rt
    local mt = modelTime()

    -- onSimulationFrame also ticks while idle in the main menu (model time 0): use it as the
    -- autostart ticker (UpdateManager ticks are not reliable in every launch mode).
    if not (st.serverCalled or st.simStarted or st.loaded) then
        st.hookLoadedAt = st.hookLoadedAt or rt
        if rt - st.hookLoadedAt >= CFG.menuDelaySec then
            L('PHASE menu_ready (frame ticker) real=%.1f', rt)
            startServer()
        end
    end

    if S.getPause and S.getPause() and S.setPause then pcall(S.setPause, false) end
    if not st.accelTried and mt > 1 then tryAccel() end

    if S.getLogHistory then
        local ok, hist, idx = pcall(S.getLogHistory, st.logIdx)
        if ok then
            st.logIdx = idx or st.logIdx
            for _, rec in ipairs(hist or {}) do
                local msg = type(rec) == 'table' and tostring(rec[4] or rec.message or '') or tostring(rec)
                if not st.done and msg:find('[DMS.TEST] DONE', 1, true) then
                    st.done = true
                    st.doneAt = rt
                    L('PHASE done_seen model=%.1f', mt)
                end
            end
        end
    end

    if rt - st.lastBeat >= 30 then
        st.lastBeat = rt
        L('BEAT model=%.1f real=%.1f', mt, rt)
    end
    if st.done and rt - st.doneAt >= CFG.graceSec then exitNow('done') return end
    if mt >= CFG.maxModelSec then exitNow('model_timeout') return end
    if rt >= CFG.maxRealSec then exitNow('wall_timeout') return end
end

function cb.onSimulationStop()
    L('PHASE sim_stop model=%.1f started=%s', modelTime(), tostring(st.simStarted))
    -- DCS fires a Start/Stop pair for its empty boot scene; only a stop after our sim_start counts.
    if st.simStarted and not st.exiting then exitNow('sim_stopped') end
end

function cb.onGameEvent(name, a1, a2)
    if name == 'mission_end' then
        L('PHASE mission_end winner=%s msg=%s', tostring(a1), tostring(a2))
        exitNow('mission_end')
    end
end

function cb.onServerRegistrationFail(code)
    L('WARN server registration fail code=%s (harmless for private runs)', tostring(code))
end

S.setUserCallbacks(cb)
