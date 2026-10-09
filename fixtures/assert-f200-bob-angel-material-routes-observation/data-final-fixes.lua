-- Package-excluded observation aid. It intentionally reads only finalized
-- compiler facts so exact certificates can be authored from one F200 load.
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local relationships = require("__more-infinite-research__/prototypes/mir/index/relationships")
local data_raw = require("__more-infinite-research__/prototypes/mir/platform/factorio/data_raw")
local fingerprint = require("__more-infinite-research__/prototypes/mir/core/fingerprint")

local subjects = {
  {stream = "research_material_aluminium", item = "bob-aluminium-plate", recipes = {"bob-aluminium-plate", "angels-plate-aluminium", "angels-plate-aluminium-2"}},
  {stream = "research_material_gold", item = "bob-gold-plate", recipes = {"bob-gold-plate"}},
  {stream = "research_material_lead", item = "bob-lead-plate", recipes = {"bob-lead-plate", "bob-lead-plate-2"}},
  {stream = "research_material_nickel", item = "bob-nickel-plate", recipes = {"bob-nickel-plate", "angels-plate-nickel", "angels-plate-nickel-2"}},
  {stream = "research_material_platinum", item = "angels-wire-platinum", recipes = {"bob-platinum-plate", "angels-wire-platinum", "angels-wire-platinum-2", "angels-wire-coil-platinum-2"}},
  {stream = "research_material_silver", item = "bob-silver-plate", recipes = {"bob-silver-plate", "angels-plate-silver", "angels-plate-silver-2"}},
  {stream = "research_material_tin", item = "bob-tin-plate", recipes = {"bob-tin-plate"}},
  {stream = "research_material_titanium", item = "bob-titanium-plate", recipes = {"bob-titanium-plate"}},
  {stream = "research_material_copper_tungsten", item = "bob-copper-tungsten-alloy", recipes = {"bob-copper-tungsten-alloy"}},
  {stream = "research_material_zinc", item = "bob-zinc-plate", recipes = {"bob-zinc-plate"}},
  {stream = "research_material_bronze", item = "bob-bronze-alloy", recipes = {"bob-bronze-alloy"}},
  {stream = "research_material_brass", item = "bob-brass-alloy", recipes = {"bob-brass-alloy"}},
  {stream = "research_material_gunmetal", item = "bob-gunmetal-alloy", recipes = {"bob-gunmetal-alloy"}},
  {stream = "research_material_invar", item = "bob-invar-alloy", recipes = {"bob-invar-alloy"}},
  {stream = "research_material_cobalt_steel", item = "bob-cobalt-steel-alloy", recipes = {"bob-cobalt-steel-alloy"}},
  {stream = "research_material_nitinol", item = "bob-nitinol-alloy", recipes = {"bob-nitinol-alloy"}}
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
    direct_output_producer_count = #boundary.direct_output_producers
  }
end

log("[mir-f200-material-routes] PROFILE active_mods=" .. active_mods_line())
compiler_context.with_active(compiler_context.new(), function()
  for _, recipe_name in ipairs({"bob-silver-from-lead", "bob-silver-nitrate"}) do
    local fact = recipe_facts.view(recipe_name)
    local variant = fact and fact.variants and fact.variants[1] or {}
    log("[mir-f200-material-routes] RETURN_WITNESS recipe=" .. recipe_name
      .. " hidden=" .. scalar(fact and fact.hidden)
      .. " enabled_without_research=" .. scalar(fact and fact.enabled_without_research)
      .. " source=" .. scalar(fact and fact.source_class)
      .. " variant_hidden=" .. scalar(variant.hidden)
      .. " variant_enabled=" .. scalar(variant.enabled)
      .. " ingredients=" .. entries_line(variant.ingredients)
      .. " results=" .. entries_line(variant.results))
  end
  for _, subject in ipairs(subjects) do
    local declared = {}
    for _, recipe_name in ipairs(subject.recipes) do
      declared[recipe_name] = true
      local fact = recipe_facts.view(recipe_name)
      local risk = recipe_risk_facts.view(recipe_name)
      if not fact then
        log("[mir-f200-material-routes] ROUTE stream=" .. subject.stream .. " recipe=" .. recipe_name .. " state=absent")
      else
        local admitted, reason = recipe_matching.material_route_is_acyclic(fact)
        local variant = fact.variants and fact.variants[1] or {}
        log("[mir-f200-material-routes] ROUTE"
          .. " stream=" .. subject.stream
          .. " recipe=" .. recipe_name
          .. " admitted=" .. scalar(admitted)
          .. " reason=" .. scalar(reason)
          .. " source=" .. scalar(fact.source_class)
          .. " hidden=" .. scalar(fact.hidden)
          .. " declared_productivity=" .. scalar(fact.declared_allow_productivity)
          .. " effective_productivity=" .. scalar(fact.effective_allow_productivity)
          .. " maximum_productivity=" .. scalar(fact.effective_maximum_productivity)
          .. " variants=" .. scalar(#(fact.variants or {}))
          .. " ingredients=" .. entries_line(variant.ingredients)
          .. " results=" .. entries_line(variant.results)
          .. " risk=" .. scalar(risk and risk.risk_fingerprint)
          .. " hard=" .. names_line(risk and risk.hard_flags)
          .. " review=" .. names_line(risk and risk.review_flags)
          .. " shared=" .. names_line(risk and risk.shared_input_output)
          .. " owners=" .. effect_owners(recipe_name))
      end
    end
    -- The stable declaration can intentionally name only one ecosystem's
    -- route. List every finalized producer of its output as discovery data;
    -- the report does not promote those routes or change their eligibility.
    for _, recipe_name in ipairs(recipe_facts.recipes_by_output_identity_view("item", subject.item)) do
      if not declared[recipe_name] then
        local fact = recipe_facts.view(recipe_name)
        local risk = recipe_risk_facts.view(recipe_name)
        local admitted, reason = recipe_matching.material_route_is_acyclic(fact)
        local variant = fact and fact.variants and fact.variants[1] or {}
        log("[mir-f200-material-routes] PRODUCER"
          .. " stream=" .. subject.stream
          .. " item=" .. subject.item
          .. " recipe=" .. recipe_name
          .. " admitted=" .. scalar(admitted)
          .. " reason=" .. scalar(reason)
          .. " source=" .. scalar(fact and fact.source_class)
          .. " hidden=" .. scalar(fact and fact.hidden)
          .. " declared_productivity=" .. scalar(fact and fact.declared_allow_productivity)
          .. " effective_productivity=" .. scalar(fact and fact.effective_allow_productivity)
          .. " maximum_productivity=" .. scalar(fact and fact.effective_maximum_productivity)
          .. " variants=" .. scalar(fact and #(fact.variants or {}))
          .. " ingredients=" .. entries_line(variant.ingredients)
          .. " results=" .. entries_line(variant.results)
          .. " risk=" .. scalar(risk and risk.risk_fingerprint)
          .. " hard=" .. names_line(risk and risk.hard_flags)
          .. " review=" .. names_line(risk and risk.review_flags)
          .. " shared=" .. names_line(risk and risk.shared_input_output)
          .. " owners=" .. effect_owners(recipe_name))
      end
    end
  end
end)

-- The current exact F200 Bob/Angel profile has sixteen ordinary finished
-- materials. Assert the emitted recipe effects, rather than inferring delivery
-- from a declaration or from a recipe merely existing in data.raw.
local expected_effects = {
  aluminium = {"angels-plate-aluminium", "angels-plate-aluminium-2"},
  gold = {"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"},
  lead = {"angels-plate-lead", "angels-plate-lead-2"},
  nickel = {"angels-plate-nickel", "angels-plate-nickel-2"},
  platinum = {"angels-wire-platinum-2"},
  tin = {"angels-plate-tin", "angels-plate-tin-2"},
  titanium = {"angels-plate-titanium", "angels-plate-titanium-2"},
  copper_tungsten = {"bob-copper-tungsten-alloy"},
  zinc = {"angels-plate-zinc", "angels-plate-zinc-2"},
  bronze = {"angels-plate-bronze"},
  brass = {"angels-plate-brass"},
  gunmetal = {"angels-plate-gunmetal"},
  invar = {"angels-plate-invar"},
  cobalt_steel = {"angels-plate-cobalt-steel"},
  nitinol = {"angels-plate-nitinol"},
  silver = {"angels-plate-silver", "angels-plate-silver-2", "angels-wire-silver-2"}
}

-- Record one exact typed boundary per emitted final recipe. These values are
-- observation data only; the enclosing probe is explicitly not a release or
-- broad-mod-list qualification.
local observed_route_names, observed_route_seen = {}, {}
for _, recipes in pairs(expected_effects) do
  for _, recipe_name in ipairs(recipes) do
    if not observed_route_seen[recipe_name] then
      observed_route_seen[recipe_name] = true
      observed_route_names[#observed_route_names + 1] = recipe_name
    end
  end
end
table.sort(observed_route_names)
compiler_context.with_active(compiler_context.new(), function()
  local graph = observed_graph()
  if not graph.complete then error("MIR F200 return-graph observation exceeded edge budget") end
  for _, recipe_name in ipairs(observed_route_names) do
    local values = observed_route_fingerprints(recipe_facts.view(recipe_name), graph)
    if not values then error("MIR F200 missing return-graph observation " .. recipe_name) end
    log("[mir-f200-material-routes] RETURN_GRAPH recipe=" .. recipe_name
      .. " graph=" .. values.return_graph_fingerprint
      .. " bindings=" .. values.bindings_fingerprint
      .. " identities=" .. tostring(values.reachable_identity_count)
      .. " recipes=" .. tostring(values.relevant_recipe_count)
      .. " producers=" .. tostring(values.direct_output_producer_count))
  end
end)

for key, expected in pairs(expected_effects) do
  local name = "recipe-prod-research_material_" .. key .. "-1"
  local technology = data.raw.technology[name]
  if not technology then error("MIR F200 material missing technology " .. name) end
  local actual = {}
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" then
      actual[#actual + 1] = effect.recipe .. ":" .. tostring(effect.change)
    end
  end
  for index, recipe_name in ipairs(expected) do expected[index] = recipe_name .. ":0.02" end
  table.sort(actual)
  table.sort(expected)
  if table.concat(actual, ",") ~= table.concat(expected, ",") then
    error("MIR F200 material effects differ for " .. name .. " expected="
      .. table.concat(expected, ",") .. " actual=" .. table.concat(actual, ","))
  end
end

-- The two wire finals add no new science stage: they use the same final
-- unlock already represented by their plate routes. They consume a distinct
-- coil, rather than a MIR-productive plate, while the direct and coil routes
-- remain explicitly productivity-disabled and ownerless.
local wire_final_stages = {
  {
    stream = "research_material_gold", recipe = "angels-wire-gold-2",
    certificate = "F200-BA-gold-wire-final-v1", input = "angels-wire-coil-gold",
    science = "automation-science-pack:1,chemical-science-pack:1,logistic-science-pack:1,production-science-pack:1",
    prerequisites = "angels-gold-casting-2,angels-gold-smelting-1,automation-science-pack,chemical-science-pack,logistic-science-pack,production-science-pack"
  },
  {
    stream = "research_material_silver", recipe = "angels-wire-silver-2",
    certificate = "F200-BA-silver-wire-final-v1", input = "angels-wire-coil-silver",
    science = "automation-science-pack:1,chemical-science-pack:1,logistic-science-pack:1",
    prerequisites = "angels-silver-casting-2,angels-silver-smelting-1,automation-science-pack,chemical-science-pack,logistic-science-pack"
  }
}

local function technology_science_line(technology)
  local values = {}
  for _, entry in ipairs((technology and technology.unit and technology.unit.ingredients) or {}) do
    values[#values + 1] = tostring(entry.name or entry[1]) .. ":" .. tostring(entry.amount or entry[2])
  end
  return names_line(values)
end

local function technology_prerequisites_line(technology)
  return names_line((technology and technology.prerequisites) or {})
end

local nonproductive_wire_routes = {
  "angels-wire-gold", "angels-wire-coil-gold", "angels-wire-coil-gold-2",
  "angels-wire-platinum", "angels-wire-coil-platinum", "angels-wire-coil-platinum-2",
  "angels-wire-silver", "angels-wire-coil-silver", "angels-wire-coil-silver-2"
}

compiler_context.with_active(compiler_context.new(), function()
  local productivity_streams = require("__more-infinite-research__/prototypes/streams/productivity")
  for _, expected in ipairs(wire_final_stages) do
    local route = recipe_facts.view(expected.recipe)
    local generic_admission, generic_reason = recipe_matching.material_route_is_acyclic(route)
    if not generic_admission or generic_reason ~= "no-recipe-return-path" then
      error("MIR F200 wire final graph guard differs recipe=" .. expected.recipe .. " reason=" .. tostring(generic_reason))
    end
    local stream = productivity_streams[expected.stream]
    local certificate = stream and stream.reviewed_forward_routes and stream.reviewed_forward_routes[expected.recipe]
    if not certificate or certificate.id ~= expected.certificate or not certificate.require_exact_route_certificate
      or certificate.relevant_input_contract ~= nil then
      error("MIR F200 wire final certificate differs recipe=" .. expected.recipe)
    end
    local technology = data.raw.technology["recipe-prod-" .. expected.stream .. "-1"]
    if technology_science_line(technology) ~= expected.science
      or technology_prerequisites_line(technology) ~= expected.prerequisites then
      error("MIR F200 wire final changed material research stage stream=" .. expected.stream)
    end
    local ingredient = route and route.variants and route.variants[1]
      and route.variants[1].ingredients and route.variants[1].ingredients[1]
    if not ingredient or ingredient.type ~= "item" or ingredient.name ~= expected.input
      or effect_owners(expected.input) ~= "-" then
      error("MIR F200 wire final plate-to-wire ownership boundary differs recipe=" .. expected.recipe)
    end
    if effect_owners(expected.recipe) ~= "recipe-prod-" .. expected.stream .. "-1:0.02" then
      error("MIR F200 wire final ownership differs recipe=" .. expected.recipe)
    end
    log("[mir-f200-material-routes] WIRE_FINAL recipe=" .. expected.recipe
      .. " certificate=" .. expected.certificate
      .. " generic=" .. tostring(generic_reason)
      .. " stage=unchanged"
      .. " owner=present")
  end
  for _, recipe_name in ipairs(nonproductive_wire_routes) do
    local route = recipe_facts.view(recipe_name)
    local generic_admission, generic_reason = recipe_matching.material_route_is_acyclic(route)
    if generic_admission or generic_reason ~= "productivity-not-allowed" or effect_owners(recipe_name) ~= "-" then
      error("MIR F200 nonproductive wire route changed recipe=" .. recipe_name .. " reason=" .. tostring(generic_reason))
    end
  end
end)

-- The Platinum exception applies only in the final F200 Angel shape where Bob's
-- Platinum plate is absent. It must retain the graph guard and have exactly one
-- MIR owner; Bob plate, direct wire, Angel plate, and either coil route must
-- never receive an effect.
compiler_context.with_active(compiler_context.new(), function()
  local platinum_route = recipe_facts.view("angels-wire-platinum-2")
  local admitted, reason = recipe_matching.material_route_is_acyclic(platinum_route)
  if not admitted then
    error("MIR F200 Platinum wire route failed the material graph guard reason=" .. tostring(reason))
  end
  local platinum_owner = "recipe-prod-research_material_platinum-1:0.02"
  if effect_owners("angels-wire-platinum-2") ~= platinum_owner then
    error("MIR F200 Platinum wire ownership differs actual=" .. effect_owners("angels-wire-platinum-2"))
  end
  for _, recipe_name in ipairs({"bob-platinum-plate", "angels-wire-platinum", "angels-wire-coil-platinum", "angels-wire-coil-platinum-2", "angels-plate-platinum", "angels-plate-platinum-2"}) do
    if effect_owners(recipe_name) ~= "-" then
      error("MIR F200 Platinum excluded route received an effect recipe=" .. recipe_name
        .. " owners=" .. effect_owners(recipe_name))
    end
  end
  log("[mir-f200-material-routes] PLATINUM recipe=angels-wire-platinum-2"
    .. " admitted=" .. tostring(admitted)
    .. " reason=" .. tostring(reason)
    .. " owner=" .. platinum_owner)
end)

-- The product logs the final reviewed-forward decision while it compiles.
-- Its selection helper has relative module imports and is intentionally not a
-- cross-mod fixture API. Bind the exact certificate ID, its still-rejected
-- generic return path, and its emitted effect here; the F200 scenario also
-- requires the product's four reviewed-forward decision log records.
local reviewed_forward_decisions = {
  {stream = "research_material_nickel", recipe = "angels-plate-nickel", certificate = "F200-BA-nickel-casting-v1"},
  {stream = "research_material_nickel", recipe = "angels-plate-nickel-2", certificate = "F200-BA-nickel-roll-v1"},
  {stream = "research_material_silver", recipe = "angels-plate-silver", certificate = "F200-BA-silver-casting-v1"},
  {stream = "research_material_silver", recipe = "angels-plate-silver-2", certificate = "F200-BA-silver-roll-v1"}
}
local productivity_streams = require("__more-infinite-research__/prototypes/streams/productivity")
compiler_context.with_active(compiler_context.new(), function()
  for _, expected in ipairs(reviewed_forward_decisions) do
    local stream = productivity_streams[expected.stream]
    local certificate = stream and stream.reviewed_forward_routes and stream.reviewed_forward_routes[expected.recipe]
    if not certificate or certificate.id ~= expected.certificate then
      error("MIR F200 reviewed-forward certificate differs for " .. expected.recipe)
    end
    local generic_admission, generic_reason = recipe_matching.material_route_is_acyclic(recipe_facts.view(expected.recipe))
    if generic_admission or string.sub(tostring(generic_reason), 1, 22) ~= "potential-return-path:" then
      error("MIR F200 reviewed-forward guard differs for " .. expected.recipe .. " reason=" .. tostring(generic_reason))
    end
    local technology = data.raw.technology["recipe-prod-" .. expected.stream .. "-1"]
    local emitted = false
    for _, effect in ipairs((technology and technology.effects) or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == expected.recipe and effect.change == 0.02 then
        emitted = true
      end
    end
    if not emitted then error("MIR F200 reviewed-forward route omitted " .. expected.recipe) end
    log("[mir-f200-material-routes] REVIEWED_FORWARD recipe=" .. expected.recipe
      .. " certificate=" .. expected.certificate .. " generic=" .. tostring(generic_reason)
      .. " effect=present")
  end
end)
log("[mir-f200-material-routes] PASS emitted=16 absent=0")
