local function fail(message)
  error("MIR prototype limit validation failed: " .. message)
end

local function startup_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local expected_by_setting = {
  ["mir-prototype-productivity-cap"] = {
    ["percent-500"] = 5.0,
    ["percent-1000"] = 10.0,
    ["percent-2500"] = 25.0,
    ["percent-10000"] = 100.0,
    ["percent-100000"] = 1000.0
  },
  ["mir-prototype-efficiency-cap"] = {
    ["saving-90"] = -0.9,
    ["saving-95"] = -0.95,
    ["saving-99"] = -0.99,
    ["saving-999"] = -0.999,
    ["saving-9999"] = -0.9999
  },
  ["mir-prototype-speed-cap"] = {
    ["bonus-100"] = 1.0,
    ["bonus-500"] = 5.0,
    ["bonus-1000"] = 10.0,
    ["bonus-10000"] = 100.0,
    ["bonus-100000"] = 1000.0
  },
  ["mir-prototype-quality-cap"] = {
    ["bonus-100"] = 1.0,
    ["bonus-500"] = 5.0,
    ["bonus-1000"] = 10.0,
    ["bonus-10000"] = 100.0,
    ["bonus-100000"] = 1000.0
  }
}

local function expected_value(setting_name)
  local raw_value = startup_setting(setting_name)
  if raw_value == nil or raw_value == "engine-default" then return nil end
  return expected_by_setting[setting_name][raw_value]
end

local expected_productivity = expected_value("mir-prototype-productivity-cap")
local expected_efficiency = expected_value("mir-prototype-efficiency-cap")
local expected_speed = expected_value("mir-prototype-speed-cap")
local expected_quality = expected_value("mir-prototype-quality-cap")

if not expected_productivity and not expected_efficiency and not expected_speed and not expected_quality then
  return
end

local function assert_close(label, actual, expected)
  if actual == nil then
    fail(label .. " was nil, expected " .. tostring(expected) .. ".")
  end
  if math.abs(actual - expected) > 0.000001 then
    fail(label .. " was " .. tostring(actual) .. ", expected " .. tostring(expected) .. ".")
  end
end

if expected_productivity then
  local recipe = data.raw.recipe and data.raw.recipe["iron-gear-wheel"]
  if not recipe then fail("missing iron-gear-wheel recipe.") end
  assert_close("iron-gear-wheel maximum_productivity", recipe.maximum_productivity, expected_productivity)
end

local effect_receiver_prototypes = {
  { type = "assembling-machine", name = "assembling-machine-1" },
  { type = "furnace", name = "electric-furnace" },
  { type = "rocket-silo", name = "rocket-silo" },
  { type = "lab", name = "lab" },
  { type = "mining-drill", name = "electric-mining-drill" },
  { type = "agricultural-tower", name = "agricultural-tower" }
}

for _, id in ipairs(effect_receiver_prototypes) do
  local prototype = data.raw[id.type] and data.raw[id.type][id.name]
  if prototype then
    local receiver = prototype.effect_receiver
    if not receiver then
      fail(id.type .. "." .. id.name .. " has no effect_receiver.")
    end
    if expected_efficiency then
      assert_close(id.type .. "." .. id.name .. " consumption_limits.low",
        receiver.consumption_limits and receiver.consumption_limits.low,
        expected_efficiency)
      assert_close(id.type .. "." .. id.name .. " consumption_limits.high",
        receiver.consumption_limits and receiver.consumption_limits.high,
        1000)
    end
    if expected_speed then
      assert_close(id.type .. "." .. id.name .. " speed_limits.high",
        receiver.speed_limits and receiver.speed_limits.high,
        expected_speed)
      assert_close(id.type .. "." .. id.name .. " speed_limits.low",
        receiver.speed_limits and receiver.speed_limits.low,
        -0.8)
    end
    if expected_quality then
      assert_close(id.type .. "." .. id.name .. " quality_limits.high",
        receiver.quality_limits and receiver.quality_limits.high,
        expected_quality)
      assert_close(id.type .. "." .. id.name .. " quality_limits.low",
        receiver.quality_limits and receiver.quality_limits.low,
        0)
    end
  end
end
