-- A deliberately narrow, pure acquisition witness. It establishes that one
-- concrete route has declared inputs, a matching *prototype category*, valid
-- finite energy, and a declared source/surface witness before its unlock.
-- It does not prove machine acquisition, logistics, power, throughput, save
-- behavior, balance, or ecosystem compatibility.
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local deepcopy = require("prototypes.mir.core.deepcopy")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

local MACHINE_TYPES = {
  "assembling-machine", "furnace", "mining-drill", "rocket-silo", "character"
}

local function finite_positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Factorio recipe names alone are not a product identity. A string public
-- argument keeps the established item-default convenience, while callers that
-- reason about fluids must provide {type="fluid", name="..."}.
local function normalize_identity(value, type_hint)
  if type(value) == "string" then
    return {type = type_hint or "item", name = value}
  end
  if type(value) ~= "table" then return nil end
  local name = value.name or value[1]
  local entry_type = value.type or type_hint or "item"
  if type(name) ~= "string" or name == "" or type(entry_type) ~= "string" or entry_type == "" then
    return nil
  end
  return {type = entry_type, name = name}
end

local function identity_key(identity)
  return identity.type .. "\0" .. identity.name
end

local function same_identity(left, right)
  return left and right and left.type == right.type and left.name == right.name
end

local function entry_positive(entry)
  if type(entry) ~= "table" then return false end
  local amount = tonumber(entry.amount or entry.amount_max or entry[2] or entry.amount_min or 1) or 0
  local probability = tonumber(entry.independent_probability or entry.probability or 1) or 0
  return finite_positive(amount) and finite_positive(probability) and probability <= 1
end

local function results_include_positive(results, output_identity)
  for _, result in ipairs(results or {}) do
    if same_identity(normalize_identity(result), output_identity) and entry_positive(result) then return true end
  end
  return false
end

local function variants_for(fact)
  if type(fact.variants) == "table" and #fact.variants > 0 then return fact.variants end
  return {{
    name = "default",
    categories = fact.categories or {"crafting"},
    ingredients = fact.ingredients or {},
    results = fact.results,
    result_names = fact.result_names,
    enabled = fact.enabled_without_research == true,
    hidden = fact.hidden == true,
    energy_required = fact.energy_required,
    surface_conditions = fact.surface_conditions
  }}
end

local function normalized_results(variant)
  if variant.results then return variant.results end
  local results = {}
  for _, name in ipairs(variant.result_names or {}) do
    table.insert(results, {type = "item", name = name, amount = 1, probability = 1})
  end
  return results
end

local function normalized_ingredients(variant)
  return variant.ingredients or {}
end

local function copy_options(options)
  local copied = {}
  for key, value in pairs(options or {}) do copied[key] = value end
  return copied
end

local function resolved_options(options)
  local copied = copy_options(options)
  copied.recipe_index = copied.recipe_index or recipe_facts.index_view()
  return copied
end

local function recipe_source_epoch()
  return recipe_facts.source_epoch and recipe_facts.source_epoch() or nil
end

local function reset_state(state, epoch, context, recipe_index)
  state = state or {}
  for key in pairs(state) do state[key] = nil end
  state.compiler_context = context
  state.recipe_source_epoch = epoch
  state.recipe_index = recipe_index
  state.visiting = {}
  state.acquisition_memo = {}
  state.machine_categories = nil
  state.source_catalog = nil
  state.surface_locations = nil
  state.surface_results = {}
  return state
end

local function new_state(recipe_index)
  return reset_state({}, recipe_source_epoch(), compiler_context.current(), recipe_index)
end

-- State is intentionally query-local. A caller may pass it down a recursive
-- query, but it is discarded if the active recipe source epoch changes; this
-- prevents a result from one CompilerContext/recipe snapshot leaking into the
-- next one.
local function query_state(state, recipe_index)
  local epoch = recipe_source_epoch()
  local context = compiler_context.current()
  if not state or state.recipe_source_epoch ~= epoch or state.compiler_context ~= context
    or state.recipe_index ~= recipe_index then
    return reset_state(state, epoch, context, recipe_index)
  end
  return state
end

local function category_set_from_prototypes(state)
  if state.machine_categories then return state.machine_categories end
  local categories = {}
  for _, prototype_type in ipairs(MACHINE_TYPES) do
    for _, machine in pairs(data_raw.prototypes(prototype_type)) do
      for _, category in ipairs(machine.crafting_categories or {}) do categories[category] = true end
    end
  end
  state.machine_categories = categories
  return categories
end

local function compatible_machine(category, options, state)
  if type(options.machine_category_witness) == "function" then
    return options.machine_category_witness(category) == true
  end
  return category_set_from_prototypes(state)[category] == true
end

local function surface_conditions_satisfied(conditions, properties)
  for _, condition in ipairs(conditions or {}) do
    local property = condition.property
    local value = property and properties and properties[property] or nil
    if type(value) ~= "number" then return false end
    if condition.min ~= nil and value < condition.min then return false end
    if condition.max ~= nil and value > condition.max then return false end
  end
  return true
end

local function condition_key(conditions)
  local values = {}
  for _, condition in ipairs(conditions or {}) do
    table.insert(values, table.concat({
      type(condition.property) .. ":" .. tostring(condition.property),
      type(condition.min) .. ":" .. tostring(condition.min),
      type(condition.max) .. ":" .. tostring(condition.max)
    }, "\0"))
  end
  return table.concat(values, "\1")
end

local function all_surfaces(state)
  if state.surface_locations then return state.surface_locations end
  local locations = {}
  -- A space-location can be orbital or otherwise non-buildable. Surface
  -- feasibility needs a real SurfacePrototype or a planet, not merely a
  -- matching space-location record.
  for _, prototype_type in ipairs({"surface", "planet"}) do
    for _, location in pairs(data_raw.prototypes(prototype_type)) do table.insert(locations, location) end
  end
  state.surface_locations = locations
  return locations
end

local function surface_satisfied(conditions, options, state)
  if not conditions or #conditions == 0 then return true end
  if type(options.surface_witness) == "function" then
    return options.surface_witness(conditions) == true
  end
  local key = condition_key(conditions)
  if state.surface_results[key] ~= nil then return state.surface_results[key] end
  for _, location in ipairs(all_surfaces(state)) do
    if surface_conditions_satisfied(conditions, location.surface_properties or {}) then
      state.surface_results[key] = true
      return true
    end
  end
  state.surface_results[key] = false
  return false
end

local function minable_results(source)
  local minable = source and source.minable or {}
  if minable.result then return {{type = "item", name = minable.result, amount = minable.count or 1}} end
  return minable.results or {}
end

local function append_minable_sources(sources, prototype_type, witness_kind)
  for _, source in pairs(data_raw.prototypes(prototype_type)) do
    for _, result in ipairs(minable_results(source)) do
      local identity = normalize_identity(result)
      if identity and entry_positive(result) then
        local key = identity_key(identity)
        sources[key] = sources[key] or {}
        table.insert(sources[key], {
          kind = witness_kind,
          product = identity,
          surface_conditions = deepcopy(source.surface_conditions)
        })
      end
    end
  end
end

local function default_source_catalog(state)
  if state.source_catalog then return state.source_catalog end
  local sources = {}
  append_minable_sources(sources, "resource", "minable-resource")
  -- Trees are concrete natural acquisition sources (for example, the
  -- starting wood used by an early electronics board).  They are not stored
  -- in data.raw.resource, so omitting their MinableProperties turns a real
  -- seeded route into a false no-source cycle.
  append_minable_sources(sources, "tree", "minable-entity")
  for _, pump in pairs(data_raw.prototypes("offshore-pump")) do
    local identity = normalize_identity({type = "fluid", name = pump.fluid})
    if identity then
      local key = identity_key(identity)
      sources[key] = sources[key] or {}
      table.insert(sources[key], {
        kind = "offshore-pump",
        product = identity,
        surface_conditions = deepcopy(pump.surface_conditions)
      })
    end
  end
  state.source_catalog = sources
  return sources
end

local function source_witness(identity, options, state)
  if type(options.source_witness) == "function" then
    -- Keep the established name-first callback shape, and add the exact
    -- product type/identity for type-aware callers.
    local witness = options.source_witness(identity.name, identity.type, deepcopy(identity))
    if witness == true then return {kind = "declared-source", product = deepcopy(identity)} end
    if type(witness) == "table" then
      local declared = normalize_identity(witness.product or {
        type = witness.product_type or identity.type,
        name = witness.item or witness.name
      })
      if same_identity(declared, identity) then
        local copied = deepcopy(witness)
        copied.product = deepcopy(identity)
        return copied
      end
    end
  end
  for _, witness in ipairs(default_source_catalog(state)[identity_key(identity)] or {}) do
    if surface_satisfied(witness.surface_conditions, options, state) then
      local copied = deepcopy(witness)
      copied.surface_conditions = nil
      return copied
    end
  end
  return nil
end

function M.source_witness(identity, options)
  local candidate = normalize_identity(identity)
  if not candidate then return nil end
  -- A direct source check does not need to materialize the potentially large
  -- recipe index merely to inspect resources and offshore pumps.
  return source_witness(candidate, copy_options(options), new_state())
end

local function sorted_producers(index, output_identity)
  local producers = {}
  local exact = index.by_output_identity and index.by_output_identity[identity_key(output_identity)]
  -- Fixture and historical callers may still expose only the legacy index.
  -- It is safe to use only for an item identity; fluid callers must never
  -- silently fall back to a name-only match.
  local selected = exact
  if selected == nil and index.by_output_identity == nil and output_identity.type == "item" then
    selected = index.by_output[output_identity.name]
  end
  for _, recipe_name in ipairs(selected or {}) do table.insert(producers, recipe_name) end
  table.sort(producers)
  return producers
end

local acquisition_witness

local function route_for_recipe(recipe_name, output_identity, options, state, require_enabled)
  local fact = options.recipe_index.facts[recipe_name]
  if not fact or fact.hidden == true then return nil end
  for _, variant in ipairs(variants_for(fact)) do
    if variant.hidden ~= true and (not require_enabled or variant.enabled == true) then
      local results = normalized_results(variant)
      if results_include_positive(results, output_identity)
        and (variant.energy_required == nil or finite_positive(tonumber(variant.energy_required)))
        and surface_satisfied(variant.surface_conditions, options, state) then
        local has_machine = false
        for _, category in ipairs(variant.categories or {"crafting"}) do
          if compatible_machine(category, options, state) then has_machine = true; break end
        end
        if has_machine then
          local ingredients_ok, ingredient_witnesses = true, {}
          for _, ingredient in ipairs(normalized_ingredients(variant)) do
            local ingredient_identity = normalize_identity(ingredient)
            if not ingredient_identity
              or not finite_positive(tonumber(ingredient.amount or ingredient.amount_max or ingredient[2] or 1)) then
              ingredients_ok = false
              break
            end
            local witness = acquisition_witness(ingredient_identity, options, state)
            if not witness then ingredients_ok = false; break end
            table.insert(ingredient_witnesses, witness)
          end
          if ingredients_ok then
            return {
              kind = "recipe",
              recipe = recipe_name,
              variant = variant.name or "default",
              output = deepcopy(output_identity),
              ingredients = ingredient_witnesses
            }
          end
        end
      end
    end
  end
  return nil
end

local function cacheable(options)
  return type(options.source_witness) ~= "function"
    and type(options.machine_category_witness) ~= "function"
    and type(options.surface_witness) ~= "function"
    -- An unlock witness is contextual: its caller carries the active
    -- technology/science traversal.  A conclusion from that branch must not
    -- become a reusable acquisition answer for another traversal.
    and type(options.research_unlock_witness) ~= "function"
end

-- A source witness or one enabled recipe alternative proves a product. The
-- active type/name set makes recursive requirements AND, recipe alternatives
-- OR, and rejects unseeded cycles. Default raw-prototype scans are cached only
-- inside this one query state; no feasibility result is retained globally.
acquisition_witness = function(output_identity, options, state)
  local key = identity_key(output_identity)
  -- A recursive answer is conditional on the caller's active cycle set. Only
  -- a root query can safely memoize a positive or negative acquisition result;
  -- recursive calls still reuse the bounded raw-prototype scan indexes.
  local root_query = next(state.visiting) == nil
  local may_cache = root_query and cacheable(options)
  if may_cache and state.acquisition_memo[key] ~= nil then
    local cached = state.acquisition_memo[key]
    return cached == false and nil or deepcopy(cached)
  end
  if state.visiting[key] then return nil end

  local direct = source_witness(output_identity, options, state)
  if direct then
    if may_cache then state.acquisition_memo[key] = deepcopy(direct) end
    return direct
  end

  state.visiting[key] = true
  for _, recipe_name in ipairs(sorted_producers(options.recipe_index, output_identity)) do
    local witness = route_for_recipe(recipe_name, output_identity, options, state, true)
    if witness then
      state.visiting[key] = nil
      if may_cache then state.acquisition_memo[key] = deepcopy(witness) end
      return witness
    end
  end
  -- An enabled route is preferred, but an ingredient can also be supplied by
  -- a concrete recipe whose unlock technology is already researchable.  The
  -- caller supplies that proof because this generic structural module neither
  -- owns the technology graph nor decides which research mechanisms qualify.
  -- Keep the output active while asking for it so a locked reciprocal route
  -- remains an unseeded cycle rather than becoming a bootstrap witness.
  if type(options.research_unlock_witness) == "function" then
    local witness = options.research_unlock_witness(deepcopy(output_identity), state)
    if witness then
      state.visiting[key] = nil
      if may_cache then state.acquisition_memo[key] = deepcopy(witness) end
      return witness
    end
  end
  state.visiting[key] = nil
  if may_cache then state.acquisition_memo[key] = false end
  return nil
end

function M.acquisition_witness(identity, options, state)
  local output_identity = normalize_identity(identity)
  if not output_identity then return nil end
  local resolved = resolved_options(options)
  return acquisition_witness(output_identity, resolved, query_state(state, resolved.recipe_index))
end

-- Prove a concrete route for a named output. Locked recipes may be checked as
-- future production routes with require_enabled=false; their inputs still use
-- only enabled alternatives or declared natural sources.
function M.recipe_witness(recipe_name, output, options, state)
  local output_identity = normalize_identity(output)
  if not output_identity then return nil end
  local resolved = resolved_options(options)
  return route_for_recipe(
    recipe_name,
    output_identity,
    resolved,
    query_state(state, resolved.recipe_index),
    resolved.require_enabled == true
  )
end

function M.initial_recipe_witness(recipe_name, output, options)
  -- Never mutate the caller's option table: a caller can safely reuse it for a
  -- later locked-route query without inheriting require_enabled=true.
  local initial_options = copy_options(options)
  initial_options.require_enabled = true
  return M.recipe_witness(recipe_name, output, initial_options)
end

return M
