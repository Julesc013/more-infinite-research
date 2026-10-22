-- This companion is intentionally inert for the published 4.6 source arm.
-- Its target-only alteration is a representative 2.1.23 Space Age input, not
-- a claim about the official Space Age prototype set or an acquisition route.
local mir_version = mods and mods["more-infinite-research"]
if mir_version == "4.7.21000" then
  local satellite = data.raw.item and data.raw.item.satellite
  local recipe = data.raw.recipe and data.raw.recipe["space-science-pack"]
  local technology = data.raw.technology and data.raw.technology["space-science-pack"]
  if type(recipe) ~= "table" or type(technology) ~= "table" then
    error("MIR trigger-output representative requires Space Age space science inputs")
  end
  if type(satellite) ~= "table" then
    -- Space Age removes the base satellite item.  The representative owns this
    -- minimal target-only replacement; it is not a player-facing production
    -- path and only supplies the typed trigger payload fact under test.
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
