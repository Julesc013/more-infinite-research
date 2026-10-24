local private_target = require("platform.target")
if private_target.owner ~= "mir-fixture-mir5-api-namespace-beta"
    or private_target.recipe_productivity ~= false then
  error("MIR API namespace beta fixture: private target identity differs")
end

local api = require("__more-infinite-research__.api.v1.data")
local version = api.get_version()
local capabilities = api.get_capabilities()
if version.major ~= 1 or version.minor ~= 0 or version.product ~= "5.0.21000"
    or capabilities.recipe_productivity ~= true then
  error("MIR API namespace beta fixture: public target metadata differs")
end

local name = api.add_productivity({
  type = "technology",
  name = "mir-api-namespace-beta-cable-1",
  icon = "__base__/graphics/technology/electronics.png",
  icon_size = 256,
  prerequisites = {"electronics"},
  unit = {count = 50, ingredients = {{"automation-science-pack", 1}}, time = 20},
  max_level = 1,
  effects = {}
}, {"copper-cable"}, 0.02)

local technology = data.raw.technology[name]
local effect = technology and technology.effects and technology.effects[1]
if name ~= "mir-api-namespace-beta-cable-1" or effect == nil
    or effect.type ~= "change-recipe-productivity" or effect.recipe ~= "copper-cable"
    or effect.change ~= 0.02 then
  error("MIR API namespace beta fixture: immediate cable productivity differs")
end
if require("platform.target") ~= private_target then
  error("MIR API namespace beta fixture: private target module identity changed")
end