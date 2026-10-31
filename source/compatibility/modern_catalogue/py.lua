-- Exact F200 Py HighTech definition delta.  The product collector supplies
-- the complete named route set in one pass; this module authors identity,
-- science, presentation and the bounded expected result only.
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local M = {}

-- These two Base identities are deliberately absent in both retained Py
-- F200 catalogues.  The current raw oil recipes remain named preflight facts,
-- but their presence does not turn an omitted historical identity into a new
-- published stream.
M.omitted_base_families = {
  research_oil_cracking_productivity = true,
  research_oil_processing_productivity = true,
}

-- Rebuild only the recorded ordinary vectors through the existing single
-- collector pass.  The collector keeps its typed yield and return-route
-- checks; these profile maps only remove Base seed effects before that pass.
M.coal_replacement_families = {
  research_batteries = true,
  research_concrete = true,
  research_explosives = true,
  research_iron = true,
  research_lubricant_productivity = true,
  research_plastic = true,
  research_sulfur = true,
}

M.hightech_replacement_families = {
  research_batteries = true,
  research_belts = true,
  research_concrete = true,
  research_explosives = true,
  research_gears = true,
  research_inserters = true,
  research_iron = true,
  research_iron_sticks = true,
  research_lubricant_productivity = true,
  research_modules = true,
  research_plastic = true,
  research_science_pack_productivity = true,
  research_steel = true,
  research_sulfur = true,
  research_sulfuric_acid_productivity = true,
}

-- Exact published exclusions from otherwise retained Base product bindings.
-- They are recipe identities, not result-name rules, so a later foreign
-- recipe cannot accidentally inherit an omission.
M.coal_excluded_recipes = {
  research_batteries = {"battery"},
  research_explosives = {"explosives"},
  research_plastic = {"plastic-bar"},
  research_sulfur = {"aromatics-to-lubricant", "sulfur"},
}

M.hightech_excluded_recipes = {
  research_batteries = {"battery"},
  research_explosives = {"explosives"},
  research_modules = {"rennea-mk02-breeding", "rennea-mk03-breeding", "rennea-mk04-breeding"},
  research_plastic = {"plastic-bar"},
  research_sulfur = {"aromatics-to-lubricant", "sulfur"},
}

M.hightech_definition_overrides = {
  research_advanced_circuit = {icon="__pyhightechgraphics__/graphics/technology/advanced-electronics.png", icon_size=128},
  research_belts = {science="science_automation_logistic_chemical_production_space"},
  research_bullets = {science="science_automation_logistic_chemical_production_military_space"},
  research_concrete = {science="science_automation_logistic_chemical_production_space"},
  research_copper = {icon="__pyraworesgraphics__/graphics/icons/copper-plate.png", icon_size=32},
  research_copper_cable = {icon="__pyraworesgraphics__/graphics/icons/copper-cable.png", icon_size=32},
  research_electric_energy = {icon="__pyindustrygraphics__/graphics/technology/accumulator-mk01.png", icon_size=128},
  research_electronic_circuit = {icon="__pyhightechgraphics__/graphics/technology/vacuum-tube-electronics.png", icon_size=128},
  research_flamethrower_shooting_speed = {science="science_automation_logistic_chemical_production_military_space"},
  research_grenades = {science="science_automation_logistic_chemical_production_military_space"},
  research_heavy_ammo = {science="science_automation_logistic_chemical_production_military_space"},
  research_inserters = {science="science_automation_logistic_chemical_production_space"},
  research_iron = {icon="__pyraworesgraphics__/graphics/icons/iron-plate.png", icon_size=32},
  research_lab_productivity = {science="science_automation_logistic_military_chemical_production_utility_space"},
  research_landfill = {science="science_automation_logistic_chemical_production_space"},
  research_plastic = {icon="__pyhightechgraphics__/graphics/technology/plastics-mk01.png", icon_size=128},
  research_rails = {science="science_automation_logistic_chemical_production_space"},
  research_robot_battery = {science="science_automation_logistic_chemical_production_space"},
  research_science_pack_productivity = {
    science="science_automation_logistic_chemical_production_military_utility_space_py",
    icon="__pyhightechgraphics__/graphics/technology/quantum-computing.png", icon_size=128,
  },
  research_walls = {science="science_automation_logistic_chemical_production_military_space"},
}

M.breeding_recipes = {
  "arqad-mk02-breeding", "arqad-mk03-breeding", "arqad-mk04-breeding",
  "auog-pup-breeding-1", "auog-pup-breeding-2", "auog-pup-breeding-3",
  "auog-pup-breeding-4", "auog-pup-breeding-5",
  "bhoddos-culture-mk01", "bhoddos-culture-mk02", "bhoddos-culture-mk03", "bhoddos-culture-mk04",
  "bhoddos-spore-mk02-breeding", "bhoddos-spore-mk03-breeding", "bhoddos-spore-mk04-breeding",
  "navens-culture-mk01", "navens-culture-mk02", "navens-culture-mk03", "navens-culture-mk04",
  "rennea-mk02-breeding", "rennea-mk03-breeding", "rennea-mk04-breeding",
  "sponge-culture-mk01", "sponge-culture-mk02", "sponge-culture-mk03", "sponge-culture-mk04",
  "ulric-mk02-breeding", "ulric-mk03-breeding", "ulric-mk04-breeding",
  "yaedols-culture-mk01", "yaedols-culture-mk02", "yaedols-culture-mk03", "yaedols-culture-mk04",
}

local function definition(key, recipe, icon, icon_size, locale)
  return {
    key=key, family=key, kind="productivity",
    science="science_automation_logistic_chemical_production", prerequisites={},
    effects={{recipe=recipe, scale=1}},
    icon=icon, icon_size=icon_size, overlay=OVERLAY,
    localised_name={"technology-name.more-infinite-research." .. key, locale},
    localised_description={"technology-description.more-infinite-research.recipe_productivity"},
    order="p[" .. key .. "]",
  }
end

function M.definitions()
  return {
    definition("research_breeding", "arqad-mk02-breeding",
      "__pyalienlifegraphics__/graphics/icons/fish.png", 32, {"technology-name.fish-breeding"}),
    definition("research_supercapacitor", "supercapacitor",
      "__pyhightechgraphics__/graphics/technology/supercapacitor.png", 128, {"item-name.supercapacitor"}),
    definition("research_superconductor", "superconductor",
      "__pyhightechgraphics__/graphics/technology/superconductor.png", 128, {"item-name.superconductor"}),
  }
end

function M.required_targets()
  return {
    research_breeding={
      "arqad-mk02-breeding", "arqad-mk03-breeding", "arqad-mk04-breeding",
      "auog-pup-breeding-1", "auog-pup-breeding-2", "auog-pup-breeding-3",
      "auog-pup-breeding-4", "auog-pup-breeding-5",
      "bhoddos-culture-mk01", "bhoddos-culture-mk02", "bhoddos-culture-mk03", "bhoddos-culture-mk04",
      "bhoddos-spore-mk02-breeding", "bhoddos-spore-mk03-breeding", "bhoddos-spore-mk04-breeding",
      "navens-culture-mk01", "navens-culture-mk02", "navens-culture-mk03", "navens-culture-mk04",
      "rennea-mk02-breeding", "rennea-mk03-breeding", "rennea-mk04-breeding",
      "sponge-culture-mk01", "sponge-culture-mk02", "sponge-culture-mk03", "sponge-culture-mk04",
      "ulric-mk02-breeding", "ulric-mk03-breeding", "ulric-mk04-breeding",
      "yaedols-culture-mk01", "yaedols-culture-mk02", "yaedols-culture-mk03", "yaedols-culture-mk04",
    },
    research_supercapacitor={"supercapacitor"},
    research_superconductor={"superconductor"},
  }
end

-- Base has no broad supercapacitor/superconductor selector. These two named
-- routes enter the existing single collector pass only for the preflighted Py
-- HighTech F200 profile.
function M.product_bindings()
  return {
    {family="research_supercapacitor", weight=1, products={{type="item", name="supercapacitor"}}},
    {family="research_superconductor", weight=1, products={{type="item", name="superconductor"}}},
    {family="research_science_pack_productivity", weight=1, reject_explicit_productivity_denial=true,
      products={
        {type="item", name="automation-science-pack"}, {type="item", name="chemical-science-pack"},
        {type="item", name="logistic-science-pack"}, {type="item", name="military-science-pack"},
        {type="item", name="production-science-pack"}, {type="item", name="py-science-pack-1"},
        {type="item", name="py-science-pack-2"}, {type="item", name="py-science-pack-3"},
        {type="item", name="py-science-pack-4"}, {type="item", name="random-science-pack"},
        {type="item", name="space-science-pack"}, {type="item", name="utility-science-pack"},
      }},
  }
end

local function recipe_allowed(recipe)
  return type(recipe) == "table" and recipe.enabled == false and recipe.hidden ~= true
    and recipe.allow_productivity ~= false and recipe.maximum_productivity == 1000000
end

local function has_named_result(recipe, name)
  local rows = recipe.results or (recipe.result and {{name=recipe.result, amount=recipe.result_count or 1}}) or {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and (row.name or row[1]) == name then return true end
  end
  return false
end

local function owner_unlocks(owner, recipe)
  if type(owner) ~= "table" or owner.enabled == false then return false end
  local count = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == recipe then
      if effect.type ~= "unlock-recipe" then return false end
      count = count + 1
    end
  end
  return count == 1
end

function M.preflight(raw)
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table" then
    error("MIR F200 Py HighTech raw prototypes are unavailable", 2)
  end
  for _, name in ipairs(M.breeding_recipes) do
    if not recipe_allowed(raw.recipe[name]) then
      error("MIR F200 Py HighTech breeding route changed: " .. name, 2)
    end
  end
  for _, name in ipairs({"supercapacitor", "superconductor"}) do
    local recipe = raw.recipe[name]
    if not recipe_allowed(recipe) or not has_named_result(recipe, name)
        or not owner_unlocks(raw.technology[name], name) then
      error("MIR F200 Py HighTech route changed: " .. name, 2)
    end
  end
end

return M
