-- This fixture is an explicit expected-old-startup-failure input only.
-- It is never selected by the successful source-save/migration scenario.
local mir_version = mods and mods["more-infinite-research"]
if mir_version == "4.6.21000" then
  local satellite = data.raw.item and data.raw.item.satellite
  local recipe = data.raw.recipe and data.raw.recipe["space-science-pack"]
  local technology = data.raw.technology and data.raw.technology["space-science-pack"]
  if type(recipe) ~= "table" or type(technology) ~= "table" then
    error("MIR trigger-output source override requires Space Age space science inputs")
  end
  if type(satellite) ~= "table" then
    data:extend({{
      type = "item", name = "satellite", icon = "__base__/graphics/icons/satellite.png",
      icon_size = 64, stack_size = 1
    }})
    satellite = data.raw.item.satellite
  end
  satellite.rocket_launch_products = {{type = "item", name = "space-science-pack", amount = 1000}}
  recipe.enabled = false
  recipe.result = nil
  recipe.result_count = nil
  recipe.results = {{type = "item", name = "space-science-pack", amount = 1}}
  technology.unit = nil
  technology.research_trigger = {type = "send-item-to-orbit", item = "satellite"}
  technology.prerequisites = {"rocket-silo"}
  technology.effects = {}
end
