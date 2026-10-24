-- Fixed F200 ATAN productivity definitions. This module is pure authored data:
-- it neither reads prototypes nor decides whether a mod profile is admissible.
-- The compatibility adapter validates the named route variants and returns
-- fresh definitions only for exact captured F200 profiles.
local M = {}

M.runtime_rows = {
  {family="research_air_scrubbing_clean_filter", recipe="atan-pollution-filter"},
  {family="research_ash_separation", recipe="atan-ash-seperation"},
}

local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function tuning(research_time)
  return {
    base_cost = 8000,
    effect_percent = 5,
    enabled = true,
    growth_factor = 2,
    linear_increment = 0,
    max_level = 0,
    research_time = research_time,
  }
end

local function filter_route(item, icon, recipe, owner, owner_prerequisites, owner_science)
  return {
    item = item,
    item_icon = icon,
    item_icon_size = "default",
    recipe = recipe,
    category = "organic-or-assembling",
    energy_required = 2,
    enabled = false,
    allow_productivity = "not-false",
    maximum_productivity = "omitted",
    ingredients = {
      {type = "item", name = "carbon", amount = 2},
      {type = "item", name = "steel-plate", amount = 1},
      {type = "item", name = "plastic-bar", amount = 1},
    },
    results = {{type = "item", name = item, amount = 1}},
    owner = owner,
    owner_prerequisites = owner_prerequisites,
    owner_science = owner_science,
    owner_unit_count = 250,
    owner_unit_time = 30,
  }
end

local function standard_science()
  return {
    {type = "item", name = "automation-science-pack", amount = 1},
    {type = "item", name = "logistic-science-pack", amount = 1},
    {type = "item", name = "chemical-science-pack", amount = 1},
  }
end

local function agricultural_science()
  return {
    {type = "item", name = "automation-science-pack", amount = 1},
    {type = "item", name = "logistic-science-pack", amount = 1},
    {type = "item", name = "chemical-science-pack", amount = 1},
    {type = "item", name = "agricultural-science-pack", amount = 1},
  }
end

local function base_filter_binding()
  return {
    item_icon_size = "default",
    recipe = "atan-pollution-filter",
    category = "crafting",
    energy_required = 2,
    enabled = false,
    allow_productivity = "not-false",
    maximum_productivity = "omitted",
    ingredients = {
      {type = "item", name = "coal", amount = 2},
      {type = "item", name = "steel-plate", amount = 1},
      {type = "item", name = "plastic-bar", amount = 1},
    },
    results = {{type = "item", name = "atan-pollution-filter", amount = 1}},
    owner = "atan-pollution-scrubbing",
    owner_prerequisites = {"chemical-science-pack", "efficiency-module"},
    owner_science = standard_science(),
    owner_unit_count = 250,
    owner_unit_time = 30,
  }
end

-- The Base filter recipe deliberately records the raw field absence separately
-- from its safe binding policy. Factorio defaults a missing field to allowed;
-- a foreign explicit `false` is not the captured route.
function M.base_filter()
  return {
    key = "research_air_scrubbing_clean_filter",
    family = "research_air_scrubbing_clean_filter",
    kind = "productivity",
    science = "science_automation_logistic_chemical",
    prerequisites = {"atan-pollution-scrubbing"},
    effects = {{recipe = "atan-pollution-filter", scale = 1}},
    item = "atan-pollution-filter",
    icon = "__atan-air-scrubbing__/graphics/icons/pollution-filter.png",
    icon_size = 64,
    overlay = OVERLAY,
    localised_name = {"", "Air Scrubbing clean-filter productivity"},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    order = "p[research_air_scrubbing_clean_filter]",
    tuning = tuning(60),
    setting_order = "b-100-air-scrubbing-clean-filter-productivity-stream-research_air_scrubbing_clean_filter-",
    binding = base_filter_binding(),
  }
end

function M.base_ash()
  return {
    key = "research_ash_separation",
    family = "research_ash_separation",
    kind = "productivity",
    science = "science_automation_logistic_chemical_production",
    prerequisites = {"automation-3"},
    effects = {{recipe = "atan-ash-seperation", scale = 1}},
    item = "atan-ash",
    icon = "__atan-ash__/graphics/icons/ash.png",
    icon_size = 64,
    overlay = OVERLAY,
    localised_name = {"", "Ash separation productivity"},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    order = "p[research_ash_separation]",
    tuning = tuning(90),
    setting_order = "b-100-ash-separation-productivity-stream-research_ash_separation-",
    binding = {
      item_icon_size = 64,
      recipe = "atan-ash-seperation",
      category = "advanced-crafting",
      energy_required = 1,
      enabled = false,
      allow_productivity = true,
      maximum_productivity = "omitted",
      ingredients = {{type = "item", name = "atan-ash", amount = 10}},
      results = {
        {type = "item", name = "iron-ore", amount = 1, probability = 0.05},
        {type = "item", name = "coal", amount = 1, probability = 0.5},
      },
      owner = "automation-3",
      owner_prerequisites = {"speed-module", "production-science-pack", "electric-engine"},
      owner_science = {
        {type = "item", name = "automation-science-pack", amount = 1},
        {type = "item", name = "logistic-science-pack", amount = 1},
        {type = "item", name = "chemical-science-pack", amount = 1},
        {type = "item", name = "production-science-pack", amount = 1},
      },
      owner_unit_count = 150,
      owner_unit_time = 60,
    },
  }
end

-- Space Age retains the same MIR identity, tuning, and filter presentation as
-- Base, then adds only the separately captured spore route and agricultural
-- science/owner prerequisite. The two native routes remain explicitly named.
function M.space_age_filter()
  return {
    key = "research_air_scrubbing_clean_filter",
    family = "research_air_scrubbing_clean_filter",
    kind = "productivity",
    science = "science_automation_logistic_chemical_agricultural",
    prerequisites = {"atan-pollution-scrubbing", "atan-spore-scrubbing"},
    effects = {
      {recipe = "atan-pollution-filter", scale = 1},
      {recipe = "atan-spore-filter", scale = 1},
    },
    item = "atan-pollution-filter",
    icon = "__atan-air-scrubbing__/graphics/icons/pollution-filter.png",
    icon_size = 64,
    overlay = OVERLAY,
    localised_name = {"", "Air Scrubbing clean-filter productivity"},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    order = "p[research_air_scrubbing_clean_filter]",
    tuning = tuning(60),
    setting_order = "b-100-air-scrubbing-clean-filter-productivity-stream-research_air_scrubbing_clean_filter-",
    bindings = {
      filter_route("atan-pollution-filter", "__atan-air-scrubbing__/graphics/icons/pollution-filter.png",
        "atan-pollution-filter", "atan-pollution-scrubbing", {"space-platform", "efficiency-module"}, standard_science()),
      filter_route("atan-spore-filter", "__atan-air-scrubbing__/graphics/icons/spore-filter.png",
        "atan-spore-filter", "atan-spore-scrubbing", {"agricultural-science-pack", "atan-pollution-scrubbing"}, agricultural_science()),
    },
  }
end

function M.space_age_ash()
  local definition = M.base_ash()
  definition.binding.owner_unit_count = 500
  return definition
end

function M.f200_base_definitions()
  return {M.base_filter(), M.base_ash()}
end

function M.f200_space_age_definitions()
  return {M.space_age_filter(), M.space_age_ash()}
end

return M
