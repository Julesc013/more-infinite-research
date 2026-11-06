-- Pure published paid-state declarations shared by settings selection,
-- data construction and runtime readers. Every returned table is detached.
local M = {}

-- The published five-family/eleven-recipe paid vector is shared with the
-- exact SIF adapter. Common credit readers need these historical constants,
-- not that adapter's selection and preflight body.
local PUBLISHED_SIF_CONTRACTS = {
  {key="research_low_density_structure", product="low-density-structure", recipes={
    {"casting-low-density-structure", "low-density-structure-productivity"},
    {"low-density-structure", "low-density-structure-productivity"},
    {"scrap-recycling", "scrap-recycling-productivity"},
  }},
  {key="research_plastic", product="plastic-bar", recipes={
    {"bioplastic", "plastic-bar-productivity"}, {"plastic-bar", "plastic-bar-productivity"},
  }},
  {key="research_processing_unit", product="processing-unit", recipes={
    {"processing-unit", "processing-unit-productivity"},
  }},
  {key="research_rocket_fuel", product="rocket-fuel", recipes={
    {"ammonia-rocket-fuel", "rocket-fuel-productivity"},
    {"rocket-fuel", "rocket-fuel-productivity"}, {"rocket-fuel-from-jelly", "rocket-fuel-productivity"},
  }},
  {key="research_steel", product="steel-plate", recipes={
    {"casting-steel", "steel-plate-productivity"}, {"steel-plate", "steel-plate-productivity"},
  }},
}

function M.published_sif_contracts()
  local out = {}
  for _, contract in ipairs(PUBLISHED_SIF_CONTRACTS) do
    local row = {key=contract.key, product=contract.product, recipes={}}
    for _, route in ipairs(contract.recipes) do row.recipes[#row.recipes + 1] = {route[1],route[2]} end
    out[#out + 1] = row
  end
  return out
end

function M.published_sif_paid_recipe_sets()
  local out = {}
  for _, contract in ipairs(PUBLISHED_SIF_CONTRACTS) do
    local recipes = {}
    for _, route in ipairs(contract.recipes) do recipes[route[1]] = true end
    out[contract.key] = recipes
  end
  return out
end

-- Published 5.0.0-5.0.2 F200/F210 plain Base public families. These are old
-- earning rights, independent of today's selected effects or extra recipes.
local PUBLISHED_BETA_BASE_RECIPES = {
  research_low_density_structure="low-density-structure",
  research_plastic="plastic-bar", research_processing_unit="processing-unit",
  research_rocket_fuel="rocket-fuel", research_steel="steel-plate",
}

function M.published_beta_base_paid_recipe_sets()
  local out = {}
  for family, recipe in pairs(PUBLISHED_BETA_BASE_RECIPES) do out[family] = {[recipe]=true} end
  return out
end

-- Published data-only 1.0.0/1.1.0/1.2.0 Base research. In 1.0 conflict
-- trimming can suppress a whole one-recipe family; these are conditional
-- earning masks, not a claim that every family existed in an old save.
-- Steel was not authored and cannot carry investment from these sources.
local PUBLISHED_DATA_ONLY_BASE_RECIPES = {
  research_low_density_structure="low-density-structure",
  research_plastic="plastic-bar", research_processing_unit="processing-unit",
  research_rocket_fuel="rocket-fuel",
}

function M.published_data_only_base_paid_recipe_sets(version)
  if version ~= "1.0.0" and version ~= "1.1.0" and version ~= "1.2.0" then return nil end
  local out = {}
  for family, recipe in pairs(PUBLISHED_DATA_ONLY_BASE_RECIPES) do out[family] = {[recipe]=true} end
  return out
end

return M
