-- Direct native technology tables for the two explicitly authored Space Age
-- scripted effects. Runtime ownership is deliberately outside this data-stage
-- module; the `nothing` effects remain exact historical player-facing rows.
local cost = require("research.productivity").cost

local M = {}

local AGRICULTURE_ID = "recipe-prod-research_agricultural_growth_speed-1"
local SPOILAGE_ID = "recipe-prod-research_spoilage_preservation-1"

local function effect_text(value)
  if value == math.floor(value) then return tostring(math.floor(value)) end
  return string.format("%.15g", value)
end

local function effect(icon, icon_size, locale, values)
  return {{
    type = "nothing",
    effect_description = {locale, effect_text(values.effect_percent)},
    icons = {{icon = icon, icon_size = icon_size}}
  }}
end

local function direct_technology(id, values, binding, spec)
  if type(values) ~= "table" or type(binding) ~= "table" then
    error("MIR scripted-effect technology needs resolved values and a Space Age binding", 3)
  end
  local output = {
    type = "technology", name = id,
    localised_name = spec.localised_name,
    localised_description = spec.localised_description,
    icons = spec.icons,
    effects = effect(spec.effect_icon, spec.effect_icon_size, spec.effect_locale, values),
    prerequisites = binding.prerequisites,
    unit = {
      ingredients = binding.ingredients,
      count_formula = cost(values.base_cost, values.linear_increment, values.growth_factor),
      time = values.research_time
    },
    max_level = "infinite", order = spec.order, level = 1, upgrade = true
  }
  -- Omit Factorio's true default so the published default row stays exact.
  if values.enabled == false then output.enabled = false end
  return output
end

function M.agriculture(values, binding)
  return direct_technology(AGRICULTURE_ID, values, binding, {
    localised_name = {"technology-name.more-infinite-research.research_agricultural_growth_speed",
      {"technology-name.agriculture"}},
    localised_description = {"technology-description.more-infinite-research.agricultural_growth_speed"},
    icons = {
      {icon = "__space-age__/graphics/technology/agriculture.png", icon_size = 256},
      {icon = "__core__/graphics/icons/technology/constants/constant-speed.png", icon_size = 128,
        scale = 0.5, shift = {50, 50}, floating = true}
    },
    effect_icon = "__space-age__/graphics/technology/agriculture.png", effect_icon_size = 256,
    effect_locale = "modifier-description.more-infinite-research.agricultural_growth_speed",
    order = "p[research_agricultural_growth_speed]"
  })
end

function M.spoilage(values, binding)
  return direct_technology(SPOILAGE_ID, values, binding, {
    localised_name = {"technology-name.more-infinite-research.research_spoilage_preservation",
      {"item-name.spoilage"}},
    localised_description = {"", {"technology-description.more-infinite-research.spoilage_preservation"},
      "\n\n", {"mod-setting-description.mir-note-experimental-spoilage"}},
    icons = {
      {icon = "__space-age__/graphics/icons/spoilage.png", icon_size = 64},
      {icon = "__core__/graphics/icons/technology/constants/constant-speed.png", icon_size = 128,
        scale = 0.5, shift = {50, 50}, floating = true}
    },
    effect_icon = "__space-age__/graphics/icons/spoilage.png", effect_icon_size = 64,
    effect_locale = "modifier-description.more-infinite-research.spoilage_preservation",
    order = "p[research_spoilage_preservation]"
  })
end

function M.technologies(values, bindings)
  if type(bindings) ~= "table" then error("MIR scripted-effect bindings must be a table", 2) end
  return {
    M.agriculture(values.agricultural_growth_speed, bindings.agriculture),
    M.spoilage(values.spoilage_preservation, bindings.spoilage)
  }
end

return M
