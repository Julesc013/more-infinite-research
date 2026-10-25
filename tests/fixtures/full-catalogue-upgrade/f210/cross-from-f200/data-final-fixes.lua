-- This cross-engine successor refuses a Base F210 data stage that cannot
-- retain the F200 science-pack productivity identity.  It performs this
-- preflight before the shared fixture accelerates the one gear lab witness.
local FIXTURE = "mir-fixture-mir5-full-catalogue-upgrade"
local SCIENCE = "recipe-prod-research_science_pack_productivity-1"
local INGREDIENTS = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "military-science-pack", "utility-science-pack",
}
local EFFECTS = {
  "automation-science-pack", "chemical-science-pack", "logistic-science-pack",
  "military-science-pack", "production-science-pack", "utility-science-pack",
}

local function fail(message) error("[mir5-full-catalogue-upgrade] " .. message) end
local function exact_ingredients(value)
  if type(value) ~= "table" or #value ~= #INGREDIENTS then return false end
  for index, name in ipairs(INGREDIENTS) do
    local ingredient = value[index]
    if type(ingredient) ~= "table" or ingredient[1] ~= name or ingredient[2] ~= 1 then return false end
  end
  return true
end
local function exact_effects(value)
  if type(value) ~= "table" or #value ~= #EFFECTS then return false end
  for index, recipe in ipairs(EFFECTS) do
    local effect = value[index]
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= recipe or effect.change ~= .1 then return false end
  end
  return true
end

if mods.base ~= "2.1.23" or mods["more-infinite-research"] ~= "5.0.21000"
    or mods[FIXTURE] ~= "0.3.0" then
  fail("cross successor closure differs")
end
if mods["space-age"] ~= nil then fail("cross successor requires the Base target") end
for _, name in ipairs({"elevated-rails", "quality", "recycler"}) do
  if mods[name] ~= nil then fail("cross successor carries Space Age companions") end
end

local science = data.raw.technology and data.raw.technology[SCIENCE]
if type(science) ~= "table" or science.max_level ~= "infinite" or type(science.unit) ~= "table"
    or science.unit.count ~= nil or science.unit.count_formula ~= "8000*2^(L-1)" or science.unit.time ~= 120
    or not exact_ingredients(science.unit.ingredients) or not exact_effects(science.effects) then
  fail("F200 science productivity identity differs before F210 successor acceleration")
end
require("__mir-fixture-mir5-full-catalogue-upgrade__/fixture_data_final")
