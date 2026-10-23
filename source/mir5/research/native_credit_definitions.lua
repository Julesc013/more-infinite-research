-- Explicit migration-credit carriers for the only observed partial
-- competing-productivity overlaps. This module constructs detached native
-- TechnologyPrototype tables; runtime accounting has a separate lifecycle.
local M = {}

local ICON = "__base__/graphics/technology/automation.png"
local ORDER_PREFIX = "zz[mir-native-credit]-"

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
function M.descriptors()
  local out = {}
  for index = 1, #DESCRIPTORS do out[index] = copy_descriptor(DESCRIPTORS[index]) end
  return out
end

local function named_current_rows(technologies)
  if type(technologies) ~= "table" then
    error("MIR native credit definitions require an output technology array", 3)
  end
  local wanted = {}
  for index = 1, #DESCRIPTORS do
    local row = DESCRIPTORS[index]
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
function M.append(technologies, raw, effective_values, target)
  if type(target) ~= "table" or target.recipe_productivity ~= true then return {} end
  local present, staged = named_current_rows(technologies), {}
  local has_main = false
  for index = 1, #DESCRIPTORS do
    if present[DESCRIPTORS[index].main_id] ~= nil then has_main = true; break end
  end
  if not has_main then return staged end
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" then
    error("MIR native credit definitions require data.raw.recipe", 2)
  end

  for index = 1, #DESCRIPTORS do
    local row = DESCRIPTORS[index]
    if present[row.main_id] ~= nil and type(raw.recipe[row.recipe]) == "table" then
      if present[row.positive_id] ~= nil or present[row.negative_id] ~= nil then
        error("MIR native credit identity is already owned for " .. row.family .. ":" .. row.recipe, 2)
      end
      local change = configured_change(effective_values, row.family)
      staged[#staged + 1] = carrier(row.positive_id, row.recipe, change)
      staged[#staged + 1] = carrier(row.negative_id, row.recipe, -change)
    end
  end
  for index = 1, #staged do technologies[#technologies + 1] = staged[index] end
  return staged
end

return M
