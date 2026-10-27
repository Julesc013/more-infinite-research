local fixture = "mir-fixture-mir5-migration-origin-f200-110-source"
local catalogue = require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")

if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.1.0"
    or mods[fixture] ~= "0.1.0" then
  error("[mir5-migration-origin-f200-110-source] exact source closure differs")
end

local function fail(message)
  error("[mir5-migration-origin-f200-110-source] " .. message)
end

local function signature(value)
  if value.type == "change-recipe-productivity" then
    return value.type .. "|" .. tostring(value.recipe) .. "|" .. string.format("%.17g", value.change)
  end
  if value.type == "worker-robot-battery" then
    return value.type .. "|" .. string.format("%.17g", value.modifier)
  end
  return tostring(value.type) .. "|unexpected"
end

local function count_signatures(values)
  local result = {}
  for _, value in ipairs(values or {}) do
    local key = signature(value)
    result[key] = (result[key] or 0) + 1
  end
  return result
end

local function assert_same_counts(actual, expected, label)
  for key, amount in pairs(expected) do
    if actual[key] ~= amount then fail(label .. " differs at " .. key) end
    actual[key] = nil
  end
  if next(actual) ~= nil then fail(label .. " has unexpected value " .. tostring(next(actual))) end
end

local function map_ingredients(values, label)
  local result = {}
  for _, value in ipairs(values or {}) do
    local name, amount = value[1], value[2]
    if type(name) ~= "string" or amount ~= 1 or result[name] ~= nil then
      fail(label .. " is malformed")
    end
    result[name] = amount
  end
  return result
end

local function map_prerequisites(values, label)
  local result = {}
  for _, name in ipairs(values or {}) do
    if type(name) ~= "string" or result[name] ~= nil then fail(label .. " is malformed") end
    result[name] = true
  end
  return result
end

local function copy_map(values)
  local result = {}
  for name, value in pairs(values or {}) do result[name] = value end
  return result
end

local function set_from_map(values)
  local result = {}
  for name in pairs(values or {}) do result[name] = true end
  return result
end

local function expected_effects(row)
  return count_signatures(row.effects)
end

for name, default_value in pairs(catalogue.settings) do
  local setting = data.raw["bool-setting"] and data.raw["bool-setting"][name]
  if setting == nil or setting.type ~= "bool-setting" or setting.setting_type ~= "startup"
      or setting.default_value ~= default_value then
    fail("published setting default differs: " .. name)
  end
  local runtime = settings.startup[name]
  if runtime == nil or runtime.value ~= default_value then
    fail("effective default setting differs: " .. name)
  end
end

local setting_count = 0
for name in pairs(data.raw["bool-setting"] or {}) do
  if name:sub(1, 4) == "ips-" then
    if catalogue.settings[name] == nil then fail("unexpected published setting: " .. name) end
    setting_count = setting_count + 1
  end
end
if setting_count ~= 42 then fail("published setting count differs") end

local roster_count = 0
for name, value in pairs(data.raw.technology or {}) do
  if name:sub(1, #catalogue.technology_prefix) == catalogue.technology_prefix then
    if name:sub(-#catalogue.technology_suffix) ~= catalogue.technology_suffix then
      fail("source roster suffix differs: " .. name)
    end
    local expected = catalogue.rows[name]
    if expected == nil then fail("unexpected source row: " .. name) end
    if value.type ~= "technology" or value.name ~= name or value.level ~= nil
        or value.upgrade ~= true or value.max_level ~= "infinite" or value.enabled == false then
      fail("source identity differs: " .. name)
    end
    local unit = value.unit
    if type(unit) ~= "table" or unit.count_formula ~= catalogue.source_formula or unit.time ~= catalogue.source_time then
      fail("source unit differs: " .. name)
    end
    assert_same_counts(map_ingredients(unit.ingredients, "source science " .. name),
      copy_map(catalogue.science[expected.science]),
      "source science " .. name)
    assert_same_counts(map_prerequisites(value.prerequisites, "source prerequisites " .. name),
      set_from_map(catalogue.science[expected.science]),
      "source prerequisites " .. name)
    assert_same_counts(count_signatures(value.effects), expected_effects(expected), "source effects " .. name)
    roster_count = roster_count + 1
  end
end
for name in pairs(catalogue.rows) do
  if data.raw.technology[name] == nil then fail("published source row is absent: " .. name) end
end
if roster_count ~= 31 then fail("published source roster count differs") end
if data.raw.technology["recipe-prod-research_inventory_capacity-1"] ~= nil then
  fail("disabled inventory stream was emitted")
end

-- Acceleration is the sole write.  The source formula/time, settings, all
-- thirty-one effect vectors and raw-level omission have already been checked.
local direct = data.raw.technology[catalogue.direct]
direct.unit.count_formula = nil
direct.unit.count = 1
direct.unit.time = 1
