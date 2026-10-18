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
local recipe_semantics = require("prototypes.mir.domain.facts.recipe_semantics")
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

-- Recipe facts aggregate variants for indexes.  A direct placement source
-- requires a possible typed item result in every declared variant; an
-- aggregate amount must never conceal a zero-probability result.
local function possible_item_result(result, item_name)
  return result.type == "item" and result.name == item_name
    and recipe_semantics.possible_item_result(result)
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

local function lab_record(name, lab, science_input_set)
  local sources = {}
  for _, item_name in ipairs(item_facts.placeable_items_for_entity(name)) do
    local item = prototype_lookup.item_prototype(item_name)
    if item and item.place_result == name then
      for _, recipe_name in ipairs(recipe_facts.recipes_by_output_identity_view("item", item_name)) do
        local source = source_binding(item_name, recipe_name, science_input_set)
        if source then sources[#sources + 1] = source end
      end
    end
  end
  table.sort(sources, source_less)
  return {name = name, inputs = sorted_inputs(lab), sources = sources}
end

local function build_snapshot()
  local names = sorted_names(data_raw.prototypes("lab"))
  -- A placement recipe may consume science accepted by a different physical
  -- lab.  That dependency still belongs in the shared reference graph; the
  -- record's own `inputs` below remains the actual acceptance vector for this
  -- lab and is never unioned with another lab's inputs.
  local science_input_set = {}
  for _, name in ipairs(names) do
    for _, input in ipairs(sorted_inputs(data_raw.prototype("lab", name))) do
      science_input_set[input] = true
    end
  end
  local records = {}
  for _, name in ipairs(names) do
    records[#records + 1] = lab_record(name, data_raw.prototype("lab", name), science_input_set)
  end
  return records
end

-- Internal compiler consumers may share this Context-owned projection for the
-- exact data-stage input lifetime.  They must treat every row as read-only.
function M.view()
  local context = compiler_context.current()
  return context:state_view("approved_lab_bindings", build_snapshot)
end

-- Snapshot rows are copied at the public boundary.  Reports, fixtures, and
-- other callers must never retain the Context-owned projection.
function M.snapshot()
  return deepcopy(M.view())
end

return M
