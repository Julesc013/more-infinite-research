-- Private input intervention before MIR's data-final-fixes admission. Check
-- every named original route before setting only its effective-default cap.
local cases = require("__mir-fixture-mir5-bob-angel-default-cap__/cases")
local function fail(message) error("[mir5-bob-angel-default-cap input] " .. message) end
if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "5.0.20000"
    or mods["mir-fixture-mir5-bob-angel-default-cap"] ~= "0.1.0" then
  fail("fixture closure differs")
end
for _, family in ipairs(cases) do
  for _, name in ipairs(family.recipes) do
    local recipe = data.raw.recipe and data.raw.recipe[name]
    if type(recipe) ~= "table" or recipe.maximum_productivity ~= nil then
      fail("captured input differs: " .. name)
    end
  end
end
for _, family in ipairs(cases) do
  for _, name in ipairs(family.recipes) do data.raw.recipe[name].maximum_productivity = 3 end
end
