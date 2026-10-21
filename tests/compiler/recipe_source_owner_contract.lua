-- Recipe source ownership opponents run inside approved_family_emission's
-- ordinary F200 data-stage-shaped runtime. They exercise public boundaries and
-- compiler decisions; no private owner table is inspected directly.
local M = {}

function M.run(check)
  local Context = require("prototypes.mir.pipeline.compiler_context")
  local recipes = require("prototypes.mir.index.recipe_facts")
  local deepcopy = require("prototypes.mir.core.deepcopy")
  local fingerprint = require("prototypes.mir.core.fingerprint")
  local checks = 0
  local function verify(value, message)
    check(value, message)
    checks = checks + 1
  end
  local function source(name, result)
    return {[name] = {
      name = name, category = "crafting", enabled = true,
      ingredients = {{type = "item", name = name .. "-ore", amount = 1}},
      results = {{type = "item", name = result, amount = 1}}
    }}
  end
  local function result_named(results, name)
    for _, result in ipairs(results or {}) do
      if result.name == name then return result end
    end
  end

  -- The host runner installs the Factorio-compatible deepcopy prefix before
  -- modules load. Keep an explicit semantic check here because source capture,
  -- generic snapshots, and public values all depend on alias/cycle/metatable
  -- behavior rather than the product's reduced fallback copier.
  local deepcopy_meta = {marker = "recipe-source-owner-deepcopy"}
  local deepcopy_alias = setmetatable({value = "alias"}, deepcopy_meta)
  local deepcopy_input = {first = deepcopy_alias, second = deepcopy_alias}
  deepcopy_input.self = deepcopy_input
  local deepcopy_copy = deepcopy(deepcopy_input)
  verify(deepcopy_copy ~= deepcopy_input and deepcopy_copy.self == deepcopy_copy
      and deepcopy_copy.first ~= deepcopy_alias and deepcopy_copy.first == deepcopy_copy.second
      and getmetatable(deepcopy_copy.first) == deepcopy_meta,
    "Recipe source controls use the Factorio-compatible alias/cycle/metatable deepcopy contract")

  -- A captured plain source is detached from both the original caller and a
  -- public get()/snapshot value. Its one shared metadata value remains an
  -- alias in the supported raw-source snapshot without becoming mutable owner
  -- state through either boundary.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local shared = {min = 0.2, max = 0.8}
    local owned = source("owned-recipe", "owned-part")
    owned["owned-recipe"].results = {
      {type = "item", name = "owned-part", amount = 1, shared_probability = shared},
      {type = "item", name = "owned-byproduct", amount = 1, shared_probability = shared}
    }
    recipes.replace_source(owned, recipes.source_epoch())
    owned["owned-recipe"].results[1].name = "caller-mutated-part"
    shared.min = 0

    local identity = recipes.active_input_identity()
    local fact = recipes.view("owned-recipe")
    local owned_fact_result = result_named(fact.results, "owned-part")
    local owned_variant_result = result_named(fact.variants[1].results, "owned-part")
    verify(identity.schema == 2 and identity.record_type == "RecipeSemanticInput"
        and identity.contract == "mir-recipe-semantic-source-v2"
        and type(identity.semantic_source_fingerprint) == "string"
        and owned_fact_result ~= nil
        and owned_variant_result.shared_probability.min == 0.2,
      "Plain replacement owns all selected recipe semantics before caller mutation")

    local raw = Context.current():state_snapshot("recipe_source")
    local raw_owned = result_named(raw["owned-recipe"].results, "owned-part")
    local raw_byproduct = result_named(raw["owned-recipe"].results, "owned-byproduct")
    verify(raw_owned ~= nil and raw_byproduct ~= nil
        and raw_owned.shared_probability == raw_byproduct.shared_probability
        and raw_owned.shared_probability.min == 0.2,
      "Supported raw-source export stays detached while retaining its declared metadata alias")

    local exported = recipes.get("owned-recipe")
    result_named(exported.results, "owned-part").name = "public-mutated-part"
    result_named(exported.variants[1].results, "owned-part").shared_probability.min = 0
    local owned_view = recipes.view("owned-recipe")
    verify(result_named(owned_view.results, "owned-part") ~= nil
        and result_named(owned_view.variants[1].results, "owned-part").shared_probability.min == 0.2,
      "Public RecipeFact copies cannot mutate the active semantic source")

    local before_epoch = recipes.source_epoch()
    local before_fingerprint = identity.semantic_source_fingerprint
    recipes.replace_source(source("owned-recipe", "replacement-part"), before_epoch)
    local replacement = recipes.active_input_identity()
    verify(recipes.source_epoch() == before_epoch + 1
        and replacement.semantic_source_fingerprint ~= before_fingerprint
        and recipes.view("owned-recipe").results[1].name == "replacement-part",
      "Explicit source replacement advances the owner epoch and recomputes consumed semantics")
  end)

  -- A duplicate virtual source and a dynamic entry are existing generic-input
  -- shapes. They must select the v1 normalized-index contract before semantic
  -- reads, retaining the original discovery and getter behavior.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local first = {name = "duplicate", category = "crafting", result = "first-output"}
    local final = {name = "duplicate", category = "crafting", result = "final-output"}
    local duplicate = setmetatable({}, {
      __pairs = function()
        local ordinal = 0
        return function()
          ordinal = ordinal + 1
          if ordinal == 1 then return "duplicate", first end
          if ordinal == 2 then return "duplicate", final end
        end
      end
    })
    recipes.replace_source(duplicate, recipes.source_epoch())
    local identity = recipes.active_input_identity()
    local index = recipes.index_view()
    verify(identity.record_type == "RecipeNormalizedInput"
        and identity.contract == "mir-recipe-normalized-input-v1"
        and identity.exceptional_complete_index_fingerprint ~= nil
        and index.facts.duplicate.main_product == "final-output"
        and index.by_output["first-output"] and index.by_output["final-output"]
        and #index.names == 2,
      "Duplicate virtual keys retain the full generic discovery/index boundary")
  end)

  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local entry_reads = 0
    local dynamic_entry = setmetatable({name = "dynamic-product", amount = 1}, {
      __index = function(_, key)
        if key == "independent_probability" then entry_reads = entry_reads + 1; return 1 end
      end
    })
    local dynamic = source("dynamic-entry", "ignored")
    dynamic["dynamic-entry"].results = {dynamic_entry}
    recipes.replace_source(dynamic, recipes.source_epoch())
    verify(entry_reads == 0, "Dynamic recipe entries are rejected before semantic probability reads")
    local identity = recipes.active_input_identity()
    verify(identity.record_type == "RecipeNormalizedInput"
        and identity.contract == "mir-recipe-normalized-input-v1" and entry_reads > 0,
      "Dynamic recipe entries retain the generic getter/read-order boundary")
  end)

  -- Nested virtual metadata and cycles remain generic facts. The former must
  -- not be observed during semantic admission; the latter preserves the legacy
  -- view-first/fingerprint-error behavior instead of being silently accepted.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local callbacks = 0
    local nested = setmetatable({}, {
      __pairs = function(value)
        callbacks = callbacks + 1
        return next, value, nil
      end
    })
    local dynamic = source("dynamic-metadata", "dynamic-metadata-part")
    dynamic["dynamic-metadata"].surface_conditions = {{property = "pressure", nested = nested}}
    recipes.replace_source(dynamic, recipes.source_epoch())
    verify(callbacks == 0, "Nested dynamic metadata is not observed during semantic admission")
    local identity = recipes.active_input_identity()
    verify(identity.contract == "mir-recipe-normalized-input-v1" and callbacks > 0,
      "Nested dynamic metadata falls back to the established generic reader")
  end)

  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local cycle = {}; cycle.self = cycle
    local cyclic = source("cyclic-metadata", "cyclic-part")
    cyclic["cyclic-metadata"].surface_conditions = cycle
    recipes.replace_source(cyclic, recipes.source_epoch())
    local view_ok, fact = pcall(function() return recipes.view("cyclic-metadata") end)
    local active_ok, active_error = pcall(recipes.active_input_identity)
    verify(view_ok and fact.name == "cyclic-metadata" and not active_ok
        and tostring(active_error):find("fingerprint", 1, true),
      "Cyclic retained metadata preserves the generic view and fingerprint rejection boundary")
  end)

  -- Unsupported retained source values keep the legacy converter's timing:
  -- replacement and a generic view succeed where they did before, while the
  -- established complete fingerprint rejects the malformed value only when
  -- an identity is requested. Semantic admission must not move that rejection
  -- ahead of Context ownership.
  local function generic_identity_failure(label, mutate, assertion)
    Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
      local candidate = source(label, label .. "-part")
      mutate(candidate[label])
      local before_epoch = recipes.source_epoch()
      local replaced, replacement_error = pcall(recipes.replace_source, candidate, before_epoch)
      local viewed, fact = pcall(recipes.view, label)
      local identified, identity_error = pcall(recipes.active_input_identity)
      verify(replaced and viewed and fact.name == label
          and recipes.source_epoch() == before_epoch + 1
          and not identified
          and tostring(identity_error):lower():find("fingerprint", 1, true),
        assertion .. ": replacement/view retain the legacy boundary and identity rejects there"
          .. (replacement_error and " (unexpected replacement error: " .. tostring(replacement_error) .. ")" or ""))
    end)
  end

  generic_identity_failure("cyclic-entry-amount", function(recipe)
    local cycle = {}; cycle.self = cycle
    recipe.results[1].amount = cycle
  end, "Cyclic normalized entry amount")

  generic_identity_failure("function-entry-scalar", function(recipe)
    recipe.results[1].extra_count_fraction = function() return 1 end
  end, "Unsupported normalized entry scalar")

  generic_identity_failure("function-surface-conditions", function(recipe)
    recipe.surface_conditions = function() return nil end
  end, "Unsupported retained surface conditions")

  generic_identity_failure("root-main-product-cycle", function(recipe)
    local cycle = {}; cycle.self = cycle
    recipe.main_product = cycle
  end, "Cyclic root main_product")

  generic_identity_failure("variant-energy-cycle", function(recipe)
    local cycle = {}; cycle.self = cycle
    recipe.energy_required = cycle
  end, "Cyclic variant energy_required")

  generic_identity_failure("declared-productivity-cycle", function(recipe)
    local cycle = {}; cycle.self = cycle
    recipe.maximum_productivity = cycle
  end, "Cyclic declared maximum_productivity")

  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local getter_reads = 0
    local candidate = source("dynamic-variant-energy", "dynamic-variant-part")
    setmetatable(candidate["dynamic-variant-energy"], {
      __index = function(_, key)
        if key == "energy_required" then
          getter_reads = getter_reads + 1
          return function() return nil end
        end
      end
    })
    local before_epoch = recipes.source_epoch()
    local replaced = pcall(recipes.replace_source, candidate, before_epoch)
    local reads_before_view = getter_reads
    local viewed, fact = pcall(recipes.view, "dynamic-variant-energy")
    local reads_after_view = getter_reads
    local identified, identity_error = pcall(recipes.active_input_identity)
    verify(replaced and reads_before_view == 0
        and viewed and fact.name == "dynamic-variant-energy"
        and reads_after_view > reads_before_view
        and not identified
        and tostring(identity_error):lower():find("fingerprint", 1, true),
      "Dynamic variant getter stays unread during semantic admission and retains generic view/fingerprint timing")
  end)
  -- A malformed entries carrier historically reaches the generic converter
  -- untouched: replacing the source succeeds, then the first generic view
  -- reports its own invalid iteration. Semantic admission must not move that
  -- failure to replace_source().
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local invalid_entries = source("invalid-ingredients-carrier", "invalid-ingredients-part")
    invalid_entries["invalid-ingredients-carrier"].ingredients = 5
    local before_epoch = recipes.source_epoch()
    local replaced = pcall(recipes.replace_source, invalid_entries, before_epoch)
    local viewed = pcall(recipes.view, "invalid-ingredients-carrier")
    verify(replaced and recipes.source_epoch() == before_epoch + 1 and not viewed,
      "Malformed ingredients carrier preserves generic replace-before-view failure timing")
  end)
  -- Explicit source replacement must not eagerly deep-copy metadata that no
  -- generic fact or semantic owner consumes. A virtual ignored field selects
  -- the established generic converter before any callback; its normalized
  -- identity remains the legacy v1 contract because the field is not a fact.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local callbacks = 0
    local unknown_metadata = setmetatable({}, {
      __pairs = function(value)
        callbacks = callbacks + 1
        return next, value, nil
      end
    })
    local candidate = source("unknown-virtual-metadata", "unknown-virtual-part")
    candidate["unknown-virtual-metadata"].custom_note = unknown_metadata
    local before_epoch = recipes.source_epoch()
    local replaced = pcall(recipes.replace_source, candidate, before_epoch)
    local viewed, fact = pcall(recipes.view, "unknown-virtual-metadata")
    local identity = replaced and recipes.active_input_identity() or nil
    verify(replaced and viewed and fact.name == "unknown-virtual-metadata"
        and callbacks == 0 and recipes.source_epoch() == before_epoch + 1
        and identity and identity.record_type == "RecipeNormalizedInput"
        and identity.contract == "mir-recipe-normalized-input-v1",
      "Ignored virtual recipe metadata falls back before replacement copy and retains generic identity")
  end)
  -- The full-map replacement guard applies only to explicit caller input.
  -- Ordinary active-only capture must independently reject a retained cycle
  -- from data.raw at the generic fingerprint boundary, after preserving the
  -- established view. Restore the fixture value before the Context unwinds.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local ordinary = assert(data.raw.recipe["iron-plate"])
    local original_amount = ordinary.results[1].amount
    local cycle = {}; cycle.self = cycle
    ordinary.results[1].amount = cycle
    local viewed, fact = pcall(recipes.view, "iron-plate")
    local identified, identity_error = pcall(recipes.active_input_identity)
    ordinary.results[1].amount = original_amount
    verify(viewed and fact.name == "iron-plate" and not identified
        and tostring(identity_error):lower():find("fingerprint", 1, true),
      "Ordinary active capture preserves cyclic normalized entry view then generic fingerprint rejection")
  end)

  -- String entries are a supported compact Factorio shape. The semantic owner
  -- must retain v2 active identity while the on-demand generic export remains
  -- byte-equivalent to the established direct normalized index.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local shorthand = source("string-entry-shorthand", "unused-result")
    shorthand["string-entry-shorthand"].ingredients = {"string-entry-ingredient"}
    shorthand["string-entry-shorthand"].results = {"string-entry-result"}
    local expected = recipes.index_prototypes(shorthand)
    recipes.replace_source(shorthand, recipes.source_epoch())
    local identity = recipes.active_input_identity()
    local exported = Context.current():state_snapshot("recipe_index")
    verify(identity.record_type == "RecipeSemanticInput"
        and identity.contract == "mir-recipe-semantic-source-v2"
        and fingerprint.canonical(exported) == fingerprint.canonical(expected)
        and fingerprint.of(exported) == fingerprint.of(expected),
      "String recipe entries retain owned v2 identity and exact generic export")
  end)

  -- Acyclic tables in normally scalar semantics are valid generic input but
  -- must not enter an owned semantic record by reference. Generic v1 identity
  -- keeps the established converter rather than claiming an owned witness.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local scalar_table = {declared = "not-a-number"}
    local candidate = source("table-variant-energy", "table-variant-part")
    candidate["table-variant-energy"].energy_required = scalar_table
    recipes.replace_source(candidate, recipes.source_epoch())
    local viewed, fact = pcall(recipes.view, "table-variant-energy")
    local identity = recipes.active_input_identity()
    verify(viewed and fact.name == "table-variant-energy"
        and identity.record_type == "RecipeNormalizedInput"
        and identity.contract == "mir-recipe-normalized-input-v1",
      "Acyclic table in a scalar variant field retains generic identity without owned-source borrowing")
  end)
  -- Route callbacks receive detached scalar descriptors. Mutating a retained
  -- descriptor cannot affect a later route query, a fact consumed by planning,
  -- or the active identity that names those decisions.
  Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()
    local routed = source("route-owned", "route-part")
    routed["route-owned"].results[1].shared_probability = {min = 0.2, max = 0.8}
    recipes.replace_source(routed, recipes.source_epoch())
    local before = recipes.active_input_identity().semantic_source_fingerprint
    local escaped
    recipes.for_each_route_variant(function(_, variant)
      escaped = variant.results[1]
      escaped.name = "route-mutated"
      escaped.shared_probability.min = 0
    end)
    local later
    recipes.for_each_route_variant(function(_, variant) later = variant.results[1] end)
    verify(recipes.active_input_identity().semantic_source_fingerprint == before
        and recipes.view("route-owned").results[1].name == "route-part"
        and later.name == "route-part" and later.shared_probability.min == 0.2
        and escaped ~= later and escaped.shared_probability ~= later.shared_probability,
      "Route consumers receive detached descriptors rather than retained semantic entries")
  end)

  -- An active-only Context keeps the full recipe index deferred, but its
  -- explicit supported state snapshot may materialize that exact schema-2
  -- export. Cross-context demand restores the caller's active Context and all
  -- returned values remain isolated.
  local first = Context.new({legacy_compiler_export_requested = false})
  local second = Context.new({legacy_compiler_export_requested = false})
  Context.with_active(first, function()
    recipes.replace_source(source("first-owned", "first-part"), recipes.source_epoch())
    local identity = recipes.active_input_identity()
    verify(identity.contract == "mir-recipe-semantic-source-v2"
        and first:has_service("recipe_facts.materialize_export")
        and first:state_view("recipe_index") == nil,
      "Active compiler registers a deferred generic recipe export without an eager index")
  end)
  Context.with_active(second, function()
    recipes.replace_source(source("second-owned", "second-part"), recipes.source_epoch())
    recipes.active_input_identity()
    verify(second:state_view("recipe_index") == nil,
      "Independent active Contexts retain separate deferred recipe indexes")
  end)
  Context.with_active(first, function()
    local second_index = second:state_snapshot("recipe_index")
    verify(Context.current() == first and second_index.facts["second-owned"].results[1].name == "second-part",
      "Nested generic export activates its owner then restores the prior Context")
    local first_index = first:state_snapshot("recipe_index")
    first_index.facts["first-owned"].results[1].name = "snapshot-mutated"
    verify(first:state_snapshot("recipe_index").facts["first-owned"].results[1].name == "first-part",
      "Demand-materialized generic recipe index remains a detached public snapshot")
    local source_epoch = recipes.source_epoch()
    recipes.replace_source(source("first-owned", "replacement-part"), source_epoch)
    verify(first:state_snapshot("recipe_index").facts["first-owned"].results[1].name == "replacement-part",
      "Deferred export follows explicit owner epoch replacement rather than a stale source")
  end)

  return checks
end

return M
