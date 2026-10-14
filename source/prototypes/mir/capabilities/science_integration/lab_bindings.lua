-- Bounded laboratory-reference projection for approved science admission.
--
-- A row says only that a concrete placement item has a concrete recipe source
-- and, if that recipe starts disabled, the technologies that directly unlock
-- it.  It deliberately does not establish factory acquisition, choose among
-- competing routes, or decide whether a science/lab graph is bootstrap-safe.
-- The shared science binding graph owns those cross-reference decisions.
local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local prototype_lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local item_facts = require("prototypes.mir.index.item_prototype_facts")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

local function sorted_names(values)
  local out = {}
  for name in pairs(values or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function sorted_inputs(lab)
  local seen = {}
  for _, input in ipairs((lab and lab.inputs) or {}) do
    if type(input) == "string" and input ~= "" then seen[input] = true end
  end
  return sorted_names(seen)
end

local function finite_positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- A recipe index groups variants for lookup.  A laboratory placement binding
-- needs more: every declared difficulty variant must actually be able to
-- yield the placement item.  An aggregate amount can otherwise hide a zero
-- probability (or zero amount) result in one variant.
local function possible_item_result(result, item_name)
  if result.type ~= "item" or result.name ~= item_name then return false end
  local maximum = result.amount
  if maximum == nil then maximum = result.amount_max or result.amount_min end
  if not finite_positive(maximum) then return false end
  local probability = result.independent_probability
  if probability == nil then probability = result.probability end
  if probability == nil then probability = 1 end
  if not finite_positive(probability) or probability > 1 then return false end
  local shared = result.shared_probability
  if shared ~= nil then
    if type(shared) ~= "table" or type(shared.min) ~= "number" or type(shared.max) ~= "number"
      or shared.min ~= shared.min or shared.max ~= shared.max
      or shared.min < 0 or shared.max <= 0 or shared.min > shared.max or shared.max > 1 then
      return false
    end
  end
  return true
end

local function outputs_item(fact, item_name)
  local variants = (fact and fact.variants) or {}
  if #variants == 0 then return false end
  for _, variant in ipairs(variants) do
    local possible = false
    for _, result in ipairs(variant.results or {}) do
      if possible_item_result(result, item_name) then possible = true; break end
    end
    if not possible then return false end
  end
  return true
end

local function ingredient_packs(fact, lab_inputs)
  local seen, packs = {}, {}
  for _, ingredient in ipairs((fact and fact.ingredient_identities) or {}) do
    if ingredient.type == "item" and lab_inputs[ingredient.name] and not seen[ingredient.name] then
      seen[ingredient.name] = true
      packs[#packs + 1] = ingredient.name
    end
  end
  table.sort(packs)
  return packs
end

local function enabled_unlockers(recipe_name)
  local out = {}
  for _, technology_name in ipairs(recipe_unlocks.for_recipe(recipe_name)) do
    local technology = data_raw.technology(technology_name)
    if technology and technology.enabled ~= false then out[#out + 1] = technology_name end
  end
  table.sort(out)
  return out
end

local function source_binding(item_name, recipe_name, lab_input_set)
  local fact = recipe_facts.view(recipe_name)
  if not outputs_item(fact, item_name) then return nil end
  local packs = ingredient_packs(fact, lab_input_set)
  if fact.enabled_without_research == true then
    return {
      item_name = item_name,
      recipe_name = recipe_name,
      initial = true,
      ingredient_packs = packs,
      unlockers = {}
    }
  end
  local unlockers = enabled_unlockers(recipe_name)
  if #unlockers == 0 then return nil end
  return {
    item_name = item_name,
    recipe_name = recipe_name,
    initial = false,
    ingredient_packs = packs,
    unlockers = unlockers
  }
end

local function source_less(left, right)
  if left.item_name ~= right.item_name then return left.item_name < right.item_name end
  if left.recipe_name ~= right.recipe_name then return left.recipe_name < right.recipe_name end
  return left.initial and not right.initial
end

local function lab_record(name, lab)
  local sources, lab_input_set = {}, {}
  for _, input in ipairs(sorted_inputs(lab)) do lab_input_set[input] = true end
  for _, item_name in ipairs(item_facts.placeable_items_for_entity(name)) do
    local item = prototype_lookup.item_prototype(item_name)
    if item and item.place_result == name then
      for _, recipe_name in ipairs(recipe_facts.recipes_by_output_identity_view("item", item_name)) do
        local source = source_binding(item_name, recipe_name, lab_input_set)
        if source then sources[#sources + 1] = source end
      end
    end
  end
  table.sort(sources, source_less)
  return {name = name, inputs = sorted_inputs(lab), sources = sources}
end

local function build_snapshot()
  local names = sorted_names(data_raw.prototypes("lab"))
  local records = {}
  for _, name in ipairs(names) do records[#records + 1] = lab_record(name, data_raw.prototype("lab", name)) end
  return records
end

-- Snapshot rows are copied at the public boundary.  The Context keeps the
-- internal projection only for the exact data-stage input lifetime.
function M.snapshot()
  local context = compiler_context.current()
  local records = context:state_view("approved_lab_bindings", build_snapshot)
  return deepcopy(records)
end

return M
