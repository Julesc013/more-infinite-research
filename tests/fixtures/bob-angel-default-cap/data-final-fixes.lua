-- Read-only verification after MIR publication. No costs are accelerated.
local cases = require("__mir-fixture-mir5-bob-angel-default-cap__/cases")
local function fail(message) error("[mir5-bob-angel-default-cap data] " .. message) end
if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "5.0.20000"
    or mods["mir-fixture-mir5-bob-angel-default-cap"] ~= "0.1.0" then
  fail("fixture closure differs")
end
for _, family in ipairs(cases) do
  for _, name in ipairs(family.recipes) do
    local recipe = data.raw.recipe and data.raw.recipe[name]
    if recipe == nil or recipe.maximum_productivity ~= 3 then fail("explicit cap changed: " .. name) end
  end
  for _, stage in ipairs({{suffix="1", maximum=3}, {suffix="4", maximum="infinite"}}) do
    local name = "recipe-prod-" .. family.key .. "-" .. stage.suffix
    local technology = data.raw.technology and data.raw.technology[name]
    local effects = technology and technology.effects
    if technology == nil or technology.type ~= "technology" or technology.enabled == false
        or technology.max_level ~= stage.maximum or type(effects) ~= "table" or #effects ~= #family.recipes then
      fail("material technology differs: " .. name)
    end
    for index, recipe in ipairs(family.recipes) do
      local effect = effects[index]
      if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
          or effect.recipe ~= recipe or effect.change ~= .02 then fail("material effect differs: " .. name) end
    end
  end
end
