-- Exact row preflight for the legacy competing-preference fixture.  Every
-- stage validates the captured breeding row before it changes only its
-- disposable unit count/time.
local M = {}

local FIXTURE = "mir-fixture-mir5-legacy-preference-transition"
local ROW = "recipe-prod-research_breeding-1"
local PREREQUISITES = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "cryogenic-science-pack",
}

local function names(values, expected, label)
  if type(values) ~= "table" or #values ~= #expected then error(label .. " count changed", 3) end
  for index = 1, #expected do
    local value = values[index]
    local name = type(value) == "table" and (value.name or value[1]) or value
    if name ~= expected[index] then error(label .. " changed at " .. tostring(index), 3) end
  end
end

function M.accelerate(spec)
  assert(type(spec) == "table" and type(spec.mir) == "string" and type(spec.fixture) == "string"
    and type(spec.preference) == "boolean" and type(spec.effects) == "table", "invalid fixture stage")
  assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77"
    and mods["more-infinite-research"] == spec.mir and mods[FIXTURE] == spec.fixture
    and mods["plates-n-circuit-productivity"] == "0.0.2"
    and mods.Science_packs_productivity == "0.0.1"
    and mods["bioflux-productivity"] == "0.1.0" and mods["fish-productivity"] == "1.0.0",
    "unexpected legacy-preference fixture closure")
  local setting = assert(settings.startup and settings.startup["mir-prefer-this-mod-for-competing-techs"],
    "MIR competing preference setting is absent")
  assert(type(setting.value) == "boolean" and setting.value == spec.preference,
    "fixture preference setting differs")
  local row = assert(data.raw.technology and data.raw.technology[ROW], "captured MIR breeding row is absent")
  assert(row.type == "technology" and row.name == ROW and row.level == 1 and row.max_level == "infinite"
    and row.upgrade == true, "captured MIR breeding identity changed")
  names(row.prerequisites, PREREQUISITES, "captured MIR breeding prerequisites")
  if type(row.effects) ~= "table" or #row.effects ~= #spec.effects then
    error("captured MIR breeding effects count changed", 2)
  end
  for index = 1, #spec.effects do
    local effect = row.effects[index]
    assert(type(effect) == "table" and effect.type == "change-recipe-productivity"
      and effect.recipe == spec.effects[index] and effect.change == .1,
      "captured MIR breeding effect changed at " .. tostring(index))
  end
  local unit = assert(row.unit, "captured MIR breeding unit is absent")
  assert(unit.count_formula == "8000*2^(L-1)" and unit.count == nil and unit.time == 60,
    "captured MIR breeding cost/time changed")
  names(unit.ingredients, PREREQUISITES, "captured MIR breeding science")
  for _, ingredient in ipairs(unit.ingredients) do
    assert((ingredient.amount or ingredient[2]) == 1, "captured MIR breeding science amount changed")
  end
  unit.count_formula, unit.count, unit.time = nil, 1, 1
end

return M
