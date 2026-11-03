-- Explicit migration-credit carriers for observed partial overlaps and the
-- five authored native families. This module constructs detached native
-- TechnologyPrototype tables; runtime accounting has a separate lifecycle.
local M = {}

local ICON = "__base__/graphics/technology/automation-1.png"
local ORDER_PREFIX = "zz[mir-native-credit]-"

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

local function credit_id(family, recipe, direction)
  return "mir-native-credit-" .. family .. "-" .. recipe .. "-" .. direction
end

local function descriptor(family, main_id, recipe)
  return {
    family = family,
    main_id = main_id,
    recipe = recipe,
    positive_id = credit_id(family, recipe, "positive"),
    negative_id = credit_id(family, recipe, "negative"),
  }
end

-- These twelve recipe-level identities are the complete union of the verified
-- partial MIR replacement rows. They deliberately name no provider: the
-- carriers preserve an MIR recipe contribution after that provider disappears.
local DESCRIPTORS = {
  descriptor("research_copper", "recipe-prod-research_copper-1", "copper-plate"),
  descriptor("research_iron", "recipe-prod-research_iron-1", "iron-plate"),
  descriptor("research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"),
  descriptor("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"),
  descriptor("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"),
  descriptor("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"),
  descriptor("research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"),
  descriptor("research_grenades", "recipe-prod-research_grenades-1", "grenade"),
  descriptor("research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"),
  descriptor("research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"),
  descriptor("research_concrete", "recipe-prod-research_concrete-1", "stone-brick"),
  descriptor("research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"),
}

local function finite_positive(value)
  return type(value) == "number" and value == value
    and value > 0 and value < math.huge
end

local COLLECTED_FAMILIES = {
  "research_low_density_structure", "research_plastic", "research_processing_unit",
  "research_rocket_fuel", "research_steel",
}
local COLLECTED_FAMILY_SET = {}
for _, family in ipairs(COLLECTED_FAMILIES) do COLLECTED_FAMILY_SET[family] = true end

-- Only the caller's collected named effects cross this boundary. No owner,
-- recipe world or saved state is consulted to manufacture a descriptor.
function M.collected_descriptors(groups)
  if groups == nil then return {} end
  local seen_tables = {}
  local function plain(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil or seen_tables[value] then
      error("MIR native credit collected groups require unaliased plain tables", 3)
    end
    seen_tables[value] = true
  end
  plain(groups)
  local normalized = {}
  for family, effects in pairs(groups) do
    if COLLECTED_FAMILY_SET[family] ~= true then
      error("MIR native credit collected family is not authored", 2)
    end
    plain(effects)
    local rows, recipes, count, maximum = {}, {}, 0, 0
    for index, effect in pairs(effects) do
      if type(index) ~= "number" or index < 1 or index >= math.huge or index ~= math.floor(index) then
        error("MIR native credit collected effects must be a dense array", 2)
      end
      count, maximum = count + 1, math.max(maximum, index)
      plain(effect)
      for key in pairs(effect) do
        if key ~= "recipe" and key ~= "change" then
          error("MIR native credit collected effect has an unknown field", 2)
        end
      end
      local recipe, change = effect.recipe, effect.change
      if type(recipe) ~= "string" or recipe == "" or recipe:find("\0", 1, true)
          or not finite_positive(change) or recipes[recipe] then
        error("MIR native credit collected effect is invalid or duplicated", 2)
      end
      recipes[recipe] = true
      local row = descriptor(family, "recipe-prod-" .. family .. "-1", recipe)
      row.key, row.change, row.collected = family .. "\0" .. recipe, change, true
      rows[#rows + 1] = row
    end
    if count ~= maximum then error("MIR native credit collected effects must be a dense array", 2) end
    table.sort(rows, function(left, right) return left.recipe < right.recipe end)
    normalized[family] = rows
  end
  local out = {}
  for _, family in ipairs(COLLECTED_FAMILIES) do
    for _, row in ipairs(normalized[family] or {}) do out[#out + 1] = row end
  end
  return out
end

local function copy_descriptor(row)
  return {
    family = row.family,
    main_id = row.main_id,
    recipe = row.recipe,
    positive_id = row.positive_id,
    negative_id = row.negative_id,
  }
end

-- Runtime consumers receive fresh plain metadata, so no caller can mutate the
-- authored descriptor constants used by data-stage construction.
function M.descriptors(groups)
  local out = {}
  for index = 1, #DESCRIPTORS do out[index] = copy_descriptor(DESCRIPTORS[index]) end
  for _, row in ipairs(M.collected_descriptors(groups)) do out[#out + 1] = row end
  return out
end

local function named_current_rows(technologies, descriptors)
  if type(technologies) ~= "table" then
    error("MIR native credit definitions require an output technology array", 3)
  end
  local wanted = {}
  for index = 1, #descriptors do
    local row = descriptors[index]
    wanted[row.main_id], wanted[row.positive_id], wanted[row.negative_id] = true, true, true
  end
  local found = {}
  -- This indexes only the caller's already-built output list. It never
  -- traverses data.raw technology prototypes or arbitrary recipe families.
  for index = 1, #technologies do
    local row = technologies[index]
    local name = type(row) == "table" and row.name or nil
    if type(name) == "string" and wanted[name] then
      if found[name] ~= nil then error("MIR native credit duplicate named technology " .. name, 3) end
      found[name] = row
    end
  end
  return found
end

local function configured_change(effective_values, family)
  local streams = effective_values and effective_values.streams
  local stream = type(streams) == "table" and streams[family] or nil
  local percent = type(stream) == "table" and stream.effect_percent or nil
  if not finite_positive(percent) then
    error("MIR native credit has no positive configured effect for " .. family, 3)
  end
  return percent / 100
end

local function carrier(name, recipe, change)
  return {
    type = "technology",
    name = name,
    icon = ICON,
    icon_size = 256,
    level = 1,
    upgrade = true,
    hidden = true,
    enabled = false,
    visible_when_disabled = false,
    max_level = "infinite",
    order = ORDER_PREFIX .. name,
    effects = {{type = "change-recipe-productivity", recipe = recipe, change = change}},
    unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}},
  }
end

-- Appends carrier pairs only where an authored main MIR row and its exact
-- recipe are both present. It returns the newly owned rows; neither existing
-- output rows nor data.raw are mutated.
function M.append(technologies, raw, effective_values, target, groups)
  if type(target) ~= "table" or target.recipe_productivity ~= true then return {} end
  local descriptors = M.descriptors(groups)
  local present, staged = named_current_rows(technologies, descriptors), {}
  local has_main = false
  for index = 1, #descriptors do
    local row = descriptors[index]
    local main = present[row.main_id]
    if row.collected and (main == nil or main.type ~= "technology" or main.name ~= row.main_id) then
      error("MIR native credit collected main technology is absent or invalid: " .. row.main_id, 2)
    end
    if main ~= nil then has_main = true end
  end
  if not has_main then return staged end
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" then
    error("MIR native credit definitions require data.raw.recipe", 2)
  end

  for index = 1, #descriptors do
    local row = descriptors[index]
    local recipe = (row.collected or present[row.main_id] ~= nil) and raw.recipe[row.recipe] or nil
    if row.collected and (type(recipe) ~= "table" or recipe.type ~= "recipe" or recipe.name ~= row.recipe) then
      error("MIR native credit collected recipe is absent or invalid: " .. row.recipe, 2)
    end
    if present[row.main_id] ~= nil and type(recipe) == "table" then
      if present[row.positive_id] ~= nil or present[row.negative_id] ~= nil then
        error("MIR native credit identity is already owned for " .. row.family .. ":" .. row.recipe, 2)
      end
      local change = row.collected and row.change or configured_change(effective_values, row.family)
      staged[#staged + 1] = carrier(row.positive_id, row.recipe, change)
      staged[#staged + 1] = carrier(row.negative_id, row.recipe, -change)
    end
  end
  for index = 1, #staged do technologies[#technologies + 1] = staged[index] end
  return staged
end

return M
