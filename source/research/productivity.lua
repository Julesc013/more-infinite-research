local M = {}
local catalogue = require("research.catalogue")
local cost = require("research.cost")
local BASE_ICON = "__base__/graphics/icons/iron-gear-wheel.png"
local DEFAULT_RECIPES = {"iron-gear-wheel"}

-- The published gear model scales the linear term with the exponential term.
-- This is its native formula, not an expression evaluator.
function M.cost(base, increment, growth)
  return cost.cost(base, increment, growth)
end

local function copy_binding(binding)
  if binding == nil then return BASE_ICON, {DEFAULT_RECIPES[1]} end
  assert(type(binding) == "table" and getmetatable(binding) == nil,
    "MIR invalid gear binding")
  assert(type(binding.icon) == "string" and binding.icon ~= "",
    "MIR invalid gear binding icon")
  assert(type(binding.recipes) == "table" and getmetatable(binding.recipes) == nil,
    "MIR invalid gear binding recipes")
  local count = #binding.recipes
  assert(count > 0, "MIR gear binding has no recipes")
  for key in pairs(binding.recipes) do
    assert(type(key) == "number" and key >= 1 and key <= count and key == math.floor(key),
      "MIR gear binding recipes must be dense")
  end
  local recipes = {}
  for index = 1, count do
    assert(type(binding.recipes[index]) == "string" and binding.recipes[index] ~= "",
      "MIR gear binding has an invalid recipe")
    recipes[index] = binding.recipes[index]
  end
  return binding.icon, recipes
end

function M.gears(values, binding)
  local icon, recipes = copy_binding(binding)
  local effects = {}
  for index = 1, #recipes do
    effects[index] = {type = "change-recipe-productivity", recipe = recipes[index], change = values.effect_percent / 100}
  end
  local output = {
    type = "technology", name = catalogue.gear_id(),
    icons = {
      {icon = icon, icon_size = 64},
      {icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
        icon_size = 128, scale = 0.5, shift = {50, 50}, floating = true}
    },
    localised_name = {"technology-name.more-infinite-research.research_gears", {"item-name.iron-gear-wheel"}},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    level = 1, upgrade = true, max_level = "infinite",
    order = "p[research_gears]",
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    effects = effects,
    unit = {
      count_formula = M.cost(values.base_cost, values.linear_increment, values.growth_factor),
      time = values.research_time,
      ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"production-science-pack", 1}}
    }
  }
  if values.enabled == false then output.enabled = false end
  return output
end

return M
