-- Shared F200 Base preflight.  This fixture observes runtime caps only and
-- does not change the authored gear technology, its science, or its effect.
local M = {}

local NAME = "recipe-prod-research_gears-1"
local FIXTURE = "mir-fixture-mir5-f200-foreign-cap-baseline"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack",
}
local STAGES = {
  source = {version = "0.1.0", cap = 0},
  finite = {version = "0.2.0", cap = 1},
  relaxed = {version = "0.3.0", cap = 0},
}

local function fail(message) error("[mir5-f200-foreign-cap-baseline] " .. message) end

local function names(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, name in ipairs(expected) do
    if actual[index] ~= name then fail(label .. " differs at " .. tostring(index)) end
  end
end

function M.apply(stage)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown data-final stage") end
  if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "5.0.20000"
      or mods[FIXTURE] ~= expected.version or mods["space-age"] ~= nil then
    fail("unexpected F200 current-MIR fixture closure")
  end
  local row = data.raw.technology and data.raw.technology[NAME]
  if type(row) ~= "table" or row.name ~= NAME or row.type ~= "technology" or row.level ~= 1
      or row.upgrade ~= true or row.max_level ~= "infinite" or row.enabled == false
      or row.visible_when_disabled ~= nil or row.hidden ~= nil then
    fail("fresh gear identity or presentation differs")
  end
  names(row.prerequisites, SCIENCE, "gear prerequisites")
  local unit = row.unit
  if type(unit) ~= "table" or unit.count ~= nil or unit.count_formula ~= "8000*2^(L-1)" or unit.time ~= 60 then
    fail("gear cost or time differs")
  end
  if type(unit.ingredients) ~= "table" or #unit.ingredients ~= #SCIENCE then fail("gear science count differs") end
  for index, science in ipairs(SCIENCE) do
    local ingredient = unit.ingredients[index]
    if type(ingredient) ~= "table" or ingredient[1] ~= science or ingredient[2] ~= 1 or ingredient[3] ~= nil then
      fail("gear science differs at " .. tostring(index))
    end
  end
  local effect = row.effects and row.effects[1]
  if type(row.effects) ~= "table" or #row.effects ~= 1 or type(effect) ~= "table"
      or effect.type ~= "change-recipe-productivity" or effect.recipe ~= "iron-gear-wheel"
      or effect.change ~= 0.01 then
    fail("fixture-selected gear effect differs")
  end
  local startup = settings.startup
  local cap = startup and startup["ips-max-level-research_gears"]
  local effect_setting = startup and startup["ips-effect-per-level-research_gears"]
  if type(cap) ~= "table" or cap.value ~= expected.cap or type(effect_setting) ~= "table" or effect_setting.value ~= 1 then
    fail("fixture startup settings differ")
  end
end

return M
