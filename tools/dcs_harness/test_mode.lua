-- DMS.Test: tiny in-mission assertion API for headless DCS runs (tools/dcs_harness).
-- Lua 5.1, mission scripting env (no os/io/require). Safe to load when not testing: does nothing
-- until DMS.Test.expect/check/done is called.
--
-- DMS missions do NOT need this file: the runtime bundles DMS.Test (lua/src/dms/test.lua, with the
-- player proxy and declarative DMS_CONFIG.test.checks). Keep this standalone copy only for
-- non-DMS smoke missions loaded with a separate DO SCRIPT FILE.
--
-- Log protocol (parsed by tools/dcs_harness/run_mission.py):
--   [DMS.TEST] PASS <name> <detail>
--   [DMS.TEST] FAIL <name> <detail>
--   [DMS.TEST] SKIP <name> <detail>
--   [DMS.TEST] INFO <name> <detail>
--   [DMS.TEST] DONE <passed>/<total>        -- the harness exits DCS a few seconds after this
-- <name> must not contain spaces.
--
-- API:
--   DMS.Test.pass(name, detail) / fail(name, detail) / info(name, detail)
--   DMS.Test.check(name, cond, detail)                 -- immediate assertion
--   DMS.Test.expect(name, fn, deadlineSec, opts)       -- poll fn() every opts.interval (default 2 s)
--        until it returns truthy (PASS, with its 2nd return value as detail) or deadlineSec of model
--        time elapses (FAIL "timeout"). fn errors count as not-yet. opts.negate = true inverts it:
--        PASS if fn never became truthy before the deadline.
--   DMS.Test.done()                                    -- log DONE now (normally automatic, see below)
--   DMS.Test.autoDone(graceSec)                        -- log DONE when every expectation resolved
--        (called automatically by the first expect(); set DMS.Test.manualDone = true to disable)
--
-- "Player proxy" convention for headless runs (no human in the cockpit):
--   DMS_CONFIG.test = { playerProxy = "<AI group name>" }
--   Runtime modules that need "the player" (proximity triggers, director intensity, intel reveal,
--   player.spawned bus event) should call DMS.Test.playerGroups(realList) which returns the proxy
--   group when configured, else realList unchanged. DMS.Test.emitProxySpawn() emits a synthetic
--   "player.spawned" on DMS.Bus for the proxy's units, so modules that wait for a player start.

DMS = DMS or {}
DMS.Test = DMS.Test or {}
local T = DMS.Test

T._pending = T._pending or 0
T._total = T._total or 0
T._passed = T._passed or 0
T._done = T._done or false

local function now() return timer.getTime() end

local function log(status, name, detail)
    local safeName = (tostring(name or '-'):gsub('%s', '_'))
    env.info(string.format('[DMS.TEST] %s %s %s', status, safeName, tostring(detail or '')))
end

local function schedule(fn, delay)
    -- prefer DMS.Clock (contract: the only module allowed to schedule) when present
    if DMS.Clock and DMS.Clock.after then return DMS.Clock.after(delay, fn) end
    return timer.scheduleFunction(function() fn() return nil end, nil, now() + delay)
end

function T.pass(name, detail) T._total = T._total + 1; T._passed = T._passed + 1; log('PASS', name, detail) end
function T.fail(name, detail) T._total = T._total + 1; log('FAIL', name, detail) end
function T.skip(name, detail) log('SKIP', name, detail) end
function T.info(name, detail) log('INFO', name, detail) end

function T.check(name, cond, detail)
    if cond then T.pass(name, detail) else T.fail(name, detail or 'check failed') end
    return cond and true or false
end

function T.done()
    if T._done then return end
    T._done = true
    log('DONE', string.format('%d/%d', T._passed, T._total), '')
end

function T.autoDone(graceSec)
    if T._autoArmed or T.manualDone then return end
    T._autoArmed = true
    local function tick()
        if T._done then return end
        if T._pending <= 0 then
            schedule(T.done, graceSec or 2)
        else
            schedule(tick, 2)
        end
    end
    schedule(tick, 2)
end

function T.expect(name, fn, deadlineSec, opts)
    opts = opts or {}
    local interval = opts.interval or 2
    local deadline = now() + (deadlineSec or 60)
    T._pending = T._pending + 1
    local function resolve(ok, detail)
        T._pending = T._pending - 1
        if ok then T.pass(name, detail) else T.fail(name, detail) end
    end
    local function poll()
        local okCall, res, detail = pcall(fn)
        local hit = okCall and res
        if opts.negate then
            if hit then resolve(false, 'became true: ' .. tostring(detail or '')) return end
            if now() >= deadline then resolve(true, 'stayed false') return end
        else
            if hit then resolve(true, detail or string.format('t=%.0f', now())) return end
            if now() >= deadline then
                resolve(false, 'timeout' .. (okCall and '' or (' last error: ' .. tostring(res))))
                return
            end
        end
        schedule(poll, interval)
    end
    schedule(poll, 0.5)
    T.autoDone()
end

-- ---- player proxy ----
function T.proxyName()
    return DMS_CONFIG and DMS_CONFIG.test and DMS_CONFIG.test.playerProxy or nil
end

function T.isProxyRun() return T.proxyName() ~= nil end

function T.playerGroups(realList)
    local n = T.proxyName()
    if not n then return realList end
    local g = Group.getByName(n)
    if g and g:isExist() then return { g } end
    return realList
end

function T.emitProxySpawn()
    local n = T.proxyName()
    if not (n and DMS.Bus and DMS.Bus.emit) then return false end
    local g = Group.getByName(n)
    if not (g and g:isExist()) then T.info('proxy', 'group not found: ' .. n) return false end
    for _, u in ipairs(g:getUnits()) do
        DMS.Bus.emit('player.spawned', {
            unit = u:getName(), group = n, groupId = g:getID(), playerName = 'PROXY',
            coalition = g:getCoalition(), typeName = u:getTypeName(),
        })
    end
    T.info('proxy', 'emitted player.spawned for ' .. n)
    return true
end

-- Unattended runs: no modal error boxes (errors still reach dcs.log).
if env.setErrorMessageBoxEnabled then pcall(env.setErrorMessageBoxEnabled, false) end
