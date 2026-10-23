local M = {}
local catalogue = require("research.catalogue")

local function number_text(value)
  assert(type(value) == "number" and value == value and value < math.huge and value >= 0,
    "MIR invalid research cost value")
  if value == math.floor(value) then return tostring(math.floor(value)) end
  return string.format("%.15g", value)
end

-- The published gear model scales the linear term with the exponential term.
-- This is its native formula, not an expression evaluator.
function M.cost(base, increment, growth)
  assert(base >= 1 and increment >= 0 and growth >= 1 and growth <= 1000, "MIR invalid research cost bounds")
  local b, d, g = number_text(base), number_text(increment), number_text(growth)
  if growth == 1 then
    if increment == 0 then return b end
    return b .. "+" .. d .. "*(L-1)"
  end
  if increment == 0 then return b .. "*" .. g .. "^(L-1)" end
  return "(" .. b .. "+" .. d .. "*(L-1))*" .. g .. "^(L-1)"
end

function M.gears(values)
  return {
    type = "technology", name = catalogue.gear_id(),
    icons = {
      {icon = "__base__/graphics/icons/iron-gear-wheel.png", icon_size = 64},
      {icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
        icon_size = 128, scale = 0.5, shift = {50, 50}, floating = true}
    },
    localised_name = {"technology-name.more-infinite-research.research_gears", {"item-name.iron-gear-wheel"}},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    upgrade = true, max_level = "infinite", enabled = values.enabled,
    order = "p[research_gears]",
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    effects = {{type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = values.effect_percent / 100}},
    unit = {
      count_formula = M.cost(values.base_cost, values.linear_increment, values.growth_factor),
      time = values.research_time,
      ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"production-science-pack", 1}}
    }
  }
end

return M
