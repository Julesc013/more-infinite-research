-- A deliberately narrow, pure acquisition witness. It establishes that one
-- concrete route has declared inputs, a matching *prototype category*, valid
-- finite energy, and a declared source/surface witness before its unlock.
-- It does not prove machine acquisition, logistics, power, throughput, save
-- behavior, balance, or ecosystem compatibility.
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local deepcopy = require("prototypes.mir.core.deepcopy")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

-- Acquisition alternatives remain complete, but ordinary production is tried
-- before reverse recycling routes. A known forward route should not first
-- traverse every item whose recycling can return this same ingredient.
function M.sort_acquisition_producers(names, index)
  local facts = index and index.facts or {}
  table.sort(names, function(left, right)
    local left_recycling = facts[left] and facts[left].source_class == "recycling" or false
    local right_recycling = facts[right] and facts[right].source_class == "recycling" or false
    if left_recycling ~= right_recycling then return not left_recycling end
    return left < right
  end)
  return names
end

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

-- Assigned below with the diagnostic helpers. The forward declaration lets
-- every nested result/category/source iterator charge the same work budget.
local diagnostic_visit

local function entry_positive(entry)
  if type(entry) ~= "table" then return false end
  local amount = tonumber(entry.amount or entry.amount_max or entry[2] or entry.amount_min or 1) or 0
  local probability = tonumber(entry.independent_probability or entry.probability or 1) or 0
  return finite_positive(amount) and finite_positive(probability) and probability <= 1
end

local function results_include_positive(results, output_identity, options)
  for _, result in ipairs(results or {}) do
    if not diagnostic_visit(options) then return false end
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

local function normalized_results(variant, options)
  if variant.results then return variant.results end
  local results = {}
  for _, name in ipairs(variant.result_names or {}) do
    if not diagnostic_visit(options) then return nil end
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

-- Diagnostics are deliberately observer-only. Production callers do not pass
-- this callback, and no admission or memo decision may depend on it.
--
-- A diagnostic observer may additionally provide query-local checkpoints. A
-- recipe has OR semantics across its variants, and acquisition has OR
-- semantics across producer recipes. If a later branch succeeds, observations
-- from earlier rejected branches are not a cause of the selected result and
-- must be discarded with that branch. This keeps a successful structural
-- alternative from masking the later technology/self-lock rejection which is
-- actually decisive for a pack candidate.
local function record_diagnostic_failure(options, failure)
  local observer = options and options.diagnostic_observer
  if observer and type(observer.record) == "function" then
    observer:record(deepcopy(failure), options.diagnostic_depth or 0)
  elseif type(options.diagnostic_failure) == "function" then
    options.diagnostic_failure(deepcopy(failure))
  end
end

local function diagnostic_checkpoint(options)
  local observer = options and options.diagnostic_observer
  if observer and type(observer.checkpoint) == "function" then return observer:checkpoint() end
  return nil
end

local function diagnostic_rollback(options, checkpoint)
  local observer = options and options.diagnostic_observer
  if checkpoint and observer and type(observer.rollback) == "function" then
    observer:rollback(checkpoint)
  end
end

-- Diagnostic work is irreversible even where its explanatory trace is not.
-- The observer is absent in normal admission, preserving feasibility
-- semantics; when present, every raw-prototype scan and recursive descent
-- must reserve work before inspecting its next node.
diagnostic_visit = function(options, depth)
  local observer = options and options.diagnostic_observer
  if not observer then return true end
  if type(observer.is_stopped) == "function" and observer:is_stopped() then return false end
  if type(observer.reserve_visit) == "function" then
    return observer:reserve_visit(depth or options.diagnostic_depth or 0)
  end
  return true
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
  state.stable_acquisition_memo = {}
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
  if not state or state.recipe_source_epoch ~= epoch or state.compiler_context ~= context then
    return reset_state(state, epoch, context, recipe_index)
  end
  if state.recipe_index ~= recipe_index then
    -- A direct-source preflight intentionally starts without a recipe index.
    -- Once the same query proceeds to recipe feasibility, retain its immutable
    -- prototype catalogs while establishing the previously absent index. An
    -- explicit replacement with a different populated index remains a new
    -- query identity and must discard every prior memo.
    if state.recipe_index == nil and recipe_index ~= nil then
      state.recipe_index = recipe_index
      state.visiting = {}
      state.acquisition_memo = {}
      state.stable_acquisition_memo = {}
      return state
    end
    return reset_state(state, epoch, context, recipe_index)
  end
  return state
end

-- Direct-source checks do not need a recipe index, but a caller may supply a
-- state which has already acquired one. Preserve that state when its context
-- and source epoch match so separate science-pack roots can reuse the same
-- immutable resource, machine, and surface observations.
local function source_query_state(state)
  local epoch = recipe_source_epoch()
  local context = compiler_context.current()
  if not state or state.recipe_source_epoch ~= epoch or state.compiler_context ~= context then
    return reset_state(state, epoch, context, nil)
  end
  return state
end

local function category_set_from_prototypes(state, options)
  if state.machine_categories then return state.machine_categories end
  local categories = {}
  for _, prototype_type in ipairs(MACHINE_TYPES) do
    for _, machine in pairs(data_raw.prototypes(prototype_type)) do
      if not diagnostic_visit(options) then return categories end
      for _, category in ipairs(machine.crafting_categories or {}) do
        if not diagnostic_visit(options) then return categories end
        categories[category] = true
      end
    end
  end
  state.machine_categories = categories
  return categories
end

local function compatible_machine(category, options, state)
  if type(options.machine_category_witness) == "function" then
    return options.machine_category_witness(category) == true
  end
  return category_set_from_prototypes(state, options)[category] == true
end

local function surface_conditions_satisfied(conditions, properties, options)
  for _, condition in ipairs(conditions or {}) do
    if not diagnostic_visit(options) then return false end
    local property = condition.property
    local value = property and properties and properties[property] or nil
    if type(value) ~= "number" then return false end
    if condition.min ~= nil and value < condition.min then return false end
    if condition.max ~= nil and value > condition.max then return false end
  end
  return true
end

local function condition_key(conditions, options)
  local values = {}
  for _, condition in ipairs(conditions or {}) do
    if not diagnostic_visit(options) then return nil end
    table.insert(values, table.concat({
      type(condition.property) .. ":" .. tostring(condition.property),
      type(condition.min) .. ":" .. tostring(condition.min),
      type(condition.max) .. ":" .. tostring(condition.max)
    }, "\0"))
  end
  return table.concat(values, "\1")
end

local function all_surfaces(state, options)
  if state.surface_locations then return state.surface_locations end
  local locations = {}
  -- A space-location can be orbital or otherwise non-buildable. Surface
  -- feasibility needs a real SurfacePrototype or a planet, not merely a
  -- matching space-location record.
  for _, prototype_type in ipairs({"surface", "planet"}) do
    for _, location in pairs(data_raw.prototypes(prototype_type)) do
      if not diagnostic_visit(options) then return locations end
      table.insert(locations, location)
    end
  end
  state.surface_locations = locations
  return locations
end

local function surface_satisfied(conditions, options, state)
  if not conditions or #conditions == 0 then return true end
  if type(options.surface_witness) == "function" then
    return options.surface_witness(conditions) == true
  end
  local key = condition_key(conditions, options)
  if not key then return false end
  if state.surface_results[key] ~= nil then return state.surface_results[key] end
  for _, location in ipairs(all_surfaces(state, options)) do
    if not diagnostic_visit(options) then return false end
    if surface_conditions_satisfied(conditions, location.surface_properties or {}, options) then
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

local function append_minable_sources(sources, prototype_type, witness_kind, options)
  for _, source in pairs(data_raw.prototypes(prototype_type)) do
    if not diagnostic_visit(options) then return false end
    for _, result in ipairs(minable_results(source)) do
      if not diagnostic_visit(options) then return false end
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
  return true
end

local function has_unconditional_source(sources, identity)
  for _, witness in ipairs(sources[identity_key(identity)] or {}) do
    if type(witness.surface_conditions) ~= "table" or #witness.surface_conditions == 0 then
      return true
    end
  end
  return false
end

local function append_loot_sources(sources, options)
  -- Enemy drops are concrete acquisition seeds, including the first Gleba
  -- pentapod egg. The breeding recipe cannot seed itself without that drop.
  for _, prototype_type in ipairs({"unit-spawner", "unit", "turret"}) do
    for _, source in pairs(data_raw.prototypes(prototype_type)) do
      if not diagnostic_visit(options) then return false end
      for _, result in ipairs(source.loot or {}) do
        if not diagnostic_visit(options) then return false end
        local identity = normalize_identity(result)
        if identity and identity.type == "item" and entry_positive(result) then
          local key = identity_key(identity)
          sources[key] = sources[key] or {}
          table.insert(sources[key], {
            kind = "entity-loot",
            product = identity,
            surface_conditions = deepcopy(source.surface_conditions)
          })
        end
      end
    end
  end
  return true
end

-- Boilers are prototype-defined fluid conversions rather than recipes. A
-- boiler whose input fluid already has an unconditional natural source gives
-- a concrete acquisition route for its declared output fluid. As with recipe
-- machine checks, this witness deliberately does not claim machine, fuel,
-- power, throughput, or placement acquisition. Surface-constrained boiler or
-- input sources remain conservative until a same-surface witness is modeled.
local function append_boiler_sources(sources, options)
  for _, boiler in pairs(data_raw.prototypes("boiler")) do
    if not diagnostic_visit(options) then return false end
    local input = normalize_identity({
      type = "fluid",
      name = boiler.fluid_box and boiler.fluid_box.filter
    })
    local output = normalize_identity({
      type = "fluid",
      name = boiler.output_fluid_box and boiler.output_fluid_box.filter
    })
    local target_temperature = tonumber(boiler.target_temperature)
    if input and output and not same_identity(input, output)
      and finite_positive(target_temperature)
      and boiler.energy_consumption ~= nil
      and type(boiler.energy_source) == "table"
      and (type(boiler.surface_conditions) ~= "table" or #boiler.surface_conditions == 0)
      and has_unconditional_source(sources, input) then
      local key = identity_key(output)
      sources[key] = sources[key] or {}
      table.insert(sources[key], {
        kind = "boiler-conversion",
        prototype = boiler.name,
        product = output,
        input = input,
        target_temperature = target_temperature
      })
    end
  end
  return true
end

local function offshore_pump_output_fluids(pump, options)
  -- Factorio 2.1 base offshore pumps take their unfiltered output directly
  -- from water tiles. Its source-offset form does not carry the former
  -- `fluid` field. The F200 profile intentionally retains its established
  -- explicit-field contract. Its Angel pump `fluid_box.filter` describes a
  -- machine output shape, and must not become a natural source witness.
  -- Preserve the legacy explicit `fluid` declaration on every target.
  local declared = pump and pump.fluid
  if type(declared) == "string" and declared ~= "" then return {declared} end
  local fluids, seen = {}, {}
  if target_profiles.current_factorio_version == "2.1"
    and pump and pump.fluid_source_offset ~= nil then
    -- The pump draws the fluid declared by the tile, including Space Age
    -- oceans. A connection filter constrains that source; it cannot invent
    -- one. In particular, never assume every unfiltered pump produces water.
    local filter = pump.fluid_box and pump.fluid_box.filter
    for _, tile in pairs(data_raw.prototypes("tile")) do
      if not diagnostic_visit(options) then return fluids end
      local fluid = tile.fluid
      if type(fluid) == "string" and fluid ~= "" and not seen[fluid]
        and (filter == nil or filter == fluid) then
        seen[fluid] = true
        table.insert(fluids, fluid)
      end
    end
  end
  table.sort(fluids)
  return fluids
end

local function default_source_catalog(state, options)
  if state.source_catalog then return state.source_catalog end
  local sources = {}
  if not append_minable_sources(sources, "resource", "minable-resource", options) then return sources end
  -- Trees are concrete natural acquisition sources (for example, the
  -- starting wood used by an early electronics board).  They are not stored
  -- in data.raw.resource, so omitting their MinableProperties turns a real
  -- seeded route into a false no-source cycle.
  if not append_minable_sources(sources, "tree", "minable-entity", options) then return sources end
  -- Space Age crops and collected asteroid chunks have concrete minable
  -- products in separate prototype namespaces, not resource or tree.
  if not append_minable_sources(sources, "plant", "minable-entity", options) then return sources end
  if not append_minable_sources(sources, "asteroid-chunk", "minable-entity", options) then return sources end
  if not append_loot_sources(sources, options) then return sources end
  for _, pump in pairs(data_raw.prototypes("offshore-pump")) do
    if not diagnostic_visit(options) then return sources end
    for _, fluid in ipairs(offshore_pump_output_fluids(pump, options)) do
      local identity = normalize_identity({type = "fluid", name = fluid})
      local key = identity_key(identity)
      sources[key] = sources[key] or {}
      table.insert(sources[key], {
        kind = "offshore-pump",
        product = identity,
        surface_conditions = deepcopy(pump.surface_conditions)
      })
    end
  end
  if not append_boiler_sources(sources, options) then return sources end
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
  for _, witness in ipairs(default_source_catalog(state, options)[identity_key(identity)] or {}) do
    if not diagnostic_visit(options) then return nil end
    if surface_satisfied(witness.surface_conditions, options, state) then
      local copied = deepcopy(witness)
      copied.surface_conditions = nil
      return copied
    end
  end
  return nil
end

function M.source_witness(identity, options, state)
  local candidate = normalize_identity(identity)
  if not candidate then return nil end
  -- A direct source check does not need to materialize the potentially large
  -- recipe index merely to inspect resources and offshore pumps. Callers may
  -- share a source-epoch-bound state; it contains no contextual research route
  -- conclusion and therefore cannot alter admission semantics.
  return source_witness(candidate, copy_options(options), source_query_state(state))
end

local function sorted_producers(index, output_identity, options)
  local producers = {}
  local exact = index.by_output_identity and index.by_output_identity[identity_key(output_identity)]
  -- Fixture and historical callers may still expose only the legacy index.
  -- It is safe to use only for an item identity; fluid callers must never
  -- silently fall back to a name-only match.
  local selected = exact
  if selected == nil and index.by_output_identity == nil and output_identity.type == "item" then
    selected = index.by_output[output_identity.name]
  end
  for _, recipe_name in ipairs(selected or {}) do
    if not diagnostic_visit(options) then break end
    table.insert(producers, recipe_name)
  end
  -- Rejection projections retain their established lexical branch order and
  -- bounded-work accounting. The normal search alone prefers forward routes.
  if options.diagnostic_observer ~= nil then
    table.sort(producers)
    return producers
  end
  return M.sort_acquisition_producers(producers, index)
end

local acquisition_witness

local function route_for_recipe(recipe_name, output_identity, options, state, require_enabled)
  if not diagnostic_visit(options) then return nil end
  local fact = options.recipe_index.facts[recipe_name]
  if not fact then
    record_diagnostic_failure(options, {
      kind = "identity",
      recipe = recipe_name,
      identity = deepcopy(output_identity),
      reason = "missing-recipe-fact"
    })
    return nil
  end
  if fact.hidden == true then
    record_diagnostic_failure(options, {
      kind = "identity",
      recipe = recipe_name,
      identity = deepcopy(output_identity),
      reason = "hidden-recipe"
    })
    return nil
  end
  local route_checkpoint = diagnostic_checkpoint(options)
  for _, variant in ipairs(variants_for(fact)) do
    if not diagnostic_visit(options) then return nil end
    -- The next alternative is the one currently selected for explanation.
    -- A failed sibling is not an ancestor of this branch, so retaining it
    -- would manufacture a mixed failure tree.
    diagnostic_rollback(options, route_checkpoint)
    local variant_name = variant.name or "default"
    if variant.hidden == true then
      record_diagnostic_failure(options, {
        kind = "identity",
        recipe = recipe_name,
        variant = variant_name,
        identity = deepcopy(output_identity),
        reason = "hidden-variant"
      })
    elseif require_enabled and variant.enabled ~= true then
      record_diagnostic_failure(options, {
        kind = "identity",
        recipe = recipe_name,
        variant = variant_name,
        identity = deepcopy(output_identity),
        reason = "recipe-not-enabled"
      })
    else
      local results = normalized_results(variant, options)
      if not diagnostic_visit(options) then return nil
      elseif not results_include_positive(results, output_identity, options) then
        record_diagnostic_failure(options, {
          kind = "identity",
          recipe = recipe_name,
          variant = variant_name,
          identity = deepcopy(output_identity),
          reason = "output-identity-mismatch"
        })
      elseif variant.energy_required ~= nil
        and not finite_positive(tonumber(variant.energy_required)) then
        record_diagnostic_failure(options, {
          kind = "identity",
          recipe = recipe_name,
          variant = variant_name,
          identity = deepcopy(output_identity),
          reason = "invalid-energy-required"
        })
      elseif not surface_satisfied(variant.surface_conditions, options, state) then
        record_diagnostic_failure(options, {
          kind = "identity",
          recipe = recipe_name,
          variant = variant_name,
          identity = deepcopy(output_identity),
          reason = "surface-conditions-unsatisfied"
        })
      else
        local has_machine = false
        local categories = variant.categories or {"crafting"}
        for _, category in ipairs(categories) do
          if not diagnostic_visit(options) then return nil end
          if compatible_machine(category, options, state) then has_machine = true; break end
        end
        if has_machine then
          local ingredients_ok, ingredient_witnesses = true, {}
          for _, ingredient in ipairs(normalized_ingredients(variant)) do
            if not diagnostic_visit(options) then return nil end
            local ingredient_identity = normalize_identity(ingredient)
            if not ingredient_identity
              or not finite_positive(tonumber(ingredient.amount or ingredient.amount_max or ingredient[2] or 1)) then
              record_diagnostic_failure(options, {
                kind = "identity",
                recipe = recipe_name,
                variant = variant_name,
                identity = deepcopy(output_identity),
                reason = "invalid-ingredient-identity"
              })
              ingredients_ok = false
              break
            end
            local witness = acquisition_witness(ingredient_identity, options, state)
            if not witness then
              record_diagnostic_failure(options, {
                kind = "ingredient",
                recipe = recipe_name,
                variant = variant_name,
                identity = deepcopy(ingredient_identity),
                reason = "unreachable-acquisition"
              })
              ingredients_ok = false
              break
            end
            table.insert(ingredient_witnesses, witness)
          end
          if ingredients_ok then
            -- A reachable variant selects this recipe route. None of the
            -- diagnostic events produced by discarded sibling alternatives
            -- are a structural failure of the selected route.
            diagnostic_rollback(options, route_checkpoint)
            return {
              kind = "recipe",
              recipe = recipe_name,
              variant = variant.name or "default",
              output = deepcopy(output_identity),
              ingredients = ingredient_witnesses
            }
          end
        else
          record_diagnostic_failure(options, {
            kind = "category",
            recipe = recipe_name,
            variant = variant_name,
            category = categories[1],
            identity = deepcopy(output_identity),
            reason = "no-compatible-machine-category"
          })
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

local function stable_cacheable(options)
  return options.diagnostic_observer == nil
    and type(options.source_witness) ~= "function"
    and type(options.machine_category_witness) ~= "function"
    and type(options.surface_witness) ~= "function"
end

local STABLE_SOURCE_KINDS = {
  ["minable-resource"] = true,
  ["minable-entity"] = true,
  ["entity-loot"] = true,
  ["offshore-pump"] = true,
  ["boiler-conversion"] = true
}

local function stable_acquisition_witness(witness)
  if type(witness) ~= "table" then return false end
  if STABLE_SOURCE_KINDS[witness.kind] then return true end
  if witness.kind ~= "recipe" then return false end
  for _, ingredient in ipairs(witness.ingredients or {}) do
    if not stable_acquisition_witness(ingredient) then return false end
  end
  return true
end

-- A source witness or one enabled recipe alternative proves a product. The
-- active type/name set makes recursive requirements AND, recipe alternatives
-- OR, and rejects unseeded cycles. Default raw-prototype scans are cached only
-- inside this one query state; no feasibility result is retained globally.
local function acquisition_witness_impl(output_identity, options, state)
  if not diagnostic_visit(options) then return nil end
  local key = identity_key(output_identity)
  local may_use_stable = stable_cacheable(options)
  if may_use_stable and state.stable_acquisition_memo[key] ~= nil then
    return deepcopy(state.stable_acquisition_memo[key])
  end
  -- A recursive answer is conditional on the caller's active cycle set. Only
  -- a root query can safely memoize a positive or negative acquisition result;
  -- recursive calls still reuse the bounded raw-prototype scan indexes.
  local root_query = next(state.visiting) == nil
  local may_cache = root_query and cacheable(options)
  if may_cache and state.acquisition_memo[key] ~= nil then
    local cached = state.acquisition_memo[key]
    if cached == false then return nil end
    return deepcopy(cached)
  end
  if state.visiting[key] then
    record_diagnostic_failure(options, {
      kind = "cycle",
      identity = deepcopy(output_identity),
      reason = "active-acquisition-identity"
    })
    return nil
  end

  local direct = source_witness(output_identity, options, state)
  if direct then
    if may_use_stable and stable_acquisition_witness(direct) then
      state.stable_acquisition_memo[key] = deepcopy(direct)
    end
    if may_cache then state.acquisition_memo[key] = deepcopy(direct) end
    return direct
  end

  local acquisition_checkpoint = diagnostic_checkpoint(options)
  state.visiting[key] = true
  for _, recipe_name in ipairs(sorted_producers(options.recipe_index, output_identity, options)) do
    if not diagnostic_visit(options) then
      state.visiting[key] = nil
      return nil
    end
    -- Producer recipes are alternatives. Preserve only the branch being
    -- evaluated, rather than accumulating causes from discarded siblings.
    diagnostic_rollback(options, acquisition_checkpoint)
    local witness = route_for_recipe(recipe_name, output_identity, options, state, true)
    if witness then
      state.visiting[key] = nil
      -- As with recipe variants, one reachable producer proves acquisition;
      -- provisional failures from other producers cannot be propagated as the
      -- selected branch's explanation.
      diagnostic_rollback(options, acquisition_checkpoint)
      if may_use_stable and stable_acquisition_witness(witness) then
        state.stable_acquisition_memo[key] = deepcopy(witness)
      end
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
    -- A researched acquisition is the final alternative. If it rejects, its
    -- concrete technology/pair cause is more specific than an earlier
    -- disabled producer and is therefore the selected failure tree.
    diagnostic_rollback(options, acquisition_checkpoint)
    if not diagnostic_visit(options) then
      state.visiting[key] = nil
      return nil
    end
    local witness = options.research_unlock_witness(deepcopy(output_identity), state)
    if witness then
      state.visiting[key] = nil
      if may_cache then state.acquisition_memo[key] = deepcopy(witness) end
      return witness
    end
  end
  state.visiting[key] = nil
  if may_cache then state.acquisition_memo[key] = false end
  record_diagnostic_failure(options, {
    kind = "ingredient",
    identity = deepcopy(output_identity),
    reason = "no-enabled-acquisition-route"
  })
  return nil
end

acquisition_witness = function(output_identity, options, state)
  -- Depth is observation-only and lives on the already query-local options
  -- table. It never participates in source selection, cycle detection, or
  -- acquisition memoization.
  local previous_depth = options.diagnostic_depth or 0
  options.diagnostic_depth = previous_depth + 1
  local witness
  if diagnostic_visit(options, options.diagnostic_depth) then
    witness = acquisition_witness_impl(output_identity, options, state)
  end
  options.diagnostic_depth = previous_depth
  return witness
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

function M.initial_recipe_witness(recipe_name, output, options, state)
  -- Never mutate the caller's option table: a caller can safely reuse it for a
  -- later locked-route query without inheriting require_enabled=true.
  local initial_options = copy_options(options)
  initial_options.require_enabled = true
  -- Initial availability is a strict enabled-only proof. A future
  -- research-unlocked ingredient may establish a later route, but it must not
  -- turn an enabled outer recipe into an initial acquisition witness.
  initial_options.research_unlock_witness = nil
  return M.recipe_witness(recipe_name, output, initial_options, state)
end

return M
