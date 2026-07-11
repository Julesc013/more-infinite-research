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
    ["percent-25"] = 0.25,
    ["percent-125"] = 1.25,
    ["percent-150"] = 1.5,
    ["percent-500"] = 5.0,
    ["percent-750"] = 7.5,
    ["percent-1000"] = 10.0,
    ["percent-2500"] = 25.0,
    ["percent-5000"] = 50.0,
    ["percent-10000"] = 100.0,
    ["percent-25000"] = 250.0,
    ["percent-100000"] = 1000.0
  },
  ["mir-prototype-efficiency-cap"] = {
    ["saving-25"] = -0.25,
    ["saving-90"] = -0.9,
    ["saving-95"] = -0.95,
    ["saving-99"] = -0.99,
    ["saving-999"] = -0.999,
    ["saving-9999"] = -0.9999
  },
  ["mir-prototype-pollution-cap"] = {
    ["saving-25"] = -0.25,
    ["saving-90"] = -0.9,
    ["saving-95"] = -0.95,
    ["saving-99"] = -0.99,
    ["saving-999"] = -0.999,
    ["saving-9999"] = -0.9999
  },
  ["mir-prototype-speed-cap"] = {
    ["bonus-25"] = 0.25,
    ["bonus-125"] = 1.25,
    ["bonus-150"] = 1.5,
    ["bonus-300"] = 3.0,
    ["bonus-100"] = 1.0,
    ["bonus-500"] = 5.0,
    ["bonus-750"] = 7.5,
    ["bonus-1000"] = 10.0,
    ["bonus-2500"] = 25.0,
    ["bonus-5000"] = 50.0,
    ["bonus-10000"] = 100.0,
    ["bonus-25000"] = 250.0,
    ["bonus-100000"] = 1000.0
  },
  ["mir-prototype-speed-floor"] = {
    ["saving-25"] = -0.25,
    ["saving-50"] = -0.5,
    ["saving-75"] = -0.75,
    ["saving-90"] = -0.9,
    ["saving-95"] = -0.95,
    ["saving-99"] = -0.99,
    ["saving-999"] = -0.999,
    ["saving-9999"] = -0.9999
  },
  ["mir-prototype-quality-cap"] = {
    ["bonus-25"] = 0.25,
    ["bonus-125"] = 1.25,
    ["bonus-150"] = 1.5,
    ["bonus-300"] = 3.0,
    ["bonus-100"] = 1.0,
    ["bonus-500"] = 5.0,
    ["bonus-750"] = 7.5,
    ["bonus-1000"] = 10.0,
    ["bonus-2500"] = 25.0,
    ["bonus-5000"] = 50.0,
    ["bonus-10000"] = 100.0,
    ["bonus-25000"] = 250.0,
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
local expected_pollution = expected_value("mir-prototype-pollution-cap")
local expected_speed_floor = expected_value("mir-prototype-speed-floor")
local expected_speed = expected_value("mir-prototype-speed-cap")
local expected_quality = expected_value("mir-prototype-quality-cap")

local scoped_cap = startup_setting("mir-productivity-cap-self-recycling-only") == true
local unrestricted_modules = startup_setting("mir-unrestricted-modules") == true
local recycling_return = startup_setting("mir-recycling-return-chance")

local function expected_recycling_chance()
  if recycling_return == nil or recycling_return == "engine-default" then return nil end
  local fixed = {
    ["percent-25"] = 0.25,
    ["percent-20"] = 0.20,
    ["percent-15"] = 0.15,
    ["percent-12-5"] = 0.125,
    ["percent-10"] = 0.10,
    ["percent-7-5"] = 0.075,
    ["percent-5"] = 0.05,
    ["percent-2-5"] = 0.025,
    ["percent-1"] = 0.01,
    ["percent-0-5"] = 0.005,
    ["percent-0-1"] = 0.001
  }
  if fixed[recycling_return] then return fixed[recycling_return] end
  if recycling_return == "match-productivity-cap" then
    local cap = expected_productivity or 3.0
    return math.min(0.25, 1 / (1 + cap))
  end
  return nil
end

local recycling_chance = expected_recycling_chance()

if not expected_productivity and not expected_efficiency and not expected_pollution and not expected_speed_floor
  and not expected_speed and not expected_quality and not recycling_chance
  and startup_setting("mir-prototype-positive-power-floor") ~= true and not unrestricted_modules then
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
  local inverse_threshold = recycling_chance and recycling_chance > 0
    and math.max(0, (1 / recycling_chance) - 1) or math.huge
  local recipe = data.raw.recipe and data.raw.recipe["iron-gear-wheel"]
  if not recipe then fail("missing iron-gear-wheel recipe.") end
  if not (scoped_cap and expected_productivity > inverse_threshold) then
    assert_close("iron-gear-wheel maximum_productivity", recipe.maximum_productivity, expected_productivity)
  else
    assert_close("iron-gear-wheel inverse recycling maximum_productivity", recipe.maximum_productivity, inverse_threshold)
  end
  if scoped_cap and expected_productivity > inverse_threshold then
    local safe = data.raw.recipe["mir-fixture-self-recycling-production"]
    local unsafe = data.raw.recipe["mir-fixture-non-recycling-production"]
    local loop = data.raw.recipe["mir-fixture-self-recycling-loop"]
    if safe then assert_close("self-recycling production maximum_productivity", safe.maximum_productivity, expected_productivity) end
    if unsafe then assert_close("non-recycling production inverse cap", unsafe.maximum_productivity, inverse_threshold) end
    if loop then assert_close("self-recycling loop inverse cap", loop.maximum_productivity, inverse_threshold) end
  end
end

if recycling_chance then
  local generated = data.raw.recipe["mir-fixture-generated-recycling"]
  local visible = data.raw.recipe["mir-fixture-visible-recycling"]
  if not generated or not generated.results or not generated.results[1] then
    fail("missing generated recycling fixture recipe.")
  end
  assert_close("generated recycling independent_probability",
    generated.results[1].independent_probability,
    recycling_chance)
  if visible and visible.results and visible.results[1] then
    assert_close("visible recycling independent_probability",
      visible.results[1].independent_probability,
      0.25)
  end
end

local module_technology = data.raw.technology and data.raw.technology["recipe-prod-research_modules-1"]
if module_technology then
  local found = false
  for _, effect in ipairs(module_technology.effects or {}) do
    if effect.type == "change-recipe-productivity"
      and effect.recipe == "mir-fixture-productivity-module-4"
      and math.abs((effect.change or 0) - 0.01) < 0.000001
    then
      found = true
      break
    end
  end
  if not found then fail("tier-4 module recipe was not discovered by module prototype tier.") end
end

if unrestricted_modules then
  local recipe = data.raw.recipe["iron-gear-wheel"]
  if recipe then
    if recipe.allow_speed ~= true or recipe.allow_productivity ~= true or recipe.allow_consumption ~= true
      or recipe.allow_pollution ~= true or recipe.allow_quality ~= true then
      fail("unrestricted module permissions did not open all recipe effect flags.")
    end
    if not recipe.allowed_module_categories or #recipe.allowed_module_categories == 0 then
      fail("unrestricted module permissions did not discover module categories.")
    end
  end
  local machine = data.raw["assembling-machine"] and data.raw["assembling-machine"]["assembling-machine-1"]
  if machine and (tonumber(machine.module_slots) or 0) > 0 then
    if not machine.allowed_effects or #machine.allowed_effects ~= 5 then fail("assembling machine effect permissions were not opened.") end
    if not machine.allowed_module_categories or #machine.allowed_module_categories == 0 then fail("assembling machine module categories were not opened.") end
  end

  local first = data.raw.recipe["iron-gear-wheel"]
  local second = data.raw.recipe["copper-cable"]
  if first and second and first.allowed_module_categories and second.allowed_module_categories then
    local second_count = #second.allowed_module_categories
    local removed = table.remove(first.allowed_module_categories)
    if #second.allowed_module_categories ~= second_count then
      fail("recipe allowed_module_categories arrays are aliased.")
    end
    if removed then table.insert(first.allowed_module_categories, removed) end
  end
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
  if prototype and (expected_efficiency or expected_pollution or expected_speed_floor or expected_speed or expected_quality) then
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
    if expected_pollution then
      assert_close(id.type .. "." .. id.name .. " pollution_limits.low",
        receiver.pollution_limits and receiver.pollution_limits.low,
        expected_pollution)
      assert_close(id.type .. "." .. id.name .. " pollution_limits.high",
        receiver.pollution_limits and receiver.pollution_limits.high,
        1000)
    end
    if expected_speed then
      assert_close(id.type .. "." .. id.name .. " speed_limits.high",
        receiver.speed_limits and receiver.speed_limits.high,
        expected_speed)
      if not expected_speed_floor then
        assert_close(id.type .. "." .. id.name .. " speed_limits.low",
          receiver.speed_limits and receiver.speed_limits.low,
          -0.8)
      end
    end
    if expected_speed_floor then
      assert_close(id.type .. "." .. id.name .. " speed_limits.low",
        receiver.speed_limits and receiver.speed_limits.low,
        expected_speed_floor)
      if not expected_speed then
        assert_close(id.type .. "." .. id.name .. " speed_limits.high",
          receiver.speed_limits and receiver.speed_limits.high,
          1000)
      end
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

if startup_setting("mir-prototype-positive-power-floor") == true then
  local beacon = data.raw.beacon and data.raw.beacon["mir-fixture-zero-watt-beacon"]
  if not beacon then fail("missing zero-watt beacon fixture prototype.") end
  if beacon.energy_usage ~= "1W" then
    fail("zero-watt beacon energy_usage was " .. tostring(beacon.energy_usage) .. ", expected 1W.")
  end
end
