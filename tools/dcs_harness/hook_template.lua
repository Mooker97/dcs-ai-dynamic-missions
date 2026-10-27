-- DMS headless test harness hook (GameGUI state).
-- GENERATED into <writedir>/Scripts/Hooks/ by tools/dcs_harness/run_mission.py. Do not edit there.
--
-- What it does:
--   * once the main menu is idle: mode "sp" starts the test mission as a single-player mission (the GUI's
--     own Fly path: START_PARAMS + __EMBEDDED__.doAction, via net.dostring_in('gui')), mode "server" starts a private local MP server (needs ED login)
--   * keeps the sim unpaused (skips the SP briefing pause), ramps time acceleration to CFG.accel (SP only)
--   * watches the log history for "[DMS.TEST] DONE" and exits DCS after it,
--     or after CFG.maxModelSec of model time, or after CFG.maxRealSec of real time.
-- Every line it writes is prefixed "[DMS.HARNESS]" so run_mission.py can follow the phases.

local CFG = __CFG__

local S = Sim or DCS
local cb = {}
local st = {
    hookLoadedAt = nil, serverCalled = false, simStarted = false, done = false, doneAt = nil,
    logIdx = 0, lastPoll = -1, lastBeat = -1, exiting = false, framesInMenu = 0,
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

local function keysOf(t)
    local ks = {}
    if type(t) ~= 'table' then return tostring(t) end
    for k in pairs(t) do ks[#ks + 1] = tostring(k) end
    table.sort(ks)
    return table.concat(ks, ',')
end

local function inGui(code)
    -- Hooks run in a sandboxed env of the GameGUI state; START_PARAMS / Gui / timer live in that state's
    -- real globals. Needs 'gui' in net.allow_dostring_in (the harness writes Config/autoexec.cfg).
    if not (net and net.dostring_in) then return nil, 'net.dostring_in unavailable' end
    local ok, res = pcall(net.dostring_in, 'gui', code)
    if not ok then return nil, res end
    return res
end

local function longL(prefix, text)
    text = tostring(text)
    for i = 1, #text, 1500 do L('%s[%d] %s', prefix, (i - 1) / 1500, text:sub(i, i + 1499)) end
end

local function probe()
    -- one-shot API inventory (what this DCS build really exposes)
    longL('PROBE DCS=', keysOf(DCS))
    longL('PROBE Export=', keysOf(Export))
    L('PROBE hook-env timer=%s START_PARAMS=%s', keysOf(rawget(_G, 'timer')), keysOf(rawget(_G, 'START_PARAMS')))
    local res, err = inGui([[
        local function ks(t) if type(t) ~= 'table' then return tostring(t) end
            local r = {} for k in pairs(t) do r[#r+1] = tostring(k) end table.sort(r) return table.concat(r, ',') end
        local sp = START_PARAMS or {}
        return 'START_PARAMS=' .. ks(START_PARAMS) .. ' | command=' .. tostring(sp.command) ..
            ' nomaingui=' .. tostring(sp.nomaingui) .. ' guiVariant=' .. tostring(guiVariant) ..
            ' | Gui.doQuit=' .. tostring(Gui and Gui.doQuit) .. ' | timer=' .. ks(timer) ..
            ' | __EMBEDDED__=' .. ks(__EMBEDDED__)
    ]])
    longL('PROBE gui-state ', tostring(res) .. ' err=' .. tostring(err))
end

local function startSinglePlayer()
    -- Same path the GUI's "Fly" button takes (MissionEditor/modules/me_mission.lua runMission):
    -- fill START_PARAMS and ask the embedded GUI to hand over to the sim with "--mission <file>".
    st.serverCalled = true
    local code = string.format([[
        if not START_PARAMS then return 'no START_PARAMS' end
        START_PARAMS.missionPath = %q
        START_PARAMS.realMissionPath = %q
        START_PARAMS.command = '--mission'
        START_PARAMS.returnScreen = 'quit'
        START_PARAMS.SupervisorRun = nil
        -- Gui.doQuit() = GUI cleanup + __EMBEDDED__.doAction(); the dxgui Gui table is not a global here
        if Gui and Gui.doQuit then Gui.doQuit() return 'ok Gui.doQuit' end
        if __EMBEDDED__ and __EMBEDDED__.doAction then __EMBEDDED__.doAction() return 'ok doAction' end
        return 'no Gui.doQuit / __EMBEDDED__.doAction'
    ]], '"' .. CFG.miz .. '"', CFG.miz)
    local res, err = inGui(code)
    L('PHASE sp_start_called res=%s err=%s miz=%s', tostring(res), tostring(err), CFG.miz)
    if not (res and res:find('^ok')) then L('ERROR sp start failed: %s %s', tostring(res), tostring(err)) end
end

local function startRun()
    if CFG.mode == 'sp' then startSinglePlayer() else startServer() end
end

if CFG.probe then pcall(probe) end

-- ---- main-menu ticker (client mode): wait a few GUI frames after the hook loads, then start ----
-- In server mode DCS's own dedicated-server GUI should autostart from serverSettings.lua; the ticker is
-- a fallback (longer delay) in case that path bails out (e.g. ED login failure).
if CFG.mode == 'client' or CFG.mode == 'server' or CFG.mode == 'sp' then
    local okUM, UpdateManager = pcall(require, 'UpdateManager')
    if okUM and UpdateManager and UpdateManager.add then
        UpdateManager.add(function()
            if st.serverCalled or st.simStarted or st.loaded then return true end
            st.framesInMenu = st.framesInMenu + 1
            st.hookLoadedAt = st.hookLoadedAt or realTime()
            if st.framesInMenu >= CFG.menuFrames and realTime() - st.hookLoadedAt >= CFG.menuDelaySec then
                L('PHASE menu_ready frames=%d', st.framesInMenu)
                startRun()
                return true
            end
            if realTime() > CFG.maxRealSec then exitNow('wall_timeout_menu') return true end
        end)
        L('PHASE hook_loaded mode=%s (UpdateManager ticker armed, delay %ss)', CFG.mode, tostring(CFG.menuDelaySec))
    else
        L('WARN UpdateManager unavailable (%s); relying on the onSimulationFrame ticker', tostring(UpdateManager))
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

local function getAcc()
    if Export and Export.LoGetModelTimeAcceleration then
        local ok, r = pcall(Export.LoGetModelTimeAcceleration) if ok then return r end
    end
    return nil
end

local ICMD_DECELERATE = 191   -- "Decelerate model time" (Alt+Z)

local function tryAccel(rt)
    -- Single-player only (MP servers ignore it). iCommand 53 "Accelerate model time" (Ctrl+Z) steps the
    -- factor up, 191 steps it down; DCS applies a press on a later frame and several presses in one
    -- frame compound unpredictably (63 presses -> x3700). So: one press per 0.15 s real time, read back
    -- Export.LoGetModelTimeAcceleration(), stop at the target. Called every frame until done.
    if (CFG.accel or 1) <= 1 or st.accelDone then return end
    if st.lastAccelPress and rt - st.lastAccelPress < 0.15 then return end
    local cur = tonumber(getAcc()) or 1
    if cur == CFG.accel then
        st.accelDone = true
        L('INFO accel reached x%s after %d presses', tostring(cur), st.accelPresses or 0)
        return
    end
    st.accelPresses = (st.accelPresses or 0) + 1
    if st.accelPresses > 3 * CFG.accel + 10 or not (Export and Export.LoSetCommand) then
        st.accelDone = true
        L('WARN accel stuck at x%s (target x%d, presses %d)', tostring(cur), CFG.accel, st.accelPresses)
        return
    end
    pcall(Export.LoSetCommand, cur < CFG.accel and CFG.accelCommand or ICMD_DECELERATE)
    st.lastAccelPress = rt
end

function cb.onSimulationFrame()
    if st.exiting then return end
    local rt = realTime()
    if st.simStarted and modelTime() > 1 then tryAccel(rt) end
    if rt - st.lastPoll < 1.0 then return end
    st.lastPoll = rt
    local mt = modelTime()

    -- onSimulationFrame also ticks while idle in the main menu (model time 0): use it as the
    -- autostart ticker (UpdateManager ticks are not reliable in every launch mode).
    if not (st.serverCalled or st.simStarted or st.loaded) then
        st.hookLoadedAt = st.hookLoadedAt or rt
        if rt - st.hookLoadedAt >= CFG.menuDelaySec then
            L('PHASE menu_ready (frame ticker) real=%.1f', rt)
            startRun()
        end
    end

    if S.getPause and S.getPause() and S.setPause then pcall(S.setPause, false) end

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
        L('BEAT model=%.1f real=%.1f acc=%s', mt, rt, tostring(getAcc()))
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
