local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_semantics = require("prototypes.mir.domain.facts.recipe_semantics")
local recipe_risk_facts = require("prototypes.mir.index.recipe_risk_facts")
local item_prototype_facts = require("prototypes.mir.index.item_prototype_facts")
local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local automatic_compiler_policy = require("prototypes.mir.settings.automatic_compiler_policy")
local relationships = require("prototypes.mir.index.relationships")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")

local R = {}

local DEFAULT_SKIP_CATEGORIES = {
  recycling = true
}

local function merge_lists(a, b)
  local out = {}
  if a then for _, v in ipairs(a) do table.insert(out, v) end end
  if b then for _, v in ipairs(b) do table.insert(out, v) end end
  if #out == 0 then return nil end
  return out
end

local function recipe_categories(recipe)
  return recipe.categories or {"crafting"}
end

local function recipe_is_hidden(recipe)
  return recipe.hidden == true
end

local function has_category(recipe, categories)
  if not categories then return false end
  local wanted = {}
  for _, category in ipairs(categories) do wanted[category] = true end
  for _, category in ipairs(recipe_categories(recipe)) do
    if wanted[category] then return true end
  end
  return false
end

local function name_matches(name, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if string.find(name, pattern) then return true end
  end
  return false
end

function R.matches_stream_recipe_filter(recipe_name, recipe, stream)
  local match = stream and stream.match
  if not match then return false end
  return has_category(recipe, match.categories)
    or name_matches(recipe_name, match.name_patterns)
    or name_matches(recipe_name, match.recipe_patterns)
end

local function recipe_uses_blocked_ingredient(rec, patterns)
  if not patterns then return false end
  local function matches(name)
    for _, pat in ipairs(patterns) do
      if string.find(name, pat) then return true end
    end
    return false
  end
  for _, name in ipairs(rec.ingredient_names or {}) do
    if matches(name) then return true end
  end
  return false
end

local function typed_identity(entry)
  if type(entry) ~= "table" or type(entry.type) ~= "string" or entry.type == ""
    or type(entry.name) ~= "string" or entry.name == "" then
    return nil
  end
  return entry.type .. "\30" .. entry.name
end

local function has_productive_shared_input_output(recipe)
  for _, variant in ipairs(recipe.variants or {}) do
    local ingredients = {}
    for _, entry in ipairs(variant.ingredients or {}) do
      local identity = typed_identity(entry)
      if not identity then return true end
      ingredients[identity] = true
    end
    for _, entry in ipairs(variant.results or {}) do
      local maximum = recipe_semantics.maximum_base_result_amount(entry)
      local ignored = recipe_semantics.productivity_excluded_amount(entry, target_profiles.current())
      local identity = typed_identity(entry)
      local extra = tonumber(entry.extra_count_fraction or 0)
      -- A base-quantity exclusion does not certify extra item bonus rolls.
      -- Withhold that return, including malformed rolls, until separately
      -- qualified; this guard is not a numeric profitable-loop proof.
      local extra_return = entry.type == "item" and (extra == nil or extra ~= 0)
      if not identity or (ingredients[identity] and (maximum - ignored > 0 or extra_return)
        and not recipe_semantics.result_is_definitely_zero(entry, target_profiles.current(), true)) then return true end
    end
  end
  return false
end

local function has_explicit_productivity_denial(recipe)
  if recipe.declared_allow_productivity == false then return true end
  if tonumber(recipe.declared_maximum_productivity) == 0 then return true end
  for _, variant in ipairs(recipe.variants or {}) do
    if variant.declared_allow_productivity == false then return true end
    if tonumber(variant.declared_maximum_productivity) == 0 then return true end
  end
  return false
end

-- A sufficient, deliberately conservative graph guard for ordinary material
-- routes. A possible return path remains rejected unless the separate,
-- version-locked reviewed-forward-route certificate below proves the exact
-- final route is an ordinary, deterministic, non-recovery process.
local function material_graph()
  return compiler_context.current():state_view("material_route_graph", function()
    local graph = {typed_edges = {}, native_edges = {}, spoilage_transitions = {},
      fuel_burning_transitions = {}, complete = true, edge_count = 0}
    recipe_facts.for_each(function(_, fact)
      for _, variant in ipairs(fact.variants or {}) do
        local outputs = {}
        for _, output in ipairs(variant.results or {}) do
          local identity = typed_identity(output)
          if not identity then
            graph.complete, graph.reason = false, "process-graph-identity"
            return
          end
          if not recipe_semantics.result_is_definitely_zero(output, target_profiles.current(), true) then
            outputs[#outputs + 1] = identity
          end
        end
        for _, input in ipairs(variant.ingredients or {}) do
          local input_identity = typed_identity(input)
          if not input_identity then
            graph.complete, graph.reason = false, "process-graph-identity"
            return
          end
          graph.typed_edges[input_identity] = graph.typed_edges[input_identity] or {}
          for _, output_identity in ipairs(outputs) do
            if not graph.typed_edges[input_identity][output_identity] then
              graph.edge_count = graph.edge_count + 1
              if graph.edge_count > 100000 then graph.complete = false; return end
              graph.typed_edges[input_identity][output_identity] = true
            end
          end
        end
      end
    end)
    local function append_native_return(kind, source, result)
      local input_identity = typed_identity({type = "item", name = source})
      local output_identity = typed_identity({type = "item", name = result})
      graph.typed_edges[input_identity] = graph.typed_edges[input_identity] or {}
      if not graph.typed_edges[input_identity][output_identity] then
        graph.edge_count = graph.edge_count + 1
        if graph.edge_count > 100000 then graph.complete = false; return end
        graph.typed_edges[input_identity][output_identity] = true
      end
      graph.native_edges[input_identity] = graph.native_edges[input_identity] or {}
      graph.native_edges[input_identity][output_identity] = graph.native_edges[input_identity][output_identity] or kind
      return input_identity, output_identity
    end
    item_prototype_facts.for_each_spoilage(function(source, result, ticks)
      local input_identity, output_identity = append_native_return("spoilage", source, result)
      if not input_identity then return end
      graph.spoilage_transitions[#graph.spoilage_transitions + 1] = {
        source = input_identity, result = output_identity, ticks = ticks
      }
    end)
    item_prototype_facts.for_each_fuel_burning(function(transition)
      local input_identity, output_identity = append_native_return("fuel-burning", transition.source, transition.result)
      if not input_identity then return end
      transition.source, transition.result = input_identity, output_identity
      graph.fuel_burning_transitions[#graph.fuel_burning_transitions + 1] = transition
    end)
    return graph
  end)
end

local function sorted_keys(set)
  local out = {}
  for key in pairs(set or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function route_identities(recipe, field)
  local out = {}
  for _, variant in ipairs((recipe and recipe.variants) or {}) do
    for _, entry in ipairs(variant[field] or {}) do
      local identity = typed_identity(entry)
      if identity and (field ~= "results"
        or not recipe_semantics.result_is_definitely_zero(entry, target_profiles.current(), true)) then out[identity] = true end
    end
  end
  return out
end

-- Recipe facts use a NUL-delimited identity in their immutable lookup tables,
-- while the material graph keeps its private typed identities separated with
-- record-separator.  Keep conversion at this boundary so a same-named item
-- and fluid can never share an indexed return-cone membership query.
local function recipe_index_identity(identity)
  if type(identity) ~= "string" then return nil end
  local separator = string.find(identity, "\30", 1, true)
  if not separator or separator == 1 or separator == #identity then return nil end
  return string.sub(identity, 1, separator - 1) .. "\0" .. string.sub(identity, separator + 1)
end

local function indexed_recipe_names(index, names, selected)
  if type(names) ~= "table" then return false end
  local previous, count = nil, 0
  for ordinal, recipe_name in ipairs(names) do
    if ordinal ~= count + 1 or type(recipe_name) ~= "string" or recipe_name == ""
      or (previous and previous >= recipe_name) or type(index.facts[recipe_name]) ~= "table" then
      return false
    end
    selected[recipe_name] = true
    previous, count = recipe_name, ordinal
  end
  -- ipairs deliberately stops at the first gap.  The canonical index has
  -- dense arrays, so reject a substituted or partial bucket rather than
  -- accepting an empty-safe boundary.
  for key in pairs(names) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) or key > count then return false end
  end
  return true
end

-- The authoritative recipe-fact index already records every ingredient and
-- result identity, including hidden variants and zero-result facts.  Query it
-- directly after graph reachability instead of rescanning all facts for every
-- route.  A missing, malformed, or replaced typed projection returns nil so
-- the caller can preserve the established full-scan semantics.
local function indexed_relevant_return_facts(index, reached, outputs)
  if index ~= compiler_context.current():state_view("recipe_index")
    or type(index) ~= "table" or index.schema ~= 2 or type(index.facts) ~= "table"
    or type(index.by_ingredient_identity) ~= "table" or type(index.by_output_identity) ~= "table" then
    return nil
  end
  local selected, direct_output_producers = {}, {}
  for _, identity in ipairs(sorted_keys(reached)) do
    local key = recipe_index_identity(identity)
    if not key or not indexed_recipe_names(index, index.by_ingredient_identity[key] or {}, selected) then
      return nil
    end
  end
  for _, identity in ipairs(sorted_keys(outputs)) do
    local key = recipe_index_identity(identity)
    if not key or not indexed_recipe_names(index, index.by_output_identity[key] or {}, selected) then
      return nil
    end
    for _, recipe_name in ipairs(index.by_output_identity[key] or {}) do
      direct_output_producers[recipe_name] = true
    end
  end
  return selected, direct_output_producers
end

-- Retain the direct fact scan as the conservative compatibility path for a
-- noncanonical index.  Normal compilation uses the typed projections above;
-- this path prevents an incomplete index from granting an empty boundary.
local function scanned_relevant_return_facts(index, reached, outputs)
  local selected, direct_output_producers = {}, {}
  for recipe_name, fact in pairs(index.facts) do
    local consumes_reached = false
    for _, variant in ipairs(fact.variants or {}) do
      for _, entry in ipairs(variant.ingredients or {}) do
        if reached[typed_identity(entry)] then consumes_reached = true; break end
      end
      if consumes_reached then break end
    end
    if consumes_reached then selected[recipe_name] = true end
    for _, variant in ipairs(fact.variants or {}) do
      for _, entry in ipairs(variant.results or {}) do
        if outputs[typed_identity(entry)] then
          selected[recipe_name] = true
          direct_output_producers[recipe_name] = true
          break
        end
      end
    end
  end
  return selected, direct_output_producers
end

-- Build the exact typed return cone for one productivity route.  It includes
-- every recipe which consumes a value reachable from the route's result, plus
-- every direct producer of that result.  Therefore a disconnected extension
-- is outside the certificate, while an added return edge, a changed hidden
-- witness, or another producer of the finished result changes it.  The cone
-- uses the canonical recipe-fact index and shares the ordinary material graph
-- budget; an incomplete graph never grants a profile exception.
local function relevant_return_graph(recipe)
  if type(recipe) ~= "table" or type(recipe.name) ~= "string" or recipe.name == ""
    or type(recipe.variants) ~= "table" or #recipe.variants == 0 then
    return nil, "route"
  end
  local graph = material_graph()
  if not graph.complete then return nil, graph.reason or "process-graph-budget" end
  local outputs, inputs = route_identities(recipe, "results"), route_identities(recipe, "ingredients")
  if next(outputs) == nil or next(inputs) == nil then return nil, "route-identities" end

  local queue, reached = {}, {}
  for _, identity in ipairs(sorted_keys(outputs)) do queue[#queue + 1], reached[identity] = identity, true end
  local head = 1
  while head <= #queue do
    if head > 30000 then return nil, "process-search-budget" end
    local identity = queue[head]
    head = head + 1
    for next_identity in pairs(graph.typed_edges[identity] or {}) do
      if not reached[next_identity] then
        reached[next_identity] = true
        queue[#queue + 1] = next_identity
      end
    end
  end

  local index = recipe_facts.index_view()
  if type(index) ~= "table" or type(index.facts) ~= "table" then return nil, "recipe-index" end
  local selected, direct_output_producers = indexed_relevant_return_facts(index, reached, outputs)
  if not selected then
    telemetry.count("material_return_graph_index_fallbacks", 1)
    selected, direct_output_producers = scanned_relevant_return_facts(index, reached, outputs)
  else
    telemetry.count("material_return_graph_index_queries", 1)
  end
  local facts = {}
  for _, recipe_name in ipairs(sorted_keys(selected)) do
    facts[#facts + 1] = {name = recipe_name, fact = index.facts[recipe_name]}
  end
  local boundary = {
    schema = 1,
    route = recipe.name,
    input_identities = sorted_keys(inputs),
    output_identities = sorted_keys(outputs),
    reachable_identities = sorted_keys(reached),
    direct_output_producers = sorted_keys(direct_output_producers),
    facts = facts
  }
  -- Preserve historical recipe-only fingerprints when no native conversion
  -- touches the cone. A changed relevant item transition invalidates its
  -- certificate even when reachable names and recipe facts stay identical.
  for _, transition in ipairs(graph.spoilage_transitions) do
    if reached[transition.source] or outputs[transition.result] then
      boundary.spoilage_transitions = boundary.spoilage_transitions or {}
      boundary.spoilage_transitions[#boundary.spoilage_transitions + 1] = transition
    end
  end
  for _, transition in ipairs(graph.fuel_burning_transitions) do
    if reached[transition.source] or outputs[transition.result] then
      boundary.fuel_burning_transitions = boundary.fuel_burning_transitions or {}
      boundary.fuel_burning_transitions[#boundary.fuel_burning_transitions + 1] = transition
    end
  end
  return boundary
end

local function relevant_route_bindings(recipe_name)
  local index = relationships.view("input")
  if type(index) ~= "table" then return nil, "relationship-index" end
  local owners = {}
  for _, name in ipairs((index.technologies_by_recipe_effect or {})[recipe_name] or {}) do
    -- The certificate observes ownership external to the MIR technology it is
    -- currently generating.  Its own stable recipe-prod-* row can exist in a
    -- later final-data observer, whereas a foreign owner remains material.
    if not string.match(name, "^recipe%-prod%-") then owners[#owners + 1] = name end
  end
  table.sort(owners)
  local unlocks = {}
  for _, name in ipairs((index.unlocks_by_recipe or {})[recipe_name] or {}) do
    local technology = data_raw.technology(name)
    if type(technology) ~= "table" or type(technology.unit) ~= "table" then return nil, "unlock" end
    local science, prerequisites = {}, {}
    for _, entry in ipairs(technology.unit.ingredients or {}) do
      local pack, amount = entry.name or entry[1], tonumber(entry.amount or entry[2])
      if type(pack) ~= "string" or pack == "" or amount == nil or amount <= 0 then return nil, "unlock-science" end
      science[#science + 1] = {name = pack, amount = amount}
    end
    table.sort(science, function(left, right) return left.name < right.name end)
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if type(prerequisite) ~= "string" or prerequisite == "" then return nil, "unlock-prerequisite" end
      prerequisites[#prerequisites + 1] = prerequisite
    end
    table.sort(prerequisites)
    unlocks[#unlocks + 1] = {name = name, science_ingredients = science, prerequisites = prerequisites}
  end
  table.sort(unlocks, function(left, right) return left.name < right.name end)
  return {schema = 1, recipe = recipe_name, productivity_owner_technologies = owners, unlock_technologies = unlocks}
end

-- Schema 2 binds ownership, bonus values and the recursive science frontier
-- for every recipe in the cone, including alternate finished-output producers.
-- Schema 1 observed only the starting recipe and cannot authorize extensions.
local function relevant_cone_bindings(recipe, boundary)
  local index = relationships.view("input")
  if type(index) ~= "table" then return nil, "relationship-index" end
  local recipe_names = {[recipe.name] = true}
  for _, row in ipairs(boundary.facts) do recipe_names[row.name] = true end
  local rows, frontier_names = {}, {}
  for _, recipe_name in ipairs(sorted_keys(recipe_names)) do
    local owners, unlocks = {}, {}
    for _, name in ipairs((index.technologies_by_recipe_effect or {})[recipe_name] or {}) do
      if type(name) ~= "string" or name == "" then return nil, "owner-identity" end
      if not generated_registry.is_stream(name) then
        local technology = data_raw.technology(name)
        if type(technology) ~= "table" then return nil, "owner" end
        local changes = {}
        for _, effect in ipairs(technology.effects or {}) do
          if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
            local change = effect.change
            if type(change) ~= "number" or change ~= change or change == math.huge or change == -math.huge then
              return nil, "owner-effect"
            end
            changes[#changes + 1] = change
          end
        end
        if #changes == 0 then return nil, "owner-effect" end
        table.sort(changes)
        owners[#owners + 1] = {name = name, changes = changes}
        frontier_names[name] = true
      end
    end
    table.sort(owners, function(left, right) return left.name < right.name end)
    for _, name in ipairs((index.unlocks_by_recipe or {})[recipe_name] or {}) do
      if type(name) ~= "string" or name == "" then return nil, "unlock-identity" end
      unlocks[#unlocks + 1], frontier_names[name] = name, true
    end
    table.sort(unlocks)
    rows[#rows + 1] = {recipe = recipe_name, productivity_owners = owners, unlock_technologies = unlocks}
  end
  local queue, frontier = sorted_keys(frontier_names), {}
  local head = 1
  while head <= #queue do
    if head > 10000 then return nil, "science-frontier-budget" end
    local name = queue[head]
    head = head + 1
    local technology = data_raw.technology(name)
    if type(technology) ~= "table" or
      (type(technology.unit) ~= "table" and type(technology.research_trigger) ~= "table") then
      return nil, "science-frontier"
    end
    local prerequisites = {}
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if type(prerequisite) ~= "string" or prerequisite == "" then return nil, "science-frontier-identity" end
      prerequisites[#prerequisites + 1] = prerequisite
      if not frontier_names[prerequisite] then
        frontier_names[prerequisite] = true
        queue[#queue + 1] = prerequisite
      end
    end
    table.sort(prerequisites)
    frontier[#frontier + 1] = {
      name = name, prerequisites = prerequisites, unit = technology.unit,
      research_trigger = technology.research_trigger, max_level = technology.max_level,
      enabled = technology.enabled, hidden = technology.hidden,
      ignore_tech_cost_multiplier = technology.ignore_tech_cost_multiplier
    }
  end
  table.sort(frontier, function(left, right) return left.name < right.name end)
  return {schema = 2, route = recipe.name, recipes = rows, science_frontier = frontier}
end

-- Read-only facts for observers and matching. Unrelated recipes and
-- technologies remain outside this boundary. Keep schema-1 readback explicit
-- so historical receipts retain their original meaning and byte identity.
function R.relevant_route_fingerprints(recipe, schema)
  schema = schema or 1
  if schema ~= 1 and schema ~= 2 then return nil, "bindings-schema" end
  local boundary, boundary_reason = relevant_return_graph(recipe)
  if not boundary then return nil, boundary_reason end
  local bindings, bindings_reason
  if schema == 1 then bindings, bindings_reason = relevant_route_bindings(recipe.name)
  else bindings, bindings_reason = relevant_cone_bindings(recipe, boundary) end
  if not bindings then return nil, bindings_reason end
  return {
    schema = schema,
    return_graph_fingerprint = fingerprint.of(boundary),
    bindings_fingerprint = fingerprint.of(bindings),
    reachable_identity_count = #boundary.reachable_identities,
    relevant_recipe_count = #boundary.facts,
    direct_output_producer_count = #boundary.direct_output_producers
  }
end

-- Capture while matching still reads the real compiler input. Observers must
-- not reconstruct this phase from post-emission prototypes or retained contexts.
-- Scalar-only audit rows use the existing opt-in diagnostics channel.
local function observe_route_contract(recipe)
  if not diagnostics.enabled() then return end
  local context = compiler_context.current()
  -- A fresh finalized observer context cannot manufacture input-phase proof.
  -- Pipeline input sanitation precedes selection; the journal starts emission.
  if context:command_status("sanitize-input-technology-effects") ~= "applied"
    or context:state_view("mutation_journal") ~= nil then return end
  local observations = context:state_view("material_route_contract_observations", function()
    return {count = 0, recipes = {}, budget_reported = false}
  end)
  if observations.recipes[recipe.name] then return end
  -- Reserve one row for an explicit incomplete-capture marker.
  if observations.count >= 255 then
    if not observations.budget_reported then
      diagnostics.material_route_certificate({phase = "input", binding_schema = 2,
        status = "incomplete", reason = "observation-row-budget", observed_route_count = observations.count})
      observations.budget_reported = true
    end
    return
  end
  local contract, reason = R.relevant_route_fingerprints(recipe, 2)
  local row = {recipe = recipe.name, phase = "input", binding_schema = 2,
    status = contract and "observed" or "unavailable", reason = reason}
  if contract then
    for field, value in pairs(contract) do
      if field ~= "schema" then row[field] = value end
    end
    local risk = recipe_risk_facts.view(recipe.name)
    row.canonical_risk_fingerprint = risk and risk.risk_fingerprint
  end
  observations.recipes[recipe.name] = true
  observations.count = observations.count + 1
  diagnostics.material_route_certificate(row)
end

function R.material_route_is_acyclic(recipe)
  if not recipe or recipe.allow_productivity ~= true then return false, "productivity-not-allowed" end
  if type(recipe.variants) ~= "table" or #recipe.variants == 0 then return false, "missing-process-variants" end
  local graph = material_graph()
  if not graph.complete then return false, graph.reason or "process-graph-budget" end
  local recipe_return
  for _, variant in ipairs(recipe.variants or {}) do
    local inputs, queue, native_steps, visited, native_visited = {}, {}, {}, {}, {}
    for _, input in ipairs(variant.ingredients or {}) do
      local identity = typed_identity(input)
      if not identity then return false, "missing-process-identity" end
      inputs[identity] = input.name
    end
    for _, output in ipairs(variant.results or {}) do
      local identity = typed_identity(output)
      if not identity then return false, "missing-process-identity" end
      if not visited[identity] and not recipe_semantics.result_is_definitely_zero(output, target_profiles.current(), true) then
        queue[#queue + 1] = identity; visited[identity] = true
      end
    end
    local head = 1
    while head <= #queue do
      if head > 30000 then return false, "process-search-budget" end
      local identity, native_kind = queue[head], native_steps[head]
      head = head + 1
      if inputs[identity] then
        -- Recipe-only certificates have no authority over a native return.
        -- Continue past an ordinary return so traversal order cannot hide a
        -- second path that uses a native conversion.
        if native_kind then return false, "potential-" .. native_kind .. "-return-path:" .. inputs[identity] end
        recipe_return = "potential-return-path:" .. inputs[identity]
        if next(graph.native_edges) == nil then return false, recipe_return end
      end
      local native_edges = graph.native_edges[identity]
      for next_identity in pairs(graph.typed_edges[identity] or {}) do
        local kind = native_kind or native_edges and native_edges[next_identity]
        local seen = kind and native_visited or visited
        if not seen[next_identity] then
          seen[next_identity] = true
          queue[#queue + 1] = next_identity
          if kind then native_steps[#queue] = kind end
        end
      end
    end
  end
  if recipe_return then return false, recipe_return end
  return true, "no-recipe-return-path"
end

-- This list is deliberately paired with recipe_facts.normalized_entry(). A
-- reviewed route must bind all current semantic fields, and a future field in
-- that authority fails closed here until the certificate contract is reviewed.
local REVIEWED_ENTRY_FIELDS = {
  "type", "name", "amount", "amount_min", "amount_max", "probability",
  "independent_probability", "declared_probability", "declared_independent_probability",
  "shared_probability", "extra_count_fraction", "catalyst_amount",
  "ignored_by_productivity", "ignored_by_stats", "temperature",
  "minimum_temperature", "maximum_temperature", "fluidbox_index",
  "percent_spoiled", "always_fresh", "reset_freshness_on_craft",
  "quality_min", "quality_max", "quality_change", "affected_by_quality"
}

local REVIEWED_ENTRY_FIELD_SET = {}
for _, field in ipairs(REVIEWED_ENTRY_FIELDS) do REVIEWED_ENTRY_FIELD_SET[field] = true end

local function has_only_reviewed_entry_fields(entry)
  if type(entry) ~= "table" then return false end
  for field in pairs(entry) do
    if not REVIEWED_ENTRY_FIELD_SET[field] then return false end
  end
  return true
end

local function normalized_probability(entry, field)
  local value = entry[field]
  return tonumber(value == nil and 1 or value)
end

local function reviewed_entry_value(entry, field)
  if field == "probability" or field == "independent_probability" then
    return normalized_probability(entry, field)
  end
  return entry[field]
end

local function positive_fixed_amount(value)
  local number = tonumber(value)
  return number ~= nil and number == number and number ~= math.huge and number ~= -math.huge and number > 0
end

local function zero_or_nil(value)
  return value == nil or (type(value) == "number" and value == 0)
end

local function ordinary_deterministic_entry(entry)
  return positive_fixed_amount(entry.amount)
    and normalized_probability(entry, "probability") == 1
    and normalized_probability(entry, "independent_probability") == 1
    and (entry.declared_probability == nil or entry.declared_probability == 1)
    and (entry.declared_independent_probability == nil or entry.declared_independent_probability == 1)
    and entry.shared_probability == nil
    and entry.amount_min == nil
    and entry.amount_max == nil
    and zero_or_nil(entry.extra_count_fraction)
    and zero_or_nil(entry.catalyst_amount)
    and zero_or_nil(entry.ignored_by_productivity)
    and zero_or_nil(entry.ignored_by_stats)
end

local function exact_entry(actual, expected)
  if not has_only_reviewed_entry_fields(actual) or not has_only_reviewed_entry_fields(expected)
    or not ordinary_deterministic_entry(actual) or not ordinary_deterministic_entry(expected) then
    return false
  end
  for _, field in ipairs(REVIEWED_ENTRY_FIELDS) do
    if reviewed_entry_value(actual, field) ~= reviewed_entry_value(expected, field) then
      return false
    end
  end
  return type(actual.type) == "string" and actual.type ~= ""
    and type(actual.name) == "string" and actual.name ~= ""
    and type(expected.type) == "string" and expected.type ~= ""
    and type(expected.name) == "string" and expected.name ~= ""
end

local function exact_entries(entries, expected)
  if type(entries) ~= "table" or type(expected) ~= "table" or #entries ~= #expected then
    return false
  end
  for index, actual in ipairs(entries) do
    if not exact_entry(actual, expected[index]) then return false end
  end
  return true
end

local function exact_mod_lock(mod_locks, runtime_mods, observer_mod_locks, scope, complete_structural_binding)
  if type(mod_locks) ~= "table" or type(runtime_mods) ~= "table" then return false end
  scope = scope or "closed"
  if scope ~= "closed" and scope ~= "named-relevant-providers" and scope ~= "relevant-return-graph" then return false end
  local count = 0
  for name, expected in pairs(mod_locks) do
    count = count + 1
    if type(name) ~= "string" or name == "" or type(expected) ~= "string" or expected == "" or runtime_mods[name] ~= expected then return false end
  end
  -- Only a schema-2 cone contract can replace provider-version pins.
  -- Schema-3 closed-output records retain their explicit provider locks.
  if count == 0 and not (scope == "relevant-return-graph" and complete_structural_binding) then return false end
  observer_mod_locks = observer_mod_locks or {}
  if type(observer_mod_locks) ~= "table" then return false end
  for name, expected in pairs(observer_mod_locks) do
    if type(name) ~= "string" or name == "" or type(expected) ~= "string" or expected == "" then return false end
    if runtime_mods[name] ~= nil and runtime_mods[name] ~= expected then return false end
  end
  for name, actual in pairs(runtime_mods) do
    local expected = mod_locks[name] or observer_mod_locks[name]
    -- The named relevant-provider policy leaves only MIR's package version
    -- outside the external provider fingerprint.  It is deliberately not a
    -- general unlisted-mod allowance: an unknown extension can alter a
    -- return graph outside the direct recipe certificate.  The separate
    -- relevant-return-graph scope admits an unknown extension only after its
    -- exact typed boundary and route bindings have matched below.
    local mir_bookkeeping = scope == "named-relevant-providers"
      and name == "more-infinite-research" and mod_locks[name] == nil
      and observer_mod_locks[name] == nil
    if type(name) ~= "string" or type(actual) ~= "string" or actual == ""
      or (scope ~= "relevant-return-graph" and not mir_bookkeeping and expected ~= actual) then return false end
  end
  return true
end

local function valid_mir32_fingerprint(value)
  return type(value) == "string" and #value == 14
    and string.match(value, "^mir32%-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil
end

local function dense_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for index in pairs(value) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then return false end
    count = count + 1
  end
  return count == #value
end

local function empty_dense_array(value)
  return dense_array(value) and #value == 0
end

local function exact_string_list(actual, expected)
  if type(actual) ~= "table" or type(expected) ~= "table"
    or not dense_array(actual) or not dense_array(expected) or #actual ~= #expected then return false end
  local actual_seen, expected_seen = {}, {}
  for _, value in ipairs(actual) do
    if type(value) ~= "string" or value == "" or actual_seen[value] then return false end
    actual_seen[value] = true
  end
  for _, value in ipairs(expected) do
    if type(value) ~= "string" or value == "" or expected_seen[value] or not actual_seen[value] then return false end
    expected_seen[value] = true
  end
  return true
end

local function exact_science_ingredients(actual, expected)
  if type(actual) ~= "table" or type(expected) ~= "table"
    or not dense_array(actual) or not dense_array(expected) or #actual ~= #expected then return false end
  local function normalized(entries)
    local out, seen = {}, {}
    for _, entry in ipairs(entries) do
      if type(entry) ~= "table" then return nil end
      local name = entry.name or entry[1]
      local amount = tonumber(entry.amount or entry[2])
      if type(name) ~= "string" or name == "" or amount == nil or amount <= 0 or seen[name] then return nil end
      seen[name] = true
      out[name] = amount
    end
    return out
  end
  local actual_entries, expected_entries = normalized(actual), normalized(expected)
  if not actual_entries or not expected_entries then return false end
  for name, amount in pairs(expected_entries) do
    if actual_entries[name] ~= amount then return false end
  end
  return true
end

-- A blocked return witness can have ranged results, so it cannot use the
-- ordinary deterministic final-route predicate.  Its normalized I/O must
-- nevertheless match exactly; otherwise a changed disabled recipe could
-- silently become a different graph witness under a named-provider route.
local function exact_witness_entry(actual, expected)
  if not has_only_reviewed_entry_fields(actual) or not has_only_reviewed_entry_fields(expected) then return false end
  for _, field in ipairs(REVIEWED_ENTRY_FIELDS) do
    if reviewed_entry_value(actual, field) ~= reviewed_entry_value(expected, field) then return false end
  end
  return type(actual.type) == "string" and actual.type ~= ""
    and type(actual.name) == "string" and actual.name ~= ""
    and type(expected.type) == "string" and expected.type ~= ""
    and type(expected.name) == "string" and expected.name ~= ""
end

local function exact_witness_entries(entries, expected)
  if type(entries) ~= "table" or type(expected) ~= "table" or #entries ~= #expected then return false end
  for index, actual in ipairs(entries) do
    if not exact_witness_entry(actual, expected[index]) then return false end
  end
  return true
end

local function relevant_input_contract_matches(recipe_name, contract)
  if type(contract) ~= "table" or type(contract.productivity_owner_technologies) ~= "table"
    or type(contract.unlock_technologies) ~= "table" or type(contract.return_path) ~= "string"
    or contract.return_path == "" or type(contract.return_witnesses) ~= "table"
    or not dense_array(contract.unlock_technologies) or not dense_array(contract.return_witnesses)
    or #contract.return_witnesses == 0 then
    return false, "contract"
  end
  local index = relationships.view("input")
  if type(index) ~= "table" then return false, "contract" end
  local owners = (index.technologies_by_recipe_effect or {})[recipe_name] or {}
  if not exact_string_list(owners, contract.productivity_owner_technologies) then return false, "owner" end

  local unlock_names, seen = {}, {}
  for _, expected in ipairs(contract.unlock_technologies) do
    if type(expected) ~= "table" or type(expected.name) ~= "string" or expected.name == ""
      or seen[expected.name] or type(expected.science_ingredients) ~= "table"
      or type(expected.prerequisites) ~= "table" then
      return false, "contract"
    end
    seen[expected.name] = true
    unlock_names[#unlock_names + 1] = expected.name
  end
  local actual_unlocks = (index.unlocks_by_recipe or {})[recipe_name] or {}
  if not exact_string_list(actual_unlocks, unlock_names) then return false, "unlock" end
  for _, expected in ipairs(contract.unlock_technologies) do
    local technology = data_raw.technology(expected.name)
    if type(technology) ~= "table" or type(technology.unit) ~= "table"
      or not exact_science_ingredients(technology.unit.ingredients, expected.science_ingredients)
      or not exact_string_list(technology.prerequisites, expected.prerequisites) then
      return false, "unlock-science-or-prerequisite"
    end
  end
  local witness_seen = {}
  for _, expected in ipairs(contract.return_witnesses) do
    if type(expected) ~= "table" or type(expected.name) ~= "string" or expected.name == ""
      or witness_seen[expected.name] or expected.hidden ~= true
      or expected.enabled_without_research ~= false or expected.source_class ~= "hidden-internal"
      or type(expected.variants) ~= "table" or not dense_array(expected.variants)
      or #expected.variants == 0 then
      return false, "return-witness-contract"
    end
    witness_seen[expected.name] = true
    local fact = recipe_facts.view(expected.name)
    if type(fact) ~= "table" or fact.name ~= expected.name or fact.hidden ~= true
      or fact.enabled_without_research ~= false or fact.source_class ~= "hidden-internal"
      or type(fact.variants) ~= "table" or #fact.variants ~= #expected.variants then
      return false, "return-witness"
    end
    for index, expected_variant in ipairs(expected.variants) do
      local variant = fact.variants[index]
      if type(expected_variant) ~= "table" or expected_variant.hidden ~= true
        or expected_variant.enabled ~= false or type(expected_variant.ingredients) ~= "table"
        or type(expected_variant.results) ~= "table" or type(variant) ~= "table"
        or variant.hidden ~= true or variant.enabled ~= false
        or not exact_witness_entries(variant.ingredients, expected_variant.ingredients)
        or not exact_witness_entries(variant.results, expected_variant.results) then
        return false, "return-witness"
      end
    end
  end
  return true, "accepted"
end

-- Schema 3 names the stable safety property for a closed final output rather
-- than fingerprinting every field of its direct producers. It keeps explicit
-- provider locks: unlike schema 2, it never authorizes an empty-pin profile.
-- A hidden recycler may consume and return the finished item, but only the
-- exact lossy, non-productive self-recycler shape is outside the ordinary
-- return path. All other consumers remain material to the boundary.
-- Permission, risk, target ownership, unlock progression, and exact route I/O
-- remain checked by the normal certificate path.
local function safe_recycling_entry_shape(entry)
  return has_only_reviewed_entry_fields(entry)
    and entry.amount_min == nil and entry.amount_max == nil
    and entry.shared_probability == nil and zero_or_nil(entry.extra_count_fraction)
    and zero_or_nil(entry.catalyst_amount) and zero_or_nil(entry.ignored_by_productivity)
    and entry.temperature == nil and entry.minimum_temperature == nil and entry.maximum_temperature == nil
    and entry.fluidbox_index == nil and entry.percent_spoiled == nil
    and entry.always_fresh == nil and entry.reset_freshness_on_craft == nil
    and entry.quality_min == nil and entry.quality_max == nil
    and entry.quality_change == nil and entry.affected_by_quality == nil
end

local function safe_recycling_input(entry, expected_identity)
  local amount = tonumber(type(entry) == "table" and entry.amount or nil)
  return safe_recycling_entry_shape(entry) and typed_identity(entry) == expected_identity
    and positive_fixed_amount(amount) and normalized_probability(entry, "probability") == 1
    and normalized_probability(entry, "independent_probability") == 1
    and (entry.declared_probability == nil or entry.declared_probability == 1)
    and (entry.declared_independent_probability == nil or entry.declared_independent_probability == 1)
    and tonumber(entry.ignored_by_stats) == amount
end

local function safe_recycling_result(entry, expected_identity, input_amount)
  local amount = tonumber(type(entry) == "table" and entry.amount or nil)
  local probability = normalized_probability(entry, "independent_probability")
  return safe_recycling_entry_shape(entry) and typed_identity(entry) == expected_identity
    and positive_fixed_amount(amount) and positive_fixed_amount(input_amount) and amount <= input_amount
    and probability ~= nil and probability > 0 and probability < 1
    and normalized_probability(entry, "probability") == probability
    and entry.declared_probability == nil and entry.declared_independent_probability == probability
    and tonumber(entry.ignored_by_stats) == amount
end

local function non_productive_recycling_variant(variant)
  if variant.allow_productivity == false and variant.effective_allow_productivity == false then return true end
  if variant.allow_productivity ~= nil or variant.effective_allow_productivity ~= nil
    or variant.declared_allow_productivity ~= nil then return false end
  -- The current fact schema retains nil for an absent declaration whose
  -- native default is false. Do not reinterpret unknown fields or defaults,
  -- or rewrite historical fact fingerprints merely to admit this recycler.
  local profile = target_profiles.current()
  local defaults = profile and profile.prototype_shapes and profile.prototype_shapes.recipe_property_defaults
  return type(defaults) == "table" and defaults.allow_productivity == false
end

local function safe_lossy_recycling_self_return(fact, expected_identity)
  if type(fact) ~= "table" or fact.hidden ~= true or fact.source_class ~= "recycling"
    or fact.enabled_without_research ~= false or fact.allow_productivity ~= false
    or fact.effective_allow_productivity ~= false
    or not exact_string_list(fact.categories, {"recycling"})
    or type(fact.variants) ~= "table" or #fact.variants ~= 1 then
    return false
  end
  local variant = fact.variants[1]
  if type(variant) ~= "table" or variant.hidden ~= true or variant.enabled ~= false
    or not non_productive_recycling_variant(variant)
    or not exact_string_list(variant.categories, {"recycling"})
    or type(variant.ingredients) ~= "table" or #variant.ingredients ~= 1
    or type(variant.results) ~= "table" or #variant.results ~= 1 then
    return false
  end
  local input, result = variant.ingredients[1], variant.results[1]
  if not safe_recycling_input(input, expected_identity) then return false end
  return safe_recycling_result(result, expected_identity, tonumber(input.amount))
end

local function closed_output_boundary_matches(recipe, contract)
  local closed = contract.closed_output
  if type(closed) ~= "table" or type(closed.type) ~= "string" or closed.type == ""
    or type(closed.name) ~= "string" or closed.name == ""
    or not exact_string_list(closed.direct_output_producers, closed.direct_output_producers) or #closed.direct_output_producers == 0 then
    return false, "closed-output-contract"
  end
  for field in pairs(closed) do
    if field ~= "type" and field ~= "name" and field ~= "direct_output_producers" then
      return false, "closed-output-contract"
    end
  end
  local expected_identity = typed_identity({type = closed.type, name = closed.name})
  if not expected_identity then return false, "closed-output-contract" end
  local boundary, reason = relevant_return_graph(recipe)
  if not boundary then return false, reason end
  if #boundary.output_identities ~= 1 or boundary.output_identities[1] ~= expected_identity
    or #boundary.reachable_identities ~= 1 or boundary.reachable_identities[1] ~= expected_identity
    or #boundary.reachable_identities ~= contract.reachable_identity_count
    or #boundary.facts ~= contract.relevant_recipe_count
    or #boundary.direct_output_producers ~= contract.direct_output_producer_count
    or #(boundary.spoilage_transitions or {}) ~= 0 or #(boundary.fuel_burning_transitions or {}) ~= 0 then
    return false, "closed-output-reachability"
  end
  local fact_names = {}
  for _, row in ipairs(boundary.facts) do
    local fact = type(row) == "table" and row.fact or nil
    if type(row) ~= "table" or type(row.name) ~= "string" or row.name == ""
      or type(fact) ~= "table" or fact.name ~= row.name or type(fact.variants) ~= "table" then
      return false, "closed-output-facts"
    end
    -- The target remains subject to the ordinary exact route checks. Another
    -- finished-output producer is either hidden internal with no self-return,
    -- or the constrained lossy native recycler described above.
    if row.name ~= recipe.name then
      if fact.source_class == "recycling" then
        if not safe_lossy_recycling_self_return(fact, expected_identity) then
          return false, "closed-output-recycling-self-return"
        end
      elseif fact.hidden ~= true or fact.source_class ~= "hidden-internal" then
        return false, "closed-output-hidden-producer"
      end
    end
    local produces_expected = false
    for _, variant in ipairs(fact.variants) do
      if type(variant) ~= "table" then return false, "closed-output-facts" end
      for _, ingredient in ipairs(variant.ingredients or {}) do
        if typed_identity(ingredient) == expected_identity and row.name ~= recipe.name
          and fact.source_class ~= "recycling" then
          return false, "closed-output-consumer"
        end
      end
      for _, result in ipairs(variant.results or {}) do
        if typed_identity(result) == expected_identity then produces_expected = true end
      end
    end
    if not produces_expected then return false, "closed-output-producer" end
    fact_names[#fact_names + 1] = row.name
  end
  if #fact_names ~= #boundary.direct_output_producers
    or not exact_string_list(fact_names, closed.direct_output_producers)
    or not exact_string_list(boundary.direct_output_producers, closed.direct_output_producers) then
    return false, "closed-output-producers"
  end
  return true, "accepted"
end
local function relevant_return_graph_contract_matches(recipe, contract)
  if type(contract) ~= "table" or (contract.schema ~= 1 and contract.schema ~= 2 and contract.schema ~= 3)
    or not valid_mir32_fingerprint(contract.bindings_fingerprint)
    or type(contract.reachable_identity_count) ~= "number" or contract.reachable_identity_count < 1
    or contract.reachable_identity_count ~= math.floor(contract.reachable_identity_count)
    or type(contract.relevant_recipe_count) ~= "number" or contract.relevant_recipe_count < 1
    or contract.relevant_recipe_count ~= math.floor(contract.relevant_recipe_count)
    or type(contract.direct_output_producer_count) ~= "number" or contract.direct_output_producer_count < 1
    or contract.direct_output_producer_count ~= math.floor(contract.direct_output_producer_count) then
    return false, "return-graph-contract"
  end
  if contract.schema == 3 then
    for field in pairs(contract) do
      if field ~= "schema" and field ~= "bindings_fingerprint"
        and field ~= "reachable_identity_count" and field ~= "relevant_recipe_count"
        and field ~= "direct_output_producer_count" and field ~= "closed_output" then
        return false, "return-graph-contract"
      end
    end
    local closed, closed_reason = closed_output_boundary_matches(recipe, contract)
    if not closed then return false, "return-graph-" .. closed_reason end
    local bindings, bindings_reason = relevant_route_bindings(recipe.name)
    if not bindings then return false, "return-graph-" .. bindings_reason end
    if fingerprint.of(bindings) ~= contract.bindings_fingerprint then return false, "return-graph-bindings" end
    return true, "accepted"
  end
  if not valid_mir32_fingerprint(contract.return_graph_fingerprint) then return false, "return-graph-contract" end
  for field in pairs(contract) do
    if field ~= "schema" and field ~= "return_graph_fingerprint" and field ~= "bindings_fingerprint"
      and field ~= "reachable_identity_count" and field ~= "relevant_recipe_count"
      and field ~= "direct_output_producer_count" then
      return false, "return-graph-contract"
    end
  end
  local actual, reason = R.relevant_route_fingerprints(recipe, contract.schema)
  if not actual then return false, "return-graph-" .. reason end
  if actual.return_graph_fingerprint ~= contract.return_graph_fingerprint
    or actual.bindings_fingerprint ~= contract.bindings_fingerprint
    or actual.reachable_identity_count ~= contract.reachable_identity_count
    or actual.relevant_recipe_count ~= contract.relevant_recipe_count
    or actual.direct_output_producer_count ~= contract.direct_output_producer_count then
    return false, "return-graph"
  end
  return true, "accepted"
end
local function matching_profile(profiles, runtime_mods, graph_contract, fact, risk)
  if type(profiles) ~= "table" or #profiles == 0 then return nil, "profile-missing" end
  local structural_binding_matches
  for _, profile in ipairs(profiles) do
    local complete_structural_binding = false
    local structural_contract_validated = false
    if type(profile) == "table" and profile.mod_lock_scope == "relevant-return-graph"
      and type(profile.mod_locks) == "table" and next(profile.mod_locks) == nil
      and type(graph_contract) == "table" and graph_contract.schema == 2 then
      -- An empty-pin replacement must agree with the already validated
      -- canonical risk before paying for its complete graph traversal. This
      -- keeps a wrong-risk structural profile from masking a later pinned one.
      if profile.canonical_risk_fingerprint == risk.risk_fingerprint then
        -- Validate the replacement boundary before choosing an unpinned
        -- profile. A malformed structural profile must not mask a later valid
        -- pinned one. Existing pinned-only profiles do not query this path.
        if structural_binding_matches == nil then
          structural_binding_matches = relevant_return_graph_contract_matches(fact, graph_contract)
        end
        complete_structural_binding = structural_binding_matches == true
        structural_contract_validated = complete_structural_binding
      end
    end
    if type(profile) == "table" and type(profile.id) == "string" and profile.id ~= ""
      and valid_mir32_fingerprint(profile.canonical_risk_fingerprint)
      and exact_mod_lock(profile.mod_locks, runtime_mods, profile.observer_mod_locks, profile.mod_lock_scope, complete_structural_binding) then
      return profile, "matched", structural_contract_validated
    end
  end
  return nil, "mod-lock", false
end

local reviewed_forward_routes = {}

function reviewed_forward_routes.admits(recipe_name, fact, risk, certificate, runtime_mods, return_reason)
  if type(certificate) ~= "table" or type(certificate.id) ~= "string" or certificate.id == ""
    or type(certificate.evidence_id) ~= "string" or certificate.evidence_id == ""
    or tonumber(certificate.maximum_productivity) ~= 3.0 then
    return false, "certificate-identity"
  end
  if not fact or fact.name ~= recipe_name or fact.source_class ~= "ordinary" or fact.hidden
    or fact.effective_allow_productivity ~= true or fact.declared_allow_productivity ~= true
    or fact.allow_productivity ~= true then
    return false, "permission-or-visibility"
  end
  local maximum_productivity = tonumber(fact.effective_maximum_productivity)
  if maximum_productivity == nil or maximum_productivity > tonumber(certificate.maximum_productivity) then
    return false, "maximum-productivity"
  end
  if not risk or risk.schema ~= 1 or risk.recipe ~= recipe_name
    or not empty_dense_array(risk.hard_flags) or not empty_dense_array(risk.review_flags)
    or not empty_dense_array(risk.shared_input_output) or tonumber(risk.evidence_confidence) ~= 1.0
    or not valid_mir32_fingerprint(risk.risk_fingerprint) then
    return false, "canonical-risk"
  end
  local profile, profile_reason, structural_contract_validated = matching_profile(certificate.profiles, runtime_mods, certificate.relevant_return_graph_contract, fact, risk)
  if not profile then return false, profile_reason end
  if profile.canonical_risk_fingerprint ~= risk.risk_fingerprint then
    return false, "canonical-risk"
  end
  if profile.mod_lock_scope == "named-relevant-providers" then
    local relevant, relevant_reason = relevant_input_contract_matches(recipe_name, certificate.relevant_input_contract)
    if not relevant then return false, "relevant-" .. relevant_reason end
    if return_reason and return_reason ~= "potential-return-path:" .. certificate.relevant_input_contract.return_path then
      return false, "return-path"
    end
  elseif profile.mod_lock_scope == "relevant-return-graph" then
    -- An old direct-route binding cannot certify ownership/progression changes
    -- made by an unlisted extension. Preserve the exact observed provider set
    -- (and MIR version bookkeeping); broader admission requires schema 2.
    local contract = certificate.relevant_return_graph_contract
    if type(contract) == "table" and contract.schema == 1
      and not exact_mod_lock(profile.mod_locks, runtime_mods, profile.observer_mod_locks, "named-relevant-providers") then
      return false, "return-graph-bindings-upgrade-required"
    end
    local relevant, relevant_reason
    if structural_contract_validated then
      -- The selected empty-pin schema-2 profile was fully checked synchronously
      -- above. Reuse only this call-local result; later phase and return checks
      -- still execute below and no mutable route object escapes this function.
      relevant, relevant_reason = true, "accepted"
    else
      relevant, relevant_reason = relevant_return_graph_contract_matches(fact, certificate.relevant_return_graph_contract)
    end
    if not relevant then return false, "relevant-" .. relevant_reason end
    if certificate.relevant_input_contract then
      local input_matches, input_reason = relevant_input_contract_matches(recipe_name, certificate.relevant_input_contract)
      if not input_matches then return false, "relevant-" .. input_reason end
      if return_reason and return_reason ~= "potential-return-path:" .. certificate.relevant_input_contract.return_path then
        return false, "return-path"
      end
    elseif return_reason then
      return false, "return-path-unwitnessed"
    end
  end
  if #(fact.variants or {}) ~= 1 then return false, "variant-count" end
  local variant = fact.variants[1]
  if variant.effective_allow_productivity ~= true or variant.declared_allow_productivity ~= true
    or tonumber(variant.effective_maximum_productivity) == nil
    or tonumber(variant.effective_maximum_productivity) > tonumber(certificate.maximum_productivity) then
    return false, "variant-permission-or-cap"
  end
  if not exact_entries(variant.ingredients, certificate.ingredients)
    or not exact_entries(variant.results, certificate.results) then
    return false, "io-shape"
  end
  return true, "accepted"
end
local function should_skip_recipe(recipe_name, recipe, options)
  if type(recipe.productive_result_names) == "table" and #recipe.productive_result_names == 0 then
    return true
  end
  local certificate = options.reviewed_forward_routes and options.reviewed_forward_routes[recipe_name]
  if type(certificate) == "table" then observe_route_contract(recipe) end
  local certificate_required = options.require_exact_route_certificate == true
    or (type(certificate) == "table" and certificate.require_exact_route_certificate == true)
  local certificate_admitted, certificate_reason = false, "certificate-not-required"
  if certificate_required then
    certificate_admitted, certificate_reason = reviewed_forward_routes.admits(
      recipe_name, recipe, recipe_risk_facts.view(recipe_name), certificate, mods)
    if not certificate_admitted then
      if log then log("[more-infinite-research] Material route omitted recipe=" .. recipe_name .. " reason=certificate-rejected:" .. certificate_reason) end
      return true
    end
  end
  if options.require_acyclic_process then
    local admitted, reason = R.material_route_is_acyclic(recipe)
    if not admitted then
      local certified = false
      certificate_reason = "certificate-not-applicable"
      if string.sub(reason, 1, 22) == "potential-return-path:" and certificate then
        if certificate_required then
          certified, certificate_reason = reviewed_forward_routes.admits(
            recipe_name, recipe, recipe_risk_facts.view(recipe_name), certificate, mods, reason)
        else
          certified, certificate_reason = reviewed_forward_routes.admits(recipe_name, recipe, recipe_risk_facts.view(recipe_name), certificate, mods, reason)
        end
      end
      if not certified then
        local reported_reason = certificate and ("certificate-rejected:" .. certificate_reason) or reason
        if log then log("[more-infinite-research] Material route omitted recipe=" .. recipe_name .. " reason=" .. reported_reason) end
        return true
      end
      if log then log("[more-infinite-research] Material route admitted recipe=" .. recipe_name .. " reason=reviewed-forward-route:" .. certificate.id) end
    end
  end
  if options.exclude_recipe_patterns and name_matches(recipe_name, options.exclude_recipe_patterns) then
    return true
  end
  if recipe_uses_blocked_ingredient(recipe, options.exclude_ingredient_patterns) then
    return true
  end
  if recipe_is_hidden(recipe) and not options.include_hidden then
    return true
  end
  if options.reject_explicit_productivity_denial and has_explicit_productivity_denial(recipe) then
    return true
  end
  if has_productive_shared_input_output(recipe) and not options.allow_shared_input_output then return true end
  if not options.include_recycling then
    for _, category in ipairs(recipe_categories(recipe)) do
      if DEFAULT_SKIP_CATEGORIES[category] then return true end
    end
  end
  return false
end

local function add_wanted_outputs(want, names)
  for _, name in ipairs(names or {}) do
    want[name] = true
  end
end

local function add_pattern_outputs(want, patterns, iterator)
  if not patterns then return end
  iterator(function(name)
    for _, pat in ipairs(patterns) do
      if string.find(name, pat) then want[name] = true end
    end
  end)
end

local function add_module_outputs(want, options)
  local tiers = options.module_tiers
  local tier_set = nil
  if type(tiers) == "table" then
    tier_set = {}
    for _, tier in ipairs(tiers) do tier_set[tonumber(tier)] = true end
  end
  local minimum = tonumber(options.module_tier_min)
  local maximum = tonumber(options.module_tier_max)
  if not tier_set and minimum == nil and maximum == nil then return end
  for _, name in ipairs(item_prototype_facts.module_items({
    module_tiers = tiers,
    module_tier_min = minimum,
    module_tier_max = maximum
  })) do want[name] = true end
end

local function add_place_result_outputs(want, entity_types)
  if type(entity_types) ~= "table" then return end
  for _, name in ipairs(item_prototype_facts.placeable_items_for_entity_types(entity_types)) do
    want[name] = true
  end
end

local function gather_by_items(items, patterns, options)
  local want = {}
  options = options or {}
  add_wanted_outputs(want, items)
  add_wanted_outputs(want, options.fluids)
  add_wanted_outputs(want, options.extra_outputs)
  add_pattern_outputs(want, patterns, lookup.each_item_prototype)
  add_pattern_outputs(want, options.fluid_patterns, lookup.each_fluid_prototype)
  add_module_outputs(want, options)
  add_place_result_outputs(want, options.place_result_entity_types)
  local candidate_categories, candidate_patterns = {}, {}
  local stream_match = options.match_stream and options.match_stream.match
  if options.match_mode == "by_category_or_match" and stream_match then
    for _, category in ipairs(stream_match.categories or {}) do table.insert(candidate_categories, category) end
    for _, pattern in ipairs(stream_match.name_patterns or {}) do table.insert(candidate_patterns, pattern) end
    for _, pattern in ipairs(stream_match.recipe_patterns or {}) do table.insert(candidate_patterns, pattern) end
  end
  for _, pattern in ipairs(options.recipe_patterns or {}) do table.insert(candidate_patterns, pattern) end

  local seen, list = {}, {}
  for _, rname in ipairs(recipe_facts.candidate_names(want, candidate_categories, candidate_patterns)) do
    local r = recipe_facts.view(rname)
    if not should_skip_recipe(rname, r, options) then
      local required_output = options.required_productive_outputs == nil
      if type(options.required_productive_outputs) == "table" then
        for _, wanted in ipairs(options.required_productive_outputs) do
          local identity = typed_identity(wanted)
          if identity then
            for _, actual in ipairs(r.productive_result_identities or {}) do
              if typed_identity(actual) == identity then required_output = true; break end
            end
          end
        end
      end
      local outs = {}
      for _, output_name in ipairs(r.productive_result_names or {}) do outs[output_name] = true end
      local match = false
      for it, _ in pairs(want) do
        if it == "rail" then
          if outs.rail then match = true; break end
        elseif outs[it] then
          match = true
          break
        end
      end
      if not match and options.match_stream and options.match_mode == "by_category_or_match" then
        match = R.matches_stream_recipe_filter(rname, r, options.match_stream)
      end
      if not match and options.recipe_patterns and name_matches(rname, options.recipe_patterns) then
        match = true
      end
      if match and required_output and not seen[rname] then
        seen[rname] = true
        table.insert(list, rname)
      end
    end
  end
  table.sort(list)
  return list
end

local function recipes_for_stream_uncached(spec, per_level_default)
  local automatic_policy = automatic_compiler_policy.current()
  if spec.groups then
    local buckets, assigned = {}, {}
    for _, g in ipairs(spec.groups) do
      local list = {}
      if not g.structural_fallback or automatic_policy.apply_changes then
        local required_outputs = g.required_productive_outputs
        if required_outputs == nil then required_outputs = spec.required_productive_outputs end
        list = gather_by_items(g.items, g.item_patterns, {
          fluids = g.fluids,
          required_productive_outputs = required_outputs,
          fluid_patterns = merge_lists(spec.fluid_patterns, g.fluid_patterns),
          extra_outputs = g.extra_outputs,
          recipe_patterns = merge_lists(spec.recipe_patterns, g.recipe_patterns),
          exclude_recipe_patterns = merge_lists(spec.exclude_recipe_patterns, g.exclude_recipe_patterns),
          exclude_ingredient_patterns = merge_lists(spec.exclude_ingredient_patterns, g.exclude_ingredient_patterns),
          include_hidden = spec.include_hidden or g.include_hidden,
          include_recycling = spec.include_recycling or g.include_recycling,
          allow_shared_input_output = spec.allow_shared_input_output or g.allow_shared_input_output,
          module_tiers = g.module_tiers,
          module_tier_min = g.module_tier_min,
          module_tier_max = g.module_tier_max,
          place_result_entity_types = g.place_result_entity_types,
          reject_explicit_productivity_denial = g.reject_explicit_productivity_denial,
          require_acyclic_process = g.require_acyclic_process or spec.require_acyclic_process,
          require_exact_route_certificate = g.require_exact_route_certificate or spec.require_exact_route_certificate,
          reviewed_forward_routes = g.reviewed_forward_routes or spec.reviewed_forward_routes,
          match_mode = g.mode or spec.mode,
          match_stream = g.match and g or spec
        })
      end
      local filtered = {}
      for _, recipe_name in ipairs(list) do
        -- Groups are ordered from broad/common to niche/high tier. If a later
        -- pattern also sees a recipe, keep the first tier assignment.
        if not assigned[recipe_name] then
          assigned[recipe_name] = true
          table.insert(filtered, recipe_name)
        end
      end
      if #filtered > 0 then
        table.insert(buckets, {
          change = g.change or per_level_default,
          recipes = filtered,
          structural_fallback = g.structural_fallback == true
        })
      end
    end
    return buckets
  end

  if spec.structural_fallback and not automatic_policy.apply_changes then
    return {}
  end
  local list = gather_by_items(spec.items, spec.item_patterns, {
    fluids = spec.fluids,
    required_productive_outputs = spec.required_productive_outputs,
    fluid_patterns = spec.fluid_patterns,
    extra_outputs = spec.extra_outputs,
    recipe_patterns = spec.recipe_patterns,
    exclude_recipe_patterns = spec.exclude_recipe_patterns,
    exclude_ingredient_patterns = spec.exclude_ingredient_patterns,
    include_hidden = spec.include_hidden,
    include_recycling = spec.include_recycling,
    allow_shared_input_output = spec.allow_shared_input_output,
    module_tiers = spec.module_tiers,
    module_tier_min = spec.module_tier_min,
    module_tier_max = spec.module_tier_max,
    place_result_entity_types = spec.place_result_entity_types,
    reject_explicit_productivity_denial = spec.reject_explicit_productivity_denial,
    require_acyclic_process = spec.require_acyclic_process,
    require_exact_route_certificate = spec.require_exact_route_certificate,
    reviewed_forward_routes = spec.reviewed_forward_routes,
    match_mode = spec.mode,
    match_stream = spec
  })
  return {{change = per_level_default, recipes = list}}
end

local function stream_match_identity(stream_key, spec, per_level_default)
  return fingerprint.of({
    schema = 1,
    stream_key = stream_key,
    descriptor = spec,
    per_level_default = per_level_default,
    recipe_facts = recipe_facts.fingerprint(),
    target_profile = target_profiles.current(),
    automatic_productivity_action = automatic_compiler_policy.current().action
  })
end

function R.buckets_view(stream_key, spec, per_level_default)
  if type(stream_key) ~= "string" or stream_key == "" then
    error("MIR stream matching cache requires a stable stream key.", 2)
  end
  local context = compiler_context.current()
  local cache = context:state_view("stream_match_index", function()
    return {schema = 1, by_identity = {}, computations_by_identity = {}}
  end)
  local identity = stream_match_identity(stream_key, spec, per_level_default)
  local cached = cache.by_identity[identity]
  if cached then
    telemetry.count("stream_match_cache_hits", 1)
    return cached
  end
  telemetry.count("stream_match_cache_misses", 1)
  cache.computations_by_identity[identity] = (cache.computations_by_identity[identity] or 0) + 1
  telemetry.observe_max("stream_match_max_computations_per_identity", cache.computations_by_identity[identity])
  local buckets = recipes_for_stream_uncached(spec, per_level_default)
  cache.by_identity[identity] = buckets
  return buckets
end

function R.recipes_for_stream(spec, per_level_default, stream_key)
  if stream_key then
    return deepcopy(R.buckets_view(stream_key, spec, per_level_default))
  end
  return recipes_for_stream_uncached(spec, per_level_default)
end

return R
