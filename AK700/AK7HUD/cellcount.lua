-- /WIDGETS/AK7HUD/cellcount.lua
--
-- Battery cell-count confirmation for the KSE4 widget (EdgeTX).
--
-- Why this exists: RotorFlight derives the cell count from the pack voltage
-- with a fixed table that stops at 12S (src/main/sensors/battery.c), so 13S and
-- 14S packs fall back to "1 cell" and the low-voltage alarms are then computed
-- for a 1S pack.  The firmware cannot be asked for a cell count, so this module
-- asks the pilot once per pack change and writes the confirmed value back over
-- standard MSP.
--
-- Only standard RotorFlight 4.6.0 commands are used, so the same code works
-- against stock firmware on other models:
--    32  MSP_BATTERY_CONFIG       read the battery configuration
--    33  MSP_SET_BATTERY_CONFIG   write it back (cell count / capacity)
--   130  MSP_BATTERY_STATE        read the *applied* cell count (verify)
--   250  MSP_EEPROM_WRITE         persist
--    68  MSP_REBOOT                stock firmware re-applies on next power-up
--
-- Loaded lazily from main.lua; see cellcount.md for the operation notes.

local M = {}

local BATTERY_CONFIG     = 32
local BATTERY_CONFIG_SET = 33
local BATTERY_STATE = 130
local EEPROM_WRITE  = 250
local REBOOT        = 68

local MAX_CELLS       = 14
-- Candidate window.  Wide enough that a deep-discharged pack (3.4 V/cell) still
-- lists its true cell count, narrow enough that the list stays short.  The menu
-- shows the implied V/cell next to every entry so the pilot can sanity-check.
local DETECT_MIN_MV   = 3400
local DETECT_MAX_MV   = 4300
local TARGET_MV       = 3900   -- order candidates by closeness to this
-- Pack-swap detection.  With a separate BEC the controller stays powered
-- through a battery change, so nothing re-triggers the selection by itself.
local PACK_ABSENT_MV  = 5000    -- below this the pack is considered unplugged
local PACK_PRESENT_MV = 10000   -- above this a pack is connected
local ABSENT_MIN_MS   = 50      -- centiseconds (EdgeTX getTime unit)
local PRESENT_MIN_MS  = 80

-- Voltage alarm.  Stored per model as a per-cell threshold so it follows the
-- pack: 3.60 V/cell is 21.6 V on a 6S and 50.4 V on a 14S.
local ALARM_DEFAULT_CELL_MV = 3600
local ALARM_MIN_CELL_MV     = 3000
local ALARM_MAX_CELL_MV     = 3900
local ALARM_STEP_MV         = 50
local ALARM_HOLD_MS         = 500   -- 5 s
local ALARM_REPEAT_MS       = 500   -- repeat the voice every 5 s
local ALARM_RESET_MV        = 500
local ALARM_SOUND           = "rf-lowcell.wav"
local ANNOUNCE_PERIOD_MS    = 2000  -- routine per-cell call-out every 20 s
local RPM_MIN               = 500    -- alarms and call-outs need the rotor turning (rpm, not time)
local REARM_ABSENT_MS       = 400   -- pack gone 4 s to re-arm
local REARM_COOLDOWN_MS     = 3000  -- 30 s after a prompt
local MAX_ENTRIES     = 5

-- ---------------------------------------------------------------- diagnostics
-- Runtime log, flushed to /WIDGETS/AK7HUD/cells_log.txt.  Written with the
-- function-form io API (handle methods are not supported by EdgeTX).

local LOG_PATH = "/WIDGETS/AK7HUD/cells_log.txt"
local logLines = {}
local logFlushAt = 0

function M.logFlush()
    local text = table.concat(logLines, "\n")
    if text ~= "" then text = text .. "\n" end
    local f = io.open(LOG_PATH, "w")
    if not f then return false end
    local ok, result = pcall(io.write, f, text)
    pcall(io.close, f)
    return ok and result ~= nil and result ~= false
end

function M.log(deps, text)
    pcall(function()
        local now = (deps and deps.now and deps.now()) or 0
        if #logLines >= 150 then table.remove(logLines, 1) end
        logLines[#logLines + 1] = string.format("%7d  %s", math.floor(now), tostring(text))
        if now >= logFlushAt then
            logFlushAt = now + 400
            pcall(M.logFlush)
        end
    end)
end

-- ----------------------------------------------------------------- pure logic

-- Cell counts that a pack of this voltage can plausibly have, closest to
-- 3.9 V/cell first.  With 6/7/12/13/14S packs every real cell count lands in
-- this window, so the correct answer is always offered; the pilot confirms it.
function M.candidates(voltageMv)
    local list = {}
    local v = tonumber(voltageMv)
    if not v or v <= 0 then return list end

    local scored = {}
    for n = 1, MAX_CELLS do
        local per = v / n
        if per >= DETECT_MIN_MV and per <= DETECT_MAX_MV then
            scored[#scored + 1] = { cells = n, delta = math.abs(per - TARGET_MV) }
        end
    end

    table.sort(scored, function(a, b) return a.delta < b.delta end)
    for i = 1, math.min(#scored, MAX_ENTRIES) do
        list[#list + 1] = scored[i].cells
    end

    -- Keep the list in ascending order for a predictable menu.
    table.sort(list)
    return list
end

function M.pickDefault(list, last)
    for _, n in ipairs(list or {}) do
        if n == last then return n end
    end
    return (list and list[1]) or nil
end

function M.label(n, voltageMv)
    local v = tonumber(voltageMv) or 0
    if v <= 0 then return tostring(n) .. " cells" end
    return string.format("%d  (%.2f V/cell)", n, v / n / 1000)
end

function M.sanitize(name)
    local s = string.gsub(tostring(name or ""), "[^%w%-_]", "_")
    if #s == 0 then s = "model" end
    return s
end

-- --------------------------------------------------------------- state file

local function statePath(deps)
    return "/WIDGETS/AK7HUD/cells_" .. M.sanitize(deps.modelName()) .. ".cfg"
end

-- EdgeTX's io library is function based: f:read()/f:write()/f:lines() are not
-- supported, io.read(f, n) and io.write(f, s) are.  Use those (same as KSE4).
function M.readAll(path, maxBytes)
    local f = io.open(path, "r")
    if not f then return nil, "open-nil" end
    local ftype = type(f)
    if ftype == "string" then return f, "string" end
    if ftype ~= "number" and ftype ~= "userdata" then return nil, ftype end
    local parts, total = {}, 0
    pcall(function()
        while true do
            local chunk = io.read(f, 512)
            if chunk == nil or chunk == "" then break end
            total = total + #chunk
            parts[#parts + 1] = chunk
            if #chunk < 512 or total >= (maxBytes or 4096) then break end
        end
    end)
    pcall(io.close, f)
    return table.concat(parts), ftype
end

function M.writeAll(path, text)
    local f = io.open(path, "w")
    if not f then return false end
    local ok, result = pcall(io.write, f, text or "")
    local closed = pcall(io.close, f)
    return ok and result ~= nil and result ~= false and closed
end

function M.loadState(deps)
    local st = {}
    local ok, text, how = pcall(M.readAll, statePath(deps), 2048)
    st.__how = tostring(how)
    st.__ok = tostring(ok)
    if not ok or type(text) ~= "string" or text == "" then return st end
    pcall(function()
        for line in string.gmatch(text, "[^\r\n]+") do
            local k, v = string.match(line, "^%s*([%w_]+)%s*=%s*(%-?%d+)%s*$")
            if k then st[k] = tonumber(v) end
        end
    end)
    return st
end

function M.saveState(deps, st)
    local ok, result = pcall(function()
        local parts = {}
        if st.cells then parts[#parts + 1] = "cells=" .. tostring(st.cells) end
        if st.capacity then parts[#parts + 1] = "capacity=" .. tostring(st.capacity) end
        if st.alarm then parts[#parts + 1] = "alarm=" .. tostring(st.alarm) end
        return M.writeAll(statePath(deps), table.concat(parts, "\n") .. "\n")
    end)
    return ok and result or false
end

-- ------------------------------------------------------------------ helpers

local function notice(deps, wgt, text, color)
    if deps.setMessage then deps.setMessage(wgt, text, color) end
    if deps.setNotice then deps.setNotice(wgt, "BATTERY CELLS", text, color, 300, true) end  -- 3 s (centiseconds)
end

-- -------------------------------------------------------------------- apply

-- Read the battery config, set the cell count (and, when given, the active
-- profile capacity), write it back, persist, then verify what the controller
-- actually applied.  Stock firmware only re-runs detection at power-up, so a
-- mismatch triggers one soft reboot and a re-check.
local function applyCells(ctx, wgt, cells, capacity)
    local deps = ctx.deps
    local queue = deps.getQueue()
    if not queue or type(queue.add) ~= "function" then
        notice(deps, wgt, "RF TOOL NOT READY", deps.colors.red)
        M.log(deps, "  apply: no queue")
        return false
    end

    ctx.verifyPending = nil
    notice(deps, wgt, "WRITING " .. tostring(cells) .. " CELLS...", deps.colors.yellow)

    local function finish(text, color, ok)
        notice(deps, wgt, text, color)
        if ok then
            ctx.state.cells = cells
            if capacity and capacity > 0 then ctx.state.capacity = capacity end
            M.saveState(deps, ctx.state)
        end
    end

    local function verify()
        queue:add({
            command = BATTERY_STATE,
            processReply = function(_, buf)
                local reported = tonumber(type(buf) == "table" and buf[2] or nil)
                if reported == cells then
                    finish(tostring(cells) .. " CELLS OK", deps.colors.green, true)
                else
                    -- Saved, but the controller only re-applies the cell count
                    -- when the pack is reconnected (batteryUpdatePresence()).
                    -- Do NOT reboot here: a controller reboot leaves the menu
                    -- orphaned and the next selection goes nowhere.
                    ctx.verifyPending = cells
                    ctx.verifyAt = (deps.now() or 0) + 6000   -- 60 s
                    finish(tostring(cells) .. " CELLS SAVED - REPLUG PACK TO APPLY",
                           deps.colors.yellow, true)
                end
            end,
            errorHandler = function()
                finish("CELL COUNT VERIFY FAILED", deps.colors.red, false)
            end,
        })
    end

    local function persist()
        queue:add({
            command = EEPROM_WRITE,
            processReply = function() verify() end,
            errorHandler = function() finish("SAVE FAILED (DISARM?)", deps.colors.red, false) end,
        })
    end

    -- Raw MSP instead of the RF2 wrapper: the wrapper's read/write shape
    -- differs between RF Tool versions and silently did nothing here.
    -- MSP 32 reply: u16 activeCapacity, u8 cellCount, u8 vbatSrc, u8 currSrc,
    --   u16 min, u16 max, u16 full, u16 warn, u8 lvc%, u8 consumption%,
    --   then 6 x u16 profile capacities  (27 bytes).
    M.log(deps, "  apply: reading MSP 32")
    queue:add({
        command = BATTERY_CONFIG,          -- 32
        processReply = function(_, buf)
            local payload = {}
            if type(buf) == "table" then
                for i = 1, #buf do payload[i] = tonumber(buf[i]) or 0 end
            end
            if #payload < 3 then
                M.log(deps, "  apply: MSP32 too short (" .. tostring(#payload) .. ")")
                finish("CONFIG READ FAILED", deps.colors.red, false)
                return
            end
            payload[3] = cells
            if capacity and capacity > 0 then
                payload[1] = capacity % 256
                payload[2] = math.floor(capacity / 256) % 256
            end
            M.log(deps, string.format("  apply: MSP32 len=%d -> MSP33 cells=%d cap=%s",
                #payload, cells, tostring(capacity)))
            queue:add({
                command = BATTERY_CONFIG_SET,   -- 33
                payload = payload,
                processReply = function() persist() end,
                errorHandler = function() finish("WRITE FAILED", deps.colors.red, false) end,
            })
        end,
        errorHandler = function() finish("CONFIG READ FAILED", deps.colors.red, false) end,
    })

    return true
end

-- Capacity picker.  Uses the profile capacities KSE4 already read from the
-- controller, and writes the chosen value through MSP 33, so it does not
-- depend on KSE4 allowing a profile switch.
local function showCapacityMenu(ctx, wgt)
    local caps = type(wgt) == "table" and wgt.profileCapacities or nil
    local values, map = {}, {}
    for i = 1, 6 do
        local c = caps and tonumber(caps[i]) or nil
        if c and c > 0 then
            values[#values + 1] = string.format("%d mAh", math.floor(c))
            map[#map + 1] = math.floor(c)
        end
    end
    values[#values + 1] = "KEEP"
    if #values <= 1 then return nil end

    local defaultIndex = #values
    local current = tonumber(ctx.state.capacity) or 0
    for i, c in ipairs(map) do if c == current then defaultIndex = i break end end

    if not lvgl or type(lvgl.menu) ~= "function" then return nil end
    ctx.pickedCapacity = nil
    pcall(lvgl.menu, {
        title = "BATTERY CAPACITY",
        values = values,
        get = function() return defaultIndex end,
        set = function(selection)
            local i = tonumber(selection)
            if i and map[i] then ctx.pickedCapacity = map[i] end
        end,
    })
    return ctx.pickedCapacity
end

-- ------------------------------------------------------------------- prompt

-- Forward declaration: the cells menu's async callback opens the alarm menu,
-- which is defined further down.
local showAlarmMenu

local function showCellsMenu(ctx, wgt)
    local deps = ctx.deps
    local voltage = tonumber(deps.voltageMv()) or 0
    local list = M.candidates(voltage)

    if #list == 0 then
        notice(deps, wgt, "NO PACK VOLTAGE - CELLS NOT CONFIRMED", deps.colors.yellow)
        return
    end

    local values = {}
    for i, n in ipairs(list) do values[i] = M.label(n, voltage) end
    values[#values + 1] = "SKIP"

    local defaultIndex = 1
    local preferred = M.pickDefault(list, ctx.state.cells)
    for i, n in ipairs(list) do
        if n == preferred then defaultIndex = i break end
    end

    if not lvgl or type(lvgl.menu) ~= "function" then return end

    M.log(ctx.deps, string.format("  show BATTERY CELLS menu (%d items, v=%d, highlighted=%s)",
        #values, tonumber(ctx.deps.voltageMv()) or 0, tostring(defaultIndex)))
    -- lvgl.menu is asynchronous: it returns immediately and calls set() when
    -- the pilot picks.  Everything after the choice has to happen in set().
    pcall(lvgl.menu, {
        title = "BATTERY CELLS",
        values = values,
        get = function() return defaultIndex end,
        set = function(selection)
            local index = tonumber(selection)
            local chosen = (index and list[index]) or nil
            M.log(deps, "  cells chosen: " .. tostring(chosen))
            if wgt then
                wgt.cellsIgnoreTapUntil = (deps.now() or 0) + 150
                wgt.cellsPromptLockAt = (deps.now() or 0) + 60
            end
            if chosen then
                -- Reflect the choice immediately so the alarm step and every
                -- later display use the new count, not the stale telemetry.
                ctx.state.cells = chosen
                local ok, err = pcall(applyCells, ctx, wgt, chosen, nil)
                if not ok then M.log(deps, "  apply ERROR: " .. tostring(err)) end
            end
            local target = chosen or tonumber(ctx.state.cells)
            if not target and deps.cellsNow then target = deps.cellsNow() end
            M.log(deps, "  alarm target cells: " .. tostring(target))
            if target then
                -- Open the next step directly.  Scheduling it through the
                -- service loop silently did nothing on this radio.
                M.log(deps, "  opening alarm step now")
                local okAlarm, alarmErr = pcall(showAlarmMenu, ctx, wgt)
                if not okAlarm then
                    M.log(deps, "  alarm menu ERROR: " .. tostring(alarmErr))
                end
            end
        end,
    })
end

-- ------------------------------------------------------------------- alarm

local function alarmTotal(cells, cellMv)
    if not cells or cells < 1 then return 0 end
    return cells * cellMv
end

local function showAlarmPicker(ctx, wgt)
    local deps = ctx.deps
    local cells = tonumber(ctx.state.cells) or 0
    local current = tonumber(ctx.state.alarm) or ALARM_DEFAULT_CELL_MV
    local values, map = {}, {}
    for mv = ALARM_MIN_CELL_MV, ALARM_MAX_CELL_MV, ALARM_STEP_MV do
        map[#map + 1] = mv
        if cells > 0 then
            values[#values + 1] = string.format("%.2f V/cell  (%.1f V)", mv / 1000, alarmTotal(cells, mv) / 1000)
        else
            values[#values + 1] = string.format("%.2f V/cell", mv / 1000)
        end
    end
    values[#values + 1] = "SKIP"
    local defaultIndex = 1
    for i, mv in ipairs(map) do if mv == current then defaultIndex = i break end end
    if not lvgl or type(lvgl.menu) ~= "function" then return end
    pcall(lvgl.menu, {
        title = "ALARM CELL VOLTAGE",
        values = values,
        get = function() return defaultIndex end,
        set = function(selection)
            local index = tonumber(selection)
            local mv = index and map[index] or nil
            if not mv then return end
            ctx.state.alarm = mv
            M.saveState(deps, ctx.state)
            if cells > 0 then
                notice(deps, wgt, string.format("ALARM %.2f V/cell (%.1f V)",
                       mv / 1000, alarmTotal(cells, mv) / 1000), deps.colors.green)
            else
                notice(deps, wgt, string.format("ALARM %.2f V/cell", mv / 1000), deps.colors.green)
            end
        end,
    })
end

-- After the cell count step: show the current alarm threshold, offer a change.
showAlarmMenu = function(ctx, wgt)
    local deps = ctx.deps
    local cells = tonumber(ctx.state.cells) or 0
    if cells == 0 and ctx.deps.cellsNow then cells = ctx.deps.cellsNow() or 0 end
    local current = tonumber(ctx.state.alarm) or ALARM_DEFAULT_CELL_MV
    local keep
    if cells > 0 then
        keep = string.format("KEEP %.2f V/cell  (%.1f V)", current / 1000, alarmTotal(cells, current) / 1000)
    else
        keep = string.format("KEEP %.2f V/cell", current / 1000)
    end
    local values = { keep, "CHANGE..." }
    if not lvgl or type(lvgl.menu) ~= "function" then
        M.log(deps, "  alarm menu unavailable: lvgl.menu missing")
        return
    end
    M.log(deps, string.format("  show BATTERY ALARM menu (cells=%d alarm=%d)", cells, current))
    local ok, err = pcall(lvgl.menu, {
        title = "BATTERY ALARM",
        values = values,
        get = function() return 1 end,
        set = function(selection)
            if tonumber(selection) == 2 then showAlarmPicker(ctx, wgt) end
        end,
    })
    if not ok then M.log(deps, "  alarm menu ERROR: " .. tostring(err)) end
end

-- Alarm announcement.  The pilot needs the per-cell value, not the pack total:
-- reading 3.52 V/cell is immediate, dividing 49.3 V by 14 in your head is not.
-- Speaks one per-cell value, e.g. "3.57 volts".
local function speakCells(perCellMv)
    pcall(function()
        local unit = rawget(_G, "UNIT_VOLTS") or 0
        if type(playNumber) == "function" and perCellMv > 0 then
            -- 357 x 10 mV with two decimals -> "3.57 volts"
            playNumber(math.floor(perCellMv / 10), unit, 0, 0, 2)
        elseif type(playFile) == "function" then
            playFile(ALARM_SOUND)
        end
    end)
end

local function playAlarm(deps, wgt, threshold, cells, volts)
    local perCellMv = (cells > 0) and (volts / cells) or 0
    local text = string.format("%.2f V/cell   %.1f V / %dS", perCellMv / 1000, volts / 1000, cells)
    if deps.setMessage then deps.setMessage(wgt, text, deps.colors.red) end
    if deps.setNotice then deps.setNotice(wgt, "LOW VOLTAGE", text, deps.colors.red, 400, false) end  -- 4 s (centiseconds)
    speakCells(perCellMv)
end

-- ---------------------------------------------------------------- public API

function M.new(deps)
    local okState, loadedState = pcall(M.loadState, deps)
    local ctx = {
        deps = deps,
        state = (okState and type(loadedState) == "table") and loadedState or {},
        verifyPending = nil,
        verifyAt = 0,
        svcCount = 0,
        stateError = (not okState) and tostring(loadedState) or nil,
    }
    M.log(deps, string.format("new: model=%s cells=%s alarm=%s cap=%s stateErr=%s",
        tostring(deps.modelName and deps.modelName() or "?"),
        tostring(ctx.state.cells), tostring(ctx.state.alarm), tostring(ctx.state.capacity),
        tostring(ctx.stateError) .. " read=" .. tostring(ctx.state.__ok) .. "/" .. tostring(ctx.state.__how)))

    local api = {}

    -- Show the confirmation menu.  Blocking, exactly like the profile menu.
    function api.prompt(wgt)
        local voltsNow = tonumber(deps.voltageMv()) or 0
        if voltsNow < PACK_PRESENT_MV then
            M.log(deps, string.format("prompt skipped: v=%d (no pack)", voltsNow))
            return false
        end
        ctx.lastPromptAt = deps.now() or 0
        local unsafeNow = false
        if deps.unsafe then unsafeNow = (deps.unsafe(wgt) == true) end
        M.log(deps, string.format("prompt: v=%d caps=%s unsafe=%s",
            tonumber(deps.voltageMv()) or 0,
            tostring(type(wgt) == "table" and wgt.profileCapacities ~= nil), tostring(unsafeNow)))
        if ctx.nextStep == "alarm" then
            ctx.nextStep = nil
            M.log(deps, "  prompt: alarm step")
            if wgt then wgt.cellsPromptLockAt = (deps.now() or 0) + 800 end
            local ok, err = pcall(showAlarmMenu, ctx, wgt)
            if not ok then M.log(deps, "  alarm menu ERROR: " .. tostring(err)) end
            return true
        end
        -- The menu is async; its set() callback applies the count and then
        -- asks for the alarm step, so nothing else is needed here.
        local okMenu, err = pcall(showCellsMenu, ctx, wgt)
        if not okMenu then M.log(deps, "  cells menu ERROR: " .. tostring(err)) end
        return true
    end

    -- Called every service pass: pack-swap detection + post-reboot verification.
    function api.service(wgt)
        local now = deps.now() or 0
        local volts = tonumber(deps.voltageMv()) or 0
        ctx.svcCount = (ctx.svcCount or 0) + 1
        if ctx.svcCount % 20 == 1 then
            local unsafeNow = false
            if deps.unsafe then unsafeNow = (deps.unsafe(wgt) == true) end
            M.log(deps, string.format("svc#%d v=%d cells=%s alarm=%s unsafe=%s armed=%s dlg=%s pending=%s",
                ctx.svcCount, volts, tostring(ctx.state.cells), tostring(ctx.state.alarm),
                tostring(unsafeNow), tostring(deps.cellsNow and deps.cellsNow() or nil), tostring(wgt and wgt.profileDialog ~= nil),
                tostring(wgt and wgt.cellsPromptPending)))
        end

        -- Sustained low voltage alarm (per-cell threshold x confirmed cells).
        -- With no saved value, follow what the controller auto-detected.
        local cells = tonumber(ctx.state.cells) or 0
        if cells == 0 and deps.cellsNow then cells = tonumber(deps.cellsNow()) or 0 end
        local cellAlarm = tonumber(ctx.state.alarm) or ALARM_DEFAULT_CELL_MV
        local rpm = 0
        if deps.rotorRpm then rpm = tonumber(deps.rotorRpm()) or 0 end
        local rotorTurning = rpm >= RPM_MIN
        if cells > 0 and volts > PACK_PRESENT_MV and rotorTurning then
            local threshold = alarmTotal(cells, cellAlarm)
            if volts < threshold then
                if not ctx.alarmSince then ctx.alarmSince = now end
                if (now - ctx.alarmSince) >= ALARM_HOLD_MS
                        and (not ctx.alarmAt or (now - ctx.alarmAt) >= ALARM_REPEAT_MS) then
                    ctx.alarmAt = now
                    playAlarm(deps, wgt, threshold, cells, volts)
                end
            elseif volts > threshold + ALARM_RESET_MV then
                ctx.alarmSince = nil
                ctx.alarmAt = nil
            end
        else
            ctx.alarmSince = nil
            ctx.alarmAt = nil
        end

        -- Routine call-out: while airborne, speak the per-cell voltage every
        -- ANNOUNCE_PERIOD_MS.  The low-voltage alarm owns the airtime when the
        -- pack is below the threshold, and the cadence restarts on take-off.
        local flying = rotorTurning
        if flying and cells > 0 and volts > PACK_PRESENT_MV then
            if volts < alarmTotal(cells, cellAlarm) then
                ctx.announceAt = nil
            elseif not ctx.announceAt then
                ctx.announceAt = now
            elseif (now - ctx.announceAt) >= ANNOUNCE_PERIOD_MS then
                ctx.announceAt = now
                speakCells(volts / cells)
            end
        else
            ctx.announceAt = nil
        end

        -- No automatic prompts: the menus open only when the pilot taps the
        -- battery bar.  Cell count falls back to the controller-detected value
        -- and the alarm threshold to the last saved setting.

        -- The stored value is applied by the controller only when the pack is
        -- reconnected, so poll every 2 s and confirm as soon as it happens.
        if not ctx.verifyPending then return end
        if ctx.verifyAt and ctx.verifyAt > 0 and now > ctx.verifyAt then
            ctx.verifyPending = nil
            notice(deps, wgt, "CELLS NOT APPLIED - CHECK MANUALLY", deps.colors.red)
            return
        end
        if ctx.verifyNextAt and now < ctx.verifyNextAt then return end
        ctx.verifyNextAt = now + 200

        local queue = deps.getQueue()
        if not queue or type(queue.add) ~= "function" then return end

        local cells = ctx.verifyPending
        queue:add({
            command = BATTERY_STATE,
            processReply = function(_, buf)
                local reported = tonumber(type(buf) == "table" and buf[2] or nil)
                if reported == cells then
                    ctx.verifyPending = nil
                    notice(deps, wgt, tostring(cells) .. " CELLS CONFIRMED", deps.colors.green)
                    ctx.state.cells = cells
                    M.saveState(deps, ctx.state)
                    M.log(deps, "  verify: confirmed " .. tostring(cells))
                end
            end,
        })
    end

    function api.getState()
        return ctx.state
    end

    -- Lets main.lua write into the same log.
    function api.log(text)
        M.log(deps, tostring(text))
    end

    return api
end

-- One-time load marker so the add-on can be verified from the PC.
pcall(function()
    local w = io.open("/WIDGETS/AK7HUD/cells_addon.txt", "w")
    if w then
        pcall(io.write, w, "cellcount addon 2026-11-02\n")
        pcall(io.close, w)
    end
end)

return M