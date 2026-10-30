-- Finite F200 Space Age + BobTech delta. The ordinary Base/Space Age
-- catalogue remains the source of shared authored semantics; this module only
-- declares the three independently observed combined-profile identities and
-- the three absent identities. It contains no material-stage selection and no
-- profile-wide discovery.
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local M = {}

local function effect(recipe, scale)
  return {recipe=recipe, scale=scale or 1}
end

local function tuning()
  return {
    base_cost=8000, effect_percent=10, enabled=true, growth_factor=2,
    linear_increment=0, max_level=0, research_time=60,
  }
end

M.omit = {
  research_oil_cracking_productivity=true,
}

M.additions = {
  {
    key="research_armor_components", family="research_armor_components", kind="productivity",
    science="science_automation_logistic_chemical_production_military_metallurgic_space", prerequisites={},
    effects={effect("bob-mech-armor-plate", 0.2)},
    icon="__base__/graphics/technology/power-armor.png", icon_size=256, overlay=OVERLAY,
    localised_name={"technology-name.more-infinite-research.research_armor_components", {"technology-name.power-armor"}},
    localised_description={"technology-description.more-infinite-research.recipe_productivity"},
    order="p[research_armor_components]", tuning=tuning(),
    setting_order="b-100-armor-component-productivity-stream-research_armor_components-",
  },
  {
    key="research_plastic", family="research_plastic", kind="productivity",
    science="science_automation_logistic_chemical_production_agricultural", prerequisites={},
    effects={effect("angels-solid-plastic")},
    icon="__space-age__/graphics/technology/plastics-productivity.png", icon_size=256, overlay=OVERLAY,
    localised_name={"technology-name.more-infinite-research.research_plastic", {"item-name.plastic-bar"}},
    localised_description={"technology-description.more-infinite-research.recipe_productivity"},
    order="p[research_plastic]", tuning=tuning(),
    setting_order="b-100-plastic-productivity-stream-research_plastic-",
  },
  {
    key="research_steel", family="research_steel", kind="productivity",
    science="science_automation_logistic_chemical_production", prerequisites={},
    effects={effect("angels-plate-steel"), effect("angels-plate-steel-2")},
    icon="__space-age__/graphics/technology/steel-plate-productivity.png", icon_size=256, overlay=OVERLAY,
    localised_name={"technology-name.more-infinite-research.research_steel", {"item-name.steel-plate"}},
    localised_description={"technology-description.more-infinite-research.recipe_productivity"},
    order="p[research_steel]", tuning=tuning(),
    setting_order="b-100-steel-plate-productivity-stream-research_steel-",
  },
}

local REQUIRED_RECIPES = {
  "angels-solid-plastic", "angels-plate-steel", "angels-plate-steel-2", "bob-mech-armor-plate",
}

local REQUIRED_TECHNOLOGIES = {
  "bob-tankotron", "braking-force-6", "braking-force-7", "laser-shooting-speed-6", "laser-shooting-speed-7",
  "research-speed-5", "research-speed-6", "weapon-shooting-speed-5", "weapon-shooting-speed-6",
}

local REQUIRED_LABS = {"lab", "biolab", "bob-lab-2", "bob-lab-alien"}

local function require_table(group, name, label)
  local row = type(group) == "table" and group[name] or nil
  if type(row) ~= "table" then error("MIR F200 combined Bob/Angel preflight missing " .. label .. " " .. name, 3) end
  return row
end

local function has_recipe_product(recipe, name)
  for _, result in ipairs(recipe.results or {}) do
    if type(result) == "table" and (result.type == nil or result.type == "item") and result.name == name then return true end
  end
  return false
end

local function contains(values, name)
  for _, value in ipairs(values or {}) do if value == name then return true end end
  return false
end

function M.preflight(raw)
  if type(raw) ~= "table" then error("MIR F200 combined Bob/Angel preflight requires data.raw", 2) end
  for _, name in ipairs(REQUIRED_RECIPES) do require_table(raw.recipe, name, "recipe") end
  for _, name in ipairs(REQUIRED_TECHNOLOGIES) do require_table(raw.technology, name, "technology") end
  for _, name in ipairs(REQUIRED_LABS) do
    local lab = require_table(raw.lab, name, "lab")
    if type(lab.inputs) ~= "table" then error("MIR F200 combined Bob/Angel preflight lab inputs changed: " .. name, 2) end
  end
  local armor = raw.recipe["bob-mech-armor-plate"]
  if armor.enabled ~= false or armor.allow_productivity ~= true or not has_recipe_product(armor, "bob-mech-armor-plate") then
    error("MIR F200 combined Bob/Angel preflight armor route changed", 2)
  end
  local tankotron = raw.technology["bob-tankotron"]
  local unlocked = false
  for _, effect_row in ipairs(tankotron.effects or {}) do
    if type(effect_row) == "table" and effect_row.type == "unlock-recipe" and effect_row.recipe == "bob-mech-armor-plate" then
      unlocked = true
    end
  end
  if not unlocked or not contains(tankotron.prerequisites, "bob-tungsten-processing") then
    error("MIR F200 combined Bob/Angel preflight armor owner changed", 2)
  end
  if not has_recipe_product(raw.recipe["angels-solid-plastic"], "plastic-bar")
      or not has_recipe_product(raw.recipe["angels-plate-steel"], "steel-plate")
      or not has_recipe_product(raw.recipe["angels-plate-steel-2"], "steel-plate") then
    error("MIR F200 combined Bob/Angel preflight named product route changed", 2)
  end
end

return M
