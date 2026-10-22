local technology_name = "recipe-prod-research_gears-1"
local recipe_name = "iron-gear-wheel"

local function fail(message)
  error("[mir5-gear-native] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000000001
end

local function effect(technology)
  local matches = {}
  for _, row in ipairs(technology.effects or {}) do
    if row.type == "change-recipe-productivity" and row.recipe == recipe_name then
      matches[#matches + 1] = row
    end
  end
  if #matches ~= 1 then fail("expected exactly one gear productivity effect") end
  return matches[1]
end

local function exact_list(actual, expected, label)
  if #actual ~= #expected then fail(label .. " cardinality differs") end
  for index, value in ipairs(expected) do
    if actual[index] ~= value then
      fail(label .. " differs at " .. index .. "; expected " .. value .. " got " .. tostring(actual[index]))
    end
  end
end

local expected_profiles = {
  ["0.1.0"] = {
    name = "default", formula = "8000*2^(L-1)", time = 60,
    change = 0.10, level_one_count = 8000, physical_output = 110,
    base_cost = 8000, linear_increment = 0, growth_factor = 2, effect_percent = 10
  },
  ["0.2.0"] = {
    name = "tuned", formula = "(100+25*(L-1))*1.5^(L-1)", time = 30,
    change = 0.20, level_one_count = 100, physical_output = 120,
    base_cost = 100, linear_increment = 25, growth_factor = 1.5, effect_percent = 20
  }
}
local fixture_version = mods["mir-fixture-mir5-gear-native"]
local profile = expected_profiles[fixture_version]
if not profile then fail("unsupported fixture version " .. tostring(fixture_version)) end

local configuration = require("__more-infinite-research__/research/settings")
local values = configuration.resolve(settings.startup, helpers, nil)
if values.base_cost ~= profile.base_cost or values.linear_increment ~= profile.linear_increment
    or not close(values.growth_factor, profile.growth_factor) or values.research_time ~= profile.time
    or not close(values.effect_percent, profile.effect_percent) then
  fail("effective startup settings differ from fixture profile " .. profile.name)
end

if values.enabled ~= true or values.max_level ~= 0 then
  fail("private slice must retain enabled unlimited gears")
end

local technology = data.raw.technology and data.raw.technology[technology_name]
if not technology then fail("missing published gear technology") end
if technology.type ~= "technology" or technology.max_level ~= "infinite" or technology.enabled ~= true or technology.upgrade ~= true then
  fail("gear technology identity or infinite form differs")
end
if not technology.unit or technology.unit.count ~= nil or technology.unit.count_formula ~= profile.formula
    or not close(technology.unit.time, profile.time) then
  fail("gear research formula or time differs for " .. profile.name)
end

exact_list(technology.prerequisites or {}, {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"
}, "gear prerequisites")

local ingredients = technology.unit.ingredients or {}
if #ingredients ~= 4 then fail("gear science ingredient cardinality differs") end
local science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
for index, name in ipairs(science) do
  local row = ingredients[index]
  if type(row) ~= "table" or row[1] ~= name or row[2] ~= 1 then
    fail("gear science differs at " .. index)
  end
end

if not close(effect(technology).change, profile.change) then
  fail("gear productivity effect differs for " .. profile.name)
end
if not data.raw.recipe or not data.raw.recipe[recipe_name] then fail("gear productivity target recipe is absent") end

log("[MIR5_GEAR_DATA] profile=" .. profile.name .. ";formula=" .. profile.formula
  .. ";time=" .. profile.time .. ";change=" .. profile.change .. ";level_one=" .. profile.level_one_count)
