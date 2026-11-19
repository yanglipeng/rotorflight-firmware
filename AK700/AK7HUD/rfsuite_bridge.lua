--[[
  AK7HUD <-> RFSuite 桥接层

  背景：AK7HUD 的电池节数/报警电压模块原本读取 RF Tool（rotorflight-lua-scripts）
  暴露的 rf2 全局：rf2.apiVersion / rf2.mspQueue / rf2.useApi / rf2.clock。

  RFSuite（rotorflight-lua-edgetx-suite）是另一套架构，不提供 rf2，但它把 MSP 请求面
  发布成 rfsuite.msp，正是为了让「遥控器上的其他脚本」共用同一个发送槽
  （crossfireTelemetryPush 只有一个缓冲，各自建队列必然互抢）。

  本文件在满足下面全部条件时，用 rfsuite.msp 构造一个 rf2 兼容对象并挂到 _G.rf2：

    1. _G.rf2 尚不存在（RF Tool 没在跑，或根本没装）
    2. _G.rfsuite.msp 可用（RFSuite 的 runtime 已被 service/dashboard widget 拉起）

  任何一条不满足就什么都不做，AK7HUD 保持原来的 RF Tool 路径。这样两套环境都能用，
  且不会覆盖正在运行的 RF Tool。
]]

local function log(msg)
  local L = _G.rfsuite and _G.rfsuite.Log
  if type(L) == "table" and type(L.tagged) == "function" then
    local t = L.tagged("AK7HUD.bridge")
    if type(t) == "function" then pcall(t, msg, "info") return end
  end
end

local function rfsuiteMsp()
  local r = rawget(_G, "rfsuite")
  if type(r) ~= "table" then return nil end
  local msp = r.msp
  if type(msp) ~= "table" or type(msp.register) ~= "function" then return nil end
  return msp
end

-- RFSuite 的解析模块只做 Api.parse(buf) / Api.buildWritePayload(data)，可以原样复用，
-- 这样 27 字节旧布局和 81 字节（每 profile 节数）新布局都由它判别，AK7HUD 不必自己判断。
local function loadRfApi(rel)
  local path = "/SCRIPTS/TOOLS/rfsuite-core/tasks/msp/api/" .. rel
  local chunk = loadScript(path, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok or type(mod) ~= "table" then return nil end
  return mod
end

-- RF Tool 的结构是 {field = {value = n}}，RFSuite 的 parse 给的是扁平值。AK7HUD 里两种
-- 写法都有用到（batteryCapacity 按 {field={value}} 读，status 按扁平读），所以这里按
-- 各个命令分别还原成 AK7HUD 期望的形状。
local function cell(v)
  if type(v) == "table" then return v end
  return { value = v }
end

local function shapeBatteryConfig(p)
  if type(p) ~= "table" then return nil end
  local out = {
    batteryCapacity          = cell(p.batteryCapacity),
    batteryCellCount         = cell(p.batteryCellCount),
    voltageMeterSource       = cell(p.voltageMeterSource),
    currentMeterSource       = cell(p.currentMeterSource),
    vbatmincellvoltage       = cell(p.vbatmincellvoltage),
    vbatmaxcellvoltage       = cell(p.vbatmaxcellvoltage),
    vbatfullcellvoltage      = cell(p.vbatfullcellvoltage),
    vbatwarningcellvoltage   = cell(p.vbatwarningcellvoltage),
    lvcPercentage            = cell(p.lvcPercentage),
    consumptionWarningPercentage = cell(p.consumptionWarningPercentage),
  }
  -- 六个 cell 容量，RF Tool 用 0..5 下标
  for i = 0, 5 do
    local v = p["batteryCapacity_" .. i]
    if v ~= nil then out.batteryCapacity[i] = { value = v } end
  end
  return out
end

local function install()
  local msp = rfsuiteMsp()
  if not msp then return false end
  if rawget(_G, "rf2") ~= nil then return false end

  local client = msp.register("AK7HUD", 2)
  if not client then
    log("register failed")
    return false
  end

  local pending = 0
  local queue = {}

  -- RF Tool 的 message 契约：command / payload / processReply(self, buf) /
  -- errorHandler(message, reason) / retryDelay（单位 1/10 s）。RFSuite 用秒。
  function queue:add(message)
    if type(message) ~= "table" or type(message.command) ~= "number" then
      return nil
    end
    pending = pending + 1
    local timeout = nil
    if type(message.retryDelay) == "number" and message.retryDelay > 0 then
      timeout = message.retryDelay / 10
    end
    local req = {
      command = message.command,
      payload = message.payload,
      simulatorResponse = message.simulatorResponse,
      timeout = timeout,
      onReply = function(buf)
        pending = math.max(0, pending - 1)
        if type(message.processReply) == "function" then
          local ok, err = pcall(message.processReply, message, buf)
          if not ok then log("processReply failed: " .. tostring(err)) end
        end
      end,
      onError = function(reason)
        pending = math.max(0, pending - 1)
        if type(message.errorHandler) == "function" then
          local ok, err = pcall(message.errorHandler, message, reason)
          if not ok then log("errorHandler failed: " .. tostring(err)) end
        end
      end,
    }
    if message.payload ~= nil then req.isWrite = true end
    local id = client:request(req)
    if id == nil then
      pending = math.max(0, pending - 1)
      if type(message.errorHandler) == "function" then
        pcall(message.errorHandler, message, "unavailable")
      end
    end
    return id
  end

  -- RF Tool 的 queue 提供 isProcessed/processQueue/clear/cancel 等入口。这里真的泵由
  -- RFSuite 自己的 runtime 驱动，processQueue 只要存在（AK7HUD 的飞行计数安全检查会
  -- 包装它），不能是 nil，否则那段逻辑会直接判 "NO QUEUE" 退出。
  function queue:isProcessed()
    return pending == 0
  end

  function queue:processQueue() end

  function queue:clear()
    if type(client) == "table" and type(client.release) == "function" then
      pcall(client.release, client)
    end
    pending = 0
    client = msp.register("AK7HUD", 2)
  end

  local cfgApi = loadRfApi("battery_config.lua")
  local profApi = loadRfApi("battery_profile.lua")
  local statusApi = loadRfApi("status.lua")
  local statsApi = loadRfApi("flight_stats.lua")

  local function readVia(api, shaper)
    return function(callback, callbackParam, _data)
      if type(api) ~= "table" or type(api.parse) ~= "function" then
        if callback then pcall(callback, callbackParam, nil) end
        return
      end
      queue:add({
        command = api.command,
        processReply = function(_, buf)
          local parsed = api.parse(buf)
          local shaped = shaper and shaper(parsed) or parsed
          if callback then pcall(callback, callbackParam, shaped) end
        end,
        errorHandler = function()
          if callback then pcall(callback, callbackParam, nil) end
        end,
      })
    end
  end

  local function writeVia(api)
    return function(data, callback, callbackParam)
      if type(api) ~= "table" or type(api.buildWritePayload) ~= "function" then
        if callback then pcall(callback, callbackParam, nil) end
        return
      end
      queue:add({
        command = api.writeCommand,
        payload = api.buildWritePayload(data),
        processReply = function(_, buf)
          if callback then pcall(callback, callbackParam, buf) end
        end,
        errorHandler = function()
          if callback then pcall(callback, callbackParam, nil) end
        end,
      })
    end
  end

  local apis = {}

  apis.mspBatteryConfig = {
    read = readVia(cfgApi, shapeBatteryConfig),
    write = writeVia(cfgApi),
  }

  apis.mspBatteryProfile = {
    read = readVia(profApi, function(p)
      if type(p) ~= "table" then return nil end
      return { batteryProfile = cell(p.batteryProfile) }
    end),
    write = writeVia(profApi),
  }

  -- AK7HUD 读 status.armingDisableFlags 时用的是扁平值，不套 {value=}；
  -- RFSuite 的字段名是 snake_case，这里换回 RF Tool 的 camelCase。
  apis.mspStatus = {
    getStatus = readVia(statusApi, function(p)
      if type(p) ~= "table" then return nil end
      return {
        armingDisableFlags = p.arming_disable_flags,
        armingDisableFlagsCount = p.arming_disable_flags_count,
        flightModeFlags = p.flight_mode_flags,
        profileNumber = p.profile_number,
      }
    end),
  }
  apis.mspStatus.read = apis.mspStatus.getStatus

  -- 飞行统计：AK7HUD 判定 statsEnabled.value == 1 且读 stats_total_flights.value。
  -- RFSuite 的 flight_stats 只有扁平字段，能读到就说明统计可用，所以 statsEnabled 直接给 1。
  apis.mspFlightStats = {
    read = readVia(statsApi, function(p)
      if type(p) ~= "table" then return nil end
      return {
        statsEnabled = { value = 1 },
        stats_total_flights = { value = p.flightcount },
        stats_total_time = { value = p.totalflighttime },
        stats_total_dist = { value = p.totaldistance },
      }
    end),
  }

  local function useApi(name)
    return apis[name]
  end

  -- widget 字段让 AK7HUD 的 profileRfToolProvider() 走 hasRfToolCore 分支，
  -- 同时避免被 profileStandaloneRf2bgCore() 误判成 rf2bg 后台核心。
  _G.rf2 = {
    apiVersion = 12.10,
    mspQueue = queue,
    useApi = useApi,
    widget = {},
    clock = function()
      local t = getTime and getTime() or 0
      return t / 100
    end,
  }

  log("installed, apiVersion=12.10")
  return true
end

-- main.lua 的 profileRf2() 在探测不到 rf2 时会回来调 install()，因为 RFSuite 的 runtime
-- 有可能比本 widget 起得晚。install() 自己判断前置条件，重复调用是安全的。
_G.__ak7hud_bridge = { install = install }

local ok, err = pcall(install)
if not ok then log("install failed: " .. tostring(err)) end

return { install = install }
