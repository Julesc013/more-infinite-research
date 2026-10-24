local private_target = require("platform.target")
local technology_name = "mir-api-namespace-alpha-gears-1"
local recipe_name = "iron-gear-wheel"
local expected_change = 0.01

local function fail(message)
  error("[mir5-api-namespace-alpha] " .. message)
end

local function assert_private_target()
  if private_target.owner ~= "mir-fixture-mir5-api-namespace-alpha"
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
    fail("native gear productivity technology differs")
  end
  log("[MIR5_API_NAMESPACE_ALPHA] RESULT " .. helpers.table_to_json({
    case="api-namespace-collision", status="passed", consumer=private_target.owner,
    technology=technology_name, recipe=recipe_name, change=expected_change
  }))
end)