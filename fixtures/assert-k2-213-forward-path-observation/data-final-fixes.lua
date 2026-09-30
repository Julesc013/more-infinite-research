-- Package-excluded observation aid. It intentionally reads only finalized
-- compiler facts so exact certificates can be authored from one exact K2 load.
-- Version 0.1.1 keeps all 0.1.0 markers and adds per-witness owner/unlock rows.
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local relationships = require("__more-infinite-research__/prototypes/mir/index/relationships")
local data_raw = require("__more-infinite-research__/prototypes/mir/platform/factorio/data_raw")
local fingerprint = require("__more-infinite-research__/prototypes/mir/core/fingerprint")

local subjects = {
  {stream = "research_material_rare_metals", recipe = "kr-rare-metals"},
  {stream = "research_material_rare_metals", recipe = "kr-rare-metals-from-enriched-rare-metals"},
  {stream = "research_material_silicon", recipe = "kr-silicon"},
  {stream = "research_material_glass", recipe = "kr-glass"}
}

local entry_fields = {
  "type", "name", "amount", "amount_min", "amount_max", "probability",
  "independent_probability", "catalyst_amount", "temperature", "minimum_temperature",
  "maximum_temperature", "fluidbox_index", "ignored_by_stats", "ignored_by_productivity",
  "always_fresh", "quality", "quality_change", "percent_spoiled", "extra_count_fraction"
}

local function scalar(value)
  if value == nil then return "-" end
  if type(value) == "boolean" then return value and "true" or "false" end
  return tostring(value)
end

local function entry_line(entry)
  local fields = {}
  for _, field in ipairs(entry_fields) do
    if entry[field] ~= nil then fields[#fields + 1] = field .. "=" .. scalar(entry[field]) end
  end
  return table.concat(fields, ";")
end

local function entries_line(entries)
  local lines = {}
  for _, entry in ipairs(entries or {}) do lines[#lines + 1] = entry_line(entry) end
  table.sort(lines)
  return #lines == 0 and "-" or table.concat(lines, "|")
end

local function names_line(values)
  local names = {}
  for _, value in ipairs(values or {}) do names[#names + 1] = tostring(value) end
  table.sort(names)
  return #names == 0 and "-" or table.concat(names, ",")
end

local function active_mods_line()
  local names = {}
  for name, version in pairs((script and script.active_mods) or mods or {}) do
    names[#names + 1] = name .. "=" .. tostring(version)
  end
  table.sort(names)
  return table.concat(names, ",")
end

local function effect_owners(recipe_name)
  local owners = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
        owners[#owners + 1] = technology_name .. ":" .. scalar(effect.change)
      end
    end
  end
  table.sort(owners)
  return #owners == 0 and "-" or table.concat(owners, ",")
end

-- This package-excluded observer mirrors the product's proposed typed
-- return-cone certificate. It records only the candidate's downstream
-- consumers and direct finished-output producers, not an all-recipe lock, so
-- the resulting evidence can distinguish a disconnected QoL addition from a
-- changed return mechanism. The product consumes the same normalized facts
-- and MIR32 fingerprint implementation.
local function typed_identity(entry)
  if type(entry) ~= "table" or type(entry.type) ~= "string" or entry.type == ""
    or type(entry.name) ~= "string" or entry.name == "" then return nil end
  return entry.type .. "\30" .. entry.name
end

local function sorted_keys(values)
  local out = {}
  for key in pairs(values or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function route_identities(recipe, field)
  local out = {}
  for _, variant in ipairs((recipe and recipe.variants) or {}) do
    for _, entry in ipairs(variant[field] or {}) do
      local identity = typed_identity(entry)
      if identity then out[identity] = true end
    end
  end
  return out
end

local function observed_graph()
  local graph = {edges = {}, complete = true, edge_count = 0}
  recipe_facts.for_each(function(_, fact)
    for _, variant in ipairs(fact.variants or {}) do
      for _, input in ipairs(variant.ingredients or {}) do
        local input_identity = typed_identity(input)
        if input_identity then
          graph.edges[input_identity] = graph.edges[input_identity] or {}
          for _, output in ipairs(variant.results or {}) do
            local output_identity = typed_identity(output)
            if output_identity and not graph.edges[input_identity][output_identity] then
              graph.edge_count = graph.edge_count + 1
              if graph.edge_count > 100000 then graph.complete = false; return end
              graph.edges[input_identity][output_identity] = true
            end
          end
        end
      end
    end
  end)
  return graph
end


-- The production acyclicity guard intentionally follows the name-only
-- material graph. This observer builds the same bounded graph, preserving
-- every final normalized recipe fact that establishes each traversed edge so
-- an eventual certificate cannot replace an observed return path with a
-- merely plausible one.
local reviewed_entry_fields = {
  "type", "name", "amount", "amount_min", "amount_max", "probability",
  "independent_probability", "declared_probability", "declared_independent_probability",
  "shared_probability", "extra_count_fraction", "catalyst_amount",
  "ignored_by_productivity", "ignored_by_stats", "temperature",
  "minimum_temperature", "maximum_temperature", "fluidbox_index",
  "percent_spoiled", "always_fresh", "reset_freshness_on_craft",
  "quality_min", "quality_max", "quality_change", "affected_by_quality"
}

local function reviewed_entry_line(entry)
  local fields = {}
  for _, field in ipairs(reviewed_entry_fields) do
    fields[#fields + 1] = field .. "=" .. scalar(entry and entry[field])
  end
  return "{" .. table.concat(fields, ",") .. "}"
end

local function reviewed_entries_line(entries)
  local values = {}
  for _, entry in ipairs(entries or {}) do values[#values + 1] = reviewed_entry_line(entry) end
  return #values == 0 and "-" or table.concat(values, "|")
end

local function reviewed_variants_line(variants)
  local values = {}
  for index, variant in ipairs(variants or {}) do
    values[#values + 1] = "v" .. tostring(index)
      .. "{hidden=" .. scalar(variant.hidden)
      .. ";enabled=" .. scalar(variant.enabled)
      .. ";ingredients=" .. reviewed_entries_line(variant.ingredients)
      .. ";results=" .. reviewed_entries_line(variant.results) .. "}"
  end
  return #values == 0 and "-" or table.concat(values, "|")
end

local function name_edge_key(from_name, to_name)
  return from_name .. "\31" .. to_name
end

local function observed_name_path_graph()
  local graph = {edges = {}, edge_recipes = {}, complete = true, edge_count = 0}
  recipe_facts.for_each(function(_, fact)
    if type(fact) ~= "table" or type(fact.name) ~= "string" or fact.name == "" then
      graph.complete = false
      return
    end
    for _, variant in ipairs(fact.variants or {}) do
      for _, input in ipairs(variant.ingredients or {}) do
        if type(input.name) ~= "string" or input.name == "" then
          graph.complete = false
          return
        end
        graph.edges[input.name] = graph.edges[input.name] or {}
        for _, output in ipairs(variant.results or {}) do
          if type(output.name) ~= "string" or output.name == "" then
            graph.complete = false
            return
          end
          if not graph.edges[input.name][output.name] then
            graph.edge_count = graph.edge_count + 1
            if graph.edge_count > 100000 then graph.complete = false; return end
            graph.edges[input.name][output.name] = true
          end
          local key = name_edge_key(input.name, output.name)
          graph.edge_recipes[key] = graph.edge_recipes[key] or {}
          graph.edge_recipes[key][fact.name] = true
        end
      end
    end
  end)
  return graph
end

local function observed_return_path(recipe, return_input, graph)
  if type(recipe) ~= "table" or type(return_input) ~= "string" or return_input == "" or not graph.complete then return nil end
  local starts, visited, queue = {}, {}, {}
  for _, variant in ipairs(recipe.variants or {}) do
    for _, output in ipairs(variant.results or {}) do
      if type(output.name) == "string" and output.name ~= "" then starts[output.name] = true end
    end
  end
  for _, output_name in ipairs(sorted_keys(starts)) do
    queue[#queue + 1] = output_name
    visited[output_name] = true
  end
  local head, previous = 1, {}
  while head <= #queue do
    if head > 30000 then return nil end
    local name = queue[head]
    head = head + 1
    if name == return_input then
      local nodes, edges, cursor = {name}, {}, name
      while previous[cursor] do
        local step = previous[cursor]
        table.insert(nodes, 1, step.from)
        table.insert(edges, 1, {from = step.from, to = cursor, recipes = step.recipes})
        cursor = step.from
      end
      return {nodes = nodes, edges = edges}
    end
    for _, next_name in ipairs(sorted_keys(graph.edges[name] or {})) do
      if not visited[next_name] then
        visited[next_name] = true
        previous[next_name] = {from = name, recipes = sorted_keys(graph.edge_recipes[name_edge_key(name, next_name)] or {})}
        queue[#queue + 1] = next_name
      end
    end
  end
  return nil
end

local function observe_return_path(route_name, fact, generic_reason, graph)
  local return_input = type(generic_reason) == "string" and string.match(generic_reason, "^potential%-return%-path:(.+)$") or nil
  if not return_input then error("MIR K2 missing potential-return-path " .. route_name) end
  local path = observed_return_path(fact, return_input, graph)
  if not path or #path.edges == 0 then error("MIR K2 path witness missing " .. route_name .. ":" .. return_input) end
  log("[MIR4_K2_213_FORWARD_PATH]"
    .. " route=" .. route_name
    .. ";return_input=" .. return_input
    .. ";edges=" .. tostring(#path.edges)
    .. ";nodes=" .. table.concat(path.nodes, ">"))
  for edge_index, edge in ipairs(path.edges) do
    if #edge.recipes == 0 then error("MIR K2 path edge lacks witness " .. route_name) end
    for _, witness_name in ipairs(edge.recipes) do
      local witness = recipe_facts.view(witness_name)
      if type(witness) ~= "table" then error("MIR K2 missing path witness fact " .. witness_name) end
      log("[MIR4_K2_213_FORWARD_WITNESS]"
        .. " route=" .. route_name
        .. ";edge=" .. tostring(edge_index)
        .. ";from=" .. edge.from
        .. ";to=" .. edge.to
        .. ";recipe=" .. witness.name
        .. ";source=" .. scalar(witness.source_class)
        .. ";hidden=" .. scalar(witness.hidden)
        .. ";enabled_without_research=" .. scalar(witness.enabled_without_research)
        .. ";variants=" .. reviewed_variants_line(witness.variants))
    end
  end
  return path
end
local function observed_route_fingerprints(recipe, graph)
  local outputs, inputs = route_identities(recipe, "results"), route_identities(recipe, "ingredients")
  if not graph.complete or next(outputs) == nil or next(inputs) == nil then return nil end
  local queue, reached = {}, {}
  for _, identity in ipairs(sorted_keys(outputs)) do queue[#queue + 1], reached[identity] = identity, true end
  local head = 1
  while head <= #queue do
    if head > 30000 then return nil end
    local identity = queue[head]
    head = head + 1
    for next_identity in pairs(graph.edges[identity] or {}) do
      if not reached[next_identity] then reached[next_identity] = true; queue[#queue + 1] = next_identity end
    end
  end
  local index = recipe_facts.index_view()
  local selected, direct_output_producers = {}, {}
  for recipe_name, fact in pairs(index.facts or {}) do
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
          selected[recipe_name], direct_output_producers[recipe_name] = true, true
          break
        end
      end
    end
  end
  local facts = {}
  for _, recipe_name in ipairs(sorted_keys(selected)) do facts[#facts + 1] = {name = recipe_name, fact = index.facts[recipe_name]} end
  local boundary = {
    schema = 1,
    route = recipe.name,
    input_identities = sorted_keys(inputs),
    output_identities = sorted_keys(outputs),
    reachable_identities = sorted_keys(reached),
    direct_output_producers = sorted_keys(direct_output_producers),
    facts = facts
  }
  local relation_index = relationships.view("input")
  local owners, unlocks = {}, {}
  for _, owner in ipairs((relation_index.technologies_by_recipe_effect or {})[recipe.name] or {}) do
    if not string.match(owner, "^recipe%-prod%-") then owners[#owners + 1] = owner end
  end
  table.sort(owners)
  for _, unlock_name in ipairs((relation_index.unlocks_by_recipe or {})[recipe.name] or {}) do
    local technology = data_raw.technology(unlock_name)
    local science, prerequisites = {}, {}
    for _, entry in ipairs((technology and technology.unit and technology.unit.ingredients) or {}) do
      science[#science + 1] = {name = entry.name or entry[1], amount = tonumber(entry.amount or entry[2])}
    end
    table.sort(science, function(left, right) return left.name < right.name end)
    for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do prerequisites[#prerequisites + 1] = prerequisite end
    table.sort(prerequisites)
    unlocks[#unlocks + 1] = {name = unlock_name, science_ingredients = science, prerequisites = prerequisites}
  end
  table.sort(unlocks, function(left, right) return left.name < right.name end)
  return {
    return_graph_fingerprint = fingerprint.of(boundary),
    bindings_fingerprint = fingerprint.of({schema = 1, recipe = recipe.name, productivity_owner_technologies = owners, unlock_technologies = unlocks}),
    reachable_identity_count = #boundary.reachable_identities,
    relevant_recipe_count = #boundary.facts,
    direct_output_producer_count = #boundary.direct_output_producers,
    direct_output_producers = boundary.direct_output_producers,
    productivity_owner_technologies = owners,
    unlock_technologies = unlocks
  }
end


-- Private current-tuple observation only. This mirrors the product's typed
-- return-cone normalisation and fingerprint implementation without writing a
-- prototype or asserting the old K2 2.1.2 certificate still applies.
local function science_entries_line(entries)
  local values = {}
  for _, entry in ipairs(entries or {}) do
    values[#values + 1] = tostring(entry.name) .. ":" .. tostring(entry.amount)
  end
  table.sort(values)
  return #values == 0 and "-" or table.concat(values, ",")
end

local function labs_for_science(entries)
  local required, labs = {}, {}
  for _, entry in ipairs(entries or {}) do required[entry.name] = true end
  for lab_name, lab in pairs(data.raw.lab or {}) do
    local supplied, accepts = {}, true
    for _, input in ipairs(lab.inputs or {}) do supplied[input] = true end
    for science_name in pairs(required) do
      if not supplied[science_name] then accepts = false; break end
    end
    if accepts then labs[#labs + 1] = lab_name end
  end
  table.sort(labs)
  return #labs == 0 and "-" or table.concat(labs, ",")
end

local function unlocks_line(unlocks)
  local values = {}
  for _, unlock in ipairs(unlocks or {}) do
    values[#values + 1] = unlock.name
      .. "[science=" .. science_entries_line(unlock.science_ingredients)
      .. ";prerequisites=" .. names_line(unlock.prerequisites)
      .. ";labs=" .. labs_for_science(unlock.science_ingredients) .. "]"
  end
  table.sort(values)
  return #values == 0 and "-" or table.concat(values, "|")
end

local function observed_recipe_bindings(recipe_name)
  local index = relationships.view("input")
  if type(index) ~= "table" then error("MIR K2 missing relationship index for " .. recipe_name) end

  local owners = {}
  for _, name in ipairs((index.technologies_by_recipe_effect or {})[recipe_name] or {}) do
    owners[#owners + 1] = name
  end
  table.sort(owners)

  local unlocks = {}
  for _, name in ipairs((index.unlocks_by_recipe or {})[recipe_name] or {}) do
    local technology = data_raw.technology(name)
    if type(technology) ~= "table" then error("MIR K2 missing path unlock technology " .. name) end
    local science, prerequisites = {}, {}
    for _, entry in ipairs((technology.unit and technology.unit.ingredients) or {}) do
      science[#science + 1] = {name = entry.name or entry[1], amount = tonumber(entry.amount or entry[2])}
    end
    table.sort(science, function(left, right)
      if left.name == right.name then return left.amount < right.amount end
      return left.name < right.name
    end)
    for _, prerequisite in ipairs(technology.prerequisites or {}) do prerequisites[#prerequisites + 1] = prerequisite end
    table.sort(prerequisites)
    unlocks[#unlocks + 1] = {
      name = name,
      science_ingredients = science,
      prerequisites = prerequisites
    }
  end
  table.sort(unlocks, function(left, right) return left.name < right.name end)
  return owners, unlocks
end

local K2_SILICON_RETURN_NODES = {
  "kr-silicon", "kr-electronic-components", "personal-laser-defense-equipment", "laser-turret", "kr-quartz"
}
local K2_SILICON_RETURN_WITNESSES = {
  "kr-electronic-components",
  "kr-electronic-components-with-lithium",
  "personal-laser-defense-equipment",
  "personal-laser-defense-equipment-recycling",
  "laser-turret-recycling"
}

local function assert_silicon_return_path(path)
  if #path.nodes ~= #K2_SILICON_RETURN_NODES then error("MIR K2 silicon return path node count changed") end
  for index, expected in ipairs(K2_SILICON_RETURN_NODES) do
    if path.nodes[index] ~= expected then error("MIR K2 silicon return path changed at node " .. tostring(index)) end
  end
  local observed, count = {}, 0
  for _, edge in ipairs(path.edges) do
    for _, recipe_name in ipairs(edge.recipes) do
      if observed[recipe_name] then error("MIR K2 duplicate silicon path witness " .. recipe_name) end
      observed[recipe_name] = true
      count = count + 1
    end
  end
  if count ~= #K2_SILICON_RETURN_WITNESSES then error("MIR K2 silicon witness count changed") end
  for _, expected in ipairs(K2_SILICON_RETURN_WITNESSES) do
    if not observed[expected] then error("MIR K2 silicon path witness missing " .. expected) end
  end
end

local function log_silicon_return_path_bindings(path)
  assert_silicon_return_path(path)
  for edge_index, edge in ipairs(path.edges) do
    for _, recipe_name in ipairs(edge.recipes) do
      local owners, unlocks = observed_recipe_bindings(recipe_name)
      log("[MIR4_K2_213_FORWARD_BINDING]"
        .. " route=kr-silicon"
        .. ";edge=" .. tostring(edge_index)
        .. ";from=" .. edge.from
        .. ";to=" .. edge.to
        .. ";recipe=" .. recipe_name
        .. ";owners=" .. names_line(owners)
        .. ";owner_effects=" .. effect_owners(recipe_name)
        .. ";unlocks=" .. unlocks_line(unlocks))
    end
  end
end

log("[MIR4_K2_213_FORWARD_PROFILE] active_mods=" .. active_mods_line())
compiler_context.with_active(compiler_context.new(), function()
  local graph = observed_graph()
  local path_graph = observed_name_path_graph()
  if not graph.complete or not path_graph.complete then error("MIR K2 2.1.3 forward-route graph exceeded edge budget") end
  for _, subject in ipairs(subjects) do
    local fact = recipe_facts.view(subject.recipe)
    local risk = recipe_risk_facts.view(subject.recipe)
    if not fact or not risk then error("MIR K2 missing final route facts " .. subject.recipe) end
    local variant = fact.variants and fact.variants[1] or {}
    local generic_admitted, generic_reason = recipe_matching.material_route_is_acyclic(fact)
    local values = observed_route_fingerprints(fact, graph)
    if not values then error("MIR K2 missing complete return-boundary " .. subject.recipe) end
    local provider_values = {}
    for _, provider in ipairs(values.direct_output_producers or {}) do
      provider_values[#provider_values + 1] = provider .. ":owners=" .. effect_owners(provider)
    end
    table.sort(provider_values)
    log("[MIR4_K2_213_FORWARD_ROUTE]"
      .. " stream=" .. subject.stream
      .. " recipe=" .. subject.recipe
      .. " admitted=" .. scalar(generic_admitted)
      .. " reason=" .. scalar(generic_reason)
      .. " source=" .. scalar(fact.source_class)
      .. " hidden=" .. scalar(fact.hidden)
      .. " declared_productivity=" .. scalar(fact.declared_allow_productivity)
      .. " effective_productivity=" .. scalar(fact.effective_allow_productivity)
      .. " maximum_productivity=" .. scalar(fact.effective_maximum_productivity)
      .. " variants=" .. scalar(#(fact.variants or {}))
      .. " ingredients=" .. entries_line(variant.ingredients)
      .. " results=" .. entries_line(variant.results)
      .. " risk=" .. scalar(risk.risk_fingerprint)
      .. " hard=" .. names_line(risk.hard_flags)
      .. " review=" .. names_line(risk.review_flags)
      .. " shared=" .. names_line(risk.shared_input_output)
      .. " owners=" .. effect_owners(subject.recipe))
    log("[MIR4_K2_213_FORWARD_GRAPH]"
      .. " recipe=" .. subject.recipe
      .. " graph=" .. values.return_graph_fingerprint
      .. " bindings=" .. values.bindings_fingerprint
      .. " identities=" .. tostring(values.reachable_identity_count)
      .. " recipes=" .. tostring(values.relevant_recipe_count)
      .. " providers=" .. tostring(values.direct_output_producer_count)
      .. " provider_closure=" .. (#provider_values == 0 and "-" or table.concat(provider_values, ","))
      .. " owner_closure=" .. names_line(values.productivity_owner_technologies)
      .. " unlock_closure=" .. unlocks_line(values.unlock_technologies))
    local path = observe_return_path(subject.recipe, fact, generic_reason, path_graph)
    if subject.recipe == "kr-silicon" then log_silicon_return_path_bindings(path) end
  end
end)
log("[MIR4_K2_213_FORWARD_COMPLETE] routes=4;mutated=false")
