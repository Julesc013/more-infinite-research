-- Fresh-world read-only init witness. No state seeding or runtime maintenance.
local cases = require("__mir-fixture-mir5-bob-angel-default-cap__/cases")
local function fail(message) error("[mir5-bob-angel-default-cap runtime] " .. message) end
local function near(value, expected)
  return type(value) == "number" and math.abs(value - expected) <= .0000001
end
script.on_init(function()
  local active = script.active_mods
  if active.base ~= "2.0.77" or active["more-infinite-research"] ~= "5.0.20000"
      or active["mir-fixture-mir5-bob-angel-default-cap"] ~= "0.1.0" then
    fail("fixture closure differs")
  end
  local force = game.forces.player
  if force == nil or force.valid == false then fail("player force is absent") end
  local technology_count, recipe_count = 0, 0
  for _, family in ipairs(cases) do
    for _, recipe_name in ipairs(family.recipes) do
      local recipe = force.recipes[recipe_name]
      if recipe == nil or recipe.valid == false or not near(recipe.productivity_bonus, 0) then
        fail("fresh native recipe differs: " .. recipe_name)
      end
      recipe_count = recipe_count + 1
    end
    for _, stage in ipairs({{level=1, maximum=3}, {level=4, maximum=4294967295}}) do
      local name = "recipe-prod-" .. family.key .. "-" .. stage.level
      local row = force.technologies[name]
      local prototype = row and row.prototype
      local effects = prototype and prototype.effects
      if row == nil or row.valid == false or row.name ~= name or row.level ~= stage.level
          or row.researched ~= false or row.enabled ~= true or prototype == nil
          or prototype.max_level ~= stage.maximum or type(effects) ~= "table" or #effects ~= #family.recipes then
        fail("fresh native technology differs: " .. name)
      end
      for index, recipe in ipairs(family.recipes) do
        local effect = effects[index]
        if effect.type ~= "change-recipe-productivity" or effect.recipe ~= recipe or not near(effect.change, .02) then
          fail("native effect differs: " .. name)
        end
      end
      technology_count = technology_count + 1
    end
  end
  log("[MIR5_F200_DEFAULT_CAP] RESULT " .. helpers.table_to_json({
    case="bob-angel-default-cap", stage="init", status="passed",
    qualification="representative-native-default-cap-startup-only",
    families=#cases, technologies=technology_count, recipes=recipe_count,
    fresh_recipe_productivity_bonus=0,
  }))
end)
