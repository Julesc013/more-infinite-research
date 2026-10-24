local private_target = require("platform.target")
local technology_name = "mir-api-namespace-beta-cable-1"
local recipe_name = "copper-cable"
local expected_change = 0.02

local function fail(message)
  error("[mir5-api-namespace-beta] " .. message)
end

local function assert_private_target()
  if private_target.owner ~= "mir-fixture-mir5-api-namespace-beta"
      or private_target.recipe_productivity ~= false then
    fail("private target identity differs")
  end
end

script.on_init(function()
  assert_private_target()
  local force = game.forces.player
  local technology = force and force.technologies[technology_name]
  local effect = technology and technology.prototype.effects[1]
  if effect == nil or effect.type ~= "change-recipe-productivity" or effect.recipe ~= recipe_name
      or effect.change ~= expected_change then
    fail("native cable productivity technology differs")
  end
  log("[MIR5_API_NAMESPACE_BETA] RESULT " .. helpers.table_to_json({
    case="api-namespace-collision", stage="init", status="passed", consumer=private_target.owner,
    technology=technology_name, recipe=recipe_name, change=expected_change
  }))
end)
