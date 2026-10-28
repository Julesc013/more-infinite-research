local M = {}

local SCIENCE = {
  "automation-science-pack", "chemical-science-pack", "logistic-science-pack",
  "military-science-pack", "utility-science-pack",
}

local function fail(message)
  error("[mir5-f100-f110-laser-transition] " .. message)
end

local function assert_effects(value, ammo)
  if type(value.effects) ~= "table" or #value.effects ~= 1 then
    fail("laser effect cardinality differs")
  end
  local effect = value.effects[1]
  if type(effect) ~= "table" or effect.type ~= "gun-speed"
      or effect.ammo_category ~= ammo or effect.modifier ~= .75 then
    fail("laser effect differs")
  end
end

local function assert_unit(value, formula, research_time)
  local unit = value.unit
  if type(unit) ~= "table" or unit.count ~= nil
      or unit.count_formula ~= formula or unit.time ~= research_time
      or type(unit.ingredients) ~= "table" or #unit.ingredients ~= #SCIENCE then
    fail("laser research unit differs")
  end
  for index, name in ipairs(SCIENCE) do
    local ingredient = unit.ingredients[index]
    if type(ingredient) ~= "table" or ingredient[1] ~= name or ingredient[2] ~= 1 then
      fail("laser research science differs")
    end
  end
end

function M.apply(spec)
  if type(spec) ~= "table" or type(spec.direct) ~= "string"
      or type(spec.ammo) ~= "string" or type(spec.maximum) ~= "number"
      or type(spec.formula) ~= "string" or type(spec.research_time) ~= "number" then
    fail("fixture data specification differs")
  end
  local technology = data.raw.technology[spec.direct]
  if type(technology) ~= "table" or technology.type ~= "technology"
      or technology.name ~= spec.direct or technology.level ~= 8 or technology.upgrade ~= true
      or technology.max_level ~= spec.maximum or technology.enabled == false then
    fail("laser identity or finite cap differs")
  end
  assert_effects(technology, spec.ammo)
  assert_unit(technology, spec.formula, spec.research_time)

  -- Fixture-only acceleration follows the exact source shape checks above.
  technology.unit.count_formula = nil
  technology.unit.count = 1
  technology.unit.time = 1
end

return M
