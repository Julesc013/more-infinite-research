local FIXTURE = "mir-fixture-mir5-migration-origin-f200-120-source"
local catalogue = require("__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")

if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.2.0"
    or mods[FIXTURE] ~= "0.1.0" then
  error("[mir5-migration-origin-f200-120-source] exact source closure differs")
end

local function fail(message)
  error("[mir5-migration-origin-f200-120-source] " .. message)
end

local function signature(value)
  if value.type == "change-recipe-productivity" then
    return value.type .. "|" .. tostring(value.recipe) .. "|" .. string.format("%.17g", value.change)
  end
  if value.type == "worker-robot-battery" then return value.type .. "|" .. string.format("%.17g", value.modifier) end
  if value.type == "gun-speed" then
    return value.type .. "|" .. tostring(value.ammo_category) .. "|" .. string.format("%.17g", value.modifier)
  end
  return tostring(value.type) .. "|unexpected"
end

local function counts(values)
  local result = {}
  for _, value in ipairs(values or {}) do
    local key = signature(value)
    result[key] = (result[key] or 0) + 1
  end
  return result
end

local function assert_counts(actual, expected, label)
  for key, amount in pairs(expected) do
    if actual[key] ~= amount then fail(label .. " differs at " .. key) end
    actual[key] = nil
  end
  if next(actual) ~= nil then fail(label .. " has unexpected value " .. tostring(next(actual))) end
end

local function expected_effects(row)
  return counts(row.effects)
end

local function map_ingredients(values, label)
  local result = {}
  for _, value in ipairs(values or {}) do
    local name, amount = value[1], value[2]
    if type(name) ~= "string" or amount ~= 1 or result[name] ~= nil then fail(label .. " is malformed") end
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

for name, expected in pairs(catalogue.settings) do
  local runtime = settings.startup[name]
  if runtime == nil or runtime.value ~= expected.default_value then
    fail("effective default setting differs: " .. name)
  end
end

local roster_count = 0
for name, value in pairs(data.raw.technology or {}) do
  if name:sub(1, #catalogue.technology_prefix) == catalogue.technology_prefix then
    local expected = catalogue.rows[name]
    if expected == nil or name:sub(-#catalogue.technology_suffix) ~= catalogue.technology_suffix then
      fail("unexpected source row: " .. name)
    end
    if value.type ~= "technology" or value.name ~= name or value.level ~= expected.level
        or value.max_level ~= expected.max_level or value.upgrade ~= expected.upgrade
        or (value.enabled ~= nil) ~= expected.enabled_present then
      fail("source identity differs: " .. name)
    end
    local unit = value.unit
    if type(unit) ~= "table" or unit.count_formula ~= expected.unit.count_formula
        or unit.time ~= expected.unit.time or unit.count ~= nil then
      fail("source unit differs: " .. name)
    end
    assert_counts(map_ingredients(unit.ingredients, "source science " .. name),
      copy_map(map_ingredients(expected.unit.ingredients, "catalogue science " .. name)), "source science " .. name)
    assert_counts(map_prerequisites(value.prerequisites, "source prerequisites " .. name),
      copy_map(map_prerequisites(expected.prerequisites, "catalogue prerequisites " .. name)), "source prerequisites " .. name)
    assert_counts(counts(value.effects), expected_effects(expected), "source effects " .. name)
    roster_count = roster_count + 1
  end
end
for name in pairs(catalogue.rows) do
  if data.raw.technology[name] == nil then fail("published source row is absent: " .. name) end
end
if roster_count ~= 34 then fail("published source roster count differs") end

for name, expected in pairs(catalogue.weapons) do
  local value = data.raw.technology[name]
  if value == nil or value.type ~= "technology" or value.name ~= name then fail("weapon owner is absent: " .. name) end
  assert_counts(counts(value.effects), expected_effects(expected), "weapon effects " .. name)
end

local continuation = data.raw.technology["weapon-shooting-speed-7"]
if continuation == nil or continuation.level ~= 7 or continuation.max_level ~= "infinite" then
  fail("published infinite weapon continuation differs")
end

local direct = data.raw.technology[catalogue.direct]
direct.unit.count_formula = nil
direct.unit.count = 1
direct.unit.time = 1
