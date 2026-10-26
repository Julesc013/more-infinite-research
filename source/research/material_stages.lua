-- Pure finite material-stage renderer shared by explicit compatibility
-- bindings.  Adapters retain selection and raw-prototype preflight; this
-- module only builds a fresh technology from one already accepted stage.
local cost = require("research.cost")

local M = {}
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function copy_names(names)
  local output = {}
  for index, name in ipairs(names) do output[index] = name end
  return output
end

local function ingredients(science)
  local output = {}
  for index, pack in ipairs(science) do output[index] = {pack, 1} end
  return output
end

local function effects(routes, effect_percent)
  local output = {}
  for index, route in ipairs(routes) do
    output[index] = {
      type = "change-recipe-productivity",
      recipe = route.recipe,
      change = effect_percent / 100,
    }
  end
  return output
end

local function continuation_cost(stream, stage, fail)
  local first = (stream.base_cost + 3 * stream.linear_increment) * (stream.growth_factor ^ 3)
  if not finite(first) then fail("material continuation cost is not finite") end
  return cost.continuation({
    base_cost = first,
    linear_increment = stream.base_cost,
    growth_factor = 1,
  }, stage.first_level, stage.predecessor_count, stage.previous_count)
end

function M.continuation_description(definition, stream)
  local useful = math.ceil(definition.productivity_ceiling * 100 / stream.effect_percent)
  local limit = stream.max_level > 0 and math.min(stream.max_level, useful) or useful
  return {"", {"technology-description.more-infinite-research.recipe_productivity"}, "\n",
    {"mod-setting-name.ips-max-level-stream", {"", {"description.productivity-bonus"}, ": ",
      {"item-name." .. definition.item}}}, ": ", tostring(limit)}
end

function M.technology(definition, stage, stream, fail)
  local output = {
    type = "technology",
    name = stage.id,
    icons = {
      {icon = definition.icon, icon_size = definition.icon_size},
      {icon = OVERLAY, icon_size = 128, scale = 0.5, shift = {50, 50}, floating = true},
    },
    localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name." .. definition.item}},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    level = stage.first_level or 1,
    upgrade = true,
    max_level = stage.max_level,
    order = stage.order,
    prerequisites = copy_names(stage.prerequisites),
    effects = effects(definition.routes, stream.effect_percent),
    unit = {
      count_formula = stage.first_level and continuation_cost(stream, stage, fail)
        or cost.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = stream.research_time,
      ingredients = ingredients(stage.science),
    },
  }
  if stage.show_levels_info ~= nil then output.show_levels_info = stage.show_levels_info end
  if stage.visible_when_disabled ~= nil then output.visible_when_disabled = stage.visible_when_disabled end
  if stream.enabled == false then output.enabled = false end
  return output
end

return M
