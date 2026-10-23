if not mods["more-infinite-research"] then return end

local api = require("__more-infinite-research__.api.v1.data")
if api.get_version().major ~= 1 or not api.get_capabilities().recipe_productivity then return end

if data.raw.recipe["copper-cable"] == nil then error("MIR 5 API beta fixture: copper cable is absent after final fixes") end

local name = api.add_productivity({
  type = "technology",
  name = "mir-api-fixture-beta-cable-1",
  icon = "__base__/graphics/technology/electronics.png",
  icon_size = 256,
  prerequisites = {"electronics"},
  unit = {count = 50, ingredients = {{"automation-science-pack", 1}}, time = 20},
  max_level = 1,
  effects = {}
}, {"copper-cable"}, 0.01)

local technology = data.raw.technology[name]
local effects = technology and technology.effects or nil
if effects == nil or #effects ~= 1 or effects[1].type ~= "change-recipe-productivity"
  or effects[1].recipe ~= "copper-cable" or effects[1].change ~= 0.01 then
  error("MIR 5 API beta fixture: immediate cable productivity technology differs")
end
