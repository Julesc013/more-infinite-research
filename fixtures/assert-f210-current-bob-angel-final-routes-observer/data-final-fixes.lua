-- Package-excluded, read-only evidence capture for the current F210
-- Bob/Angel tuple. This fixture observes possible ordinary Angel finals; it
-- does not declare routes, alter recipe permissions, or emit technologies.
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local data_raw = require("__more-infinite-research__/prototypes/mir/platform/factorio/data_raw")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local relationships = require("__more-infinite-research__/prototypes/mir/index/relationships")
local science = require("__more-infinite-research__/prototypes/mir/capabilities/science_integration/science_packs")
local production_reachability = require("__more-infinite-research__/prototypes/mir/capabilities/science_integration/pack_production_reachability")

-- These are candidates from the separately retained F200 closure, not an
-- assertion that the F210 graph is equivalent or that any route is admissible.
local CANDIDATES = {
  {family="aluminium", shape="cast-roll", name="angels-plate-aluminium"},
  {family="aluminium", shape="cast-roll", name="angels-plate-aluminium-2"},
  {family="gold", shape="cast-roll", name="angels-plate-gold"},
  {family="gold", shape="cast-roll", name="angels-plate-gold-2"},
  {family="gold", shape="wire", name="angels-wire-gold-2"},
  {family="lead", shape="cast-roll", name="angels-plate-lead"},
  {family="lead", shape="cast-roll", name="angels-plate-lead-2"},
  {family="nickel", shape="cast-roll", name="angels-plate-nickel"},
  {family="nickel", shape="cast-roll", name="angels-plate-nickel-2"},
  {family="silver", shape="cast-roll", name="angels-plate-silver"},
  {family="silver", shape="cast-roll", name="angels-plate-silver-2"},
  {family="silver", shape="wire", name="angels-wire-silver-2"},
  {family="titanium", shape="cast-roll", name="angels-plate-titanium"},
  {family="titanium", shape="cast-roll", name="angels-plate-titanium-2"},
  {family="zinc", shape="cast-roll", name="angels-plate-zinc"},
  {family="zinc", shape="cast-roll", name="angels-plate-zinc-2"},
  {family="brass", shape="molten-alloy", name="angels-plate-brass"},
  {family="bronze", shape="molten-alloy", name="angels-plate-bronze"},
  {family="cobalt-steel", shape="molten-alloy", name="angels-plate-cobalt-steel"},
  {family="gunmetal", shape="molten-alloy", name="angels-plate-gunmetal"},
  {family="invar", shape="molten-alloy", name="angels-plate-invar"},
  {family="nitinol", shape="molten-alloy", name="angels-plate-nitinol"}
}

local ENTRY_FIELDS = {
  "type", "name", "amount", "amount_min", "amount_max", "probability",
  "independent_probability", "declared_probability", "declared_independent_probability",
  "shared_probability", "extra_count_fraction", "catalyst_amount",
  "ignored_by_productivity", "ignored_by_stats", "temperature",
  "minimum_temperature", "maximum_temperature", "fluidbox_index",
  "percent_spoiled", "always_fresh", "reset_freshness_on_craft",
  "quality_min", "quality_max", "quality_change", "affected_by_quality"
}

-- Tin is the admitted early boundary. Aluminium is the next visible ordinary
-- family in the current route batch. A missing generated technology is an
-- observation, not a permission to synthesize an early science set.
local FRONTIER_EARLY_TECHNOLOGIES = {
  {family="tin", name="recipe-prod-research_material_tin-1"},
  {family="aluminium", name="recipe-prod-research_material_aluminium-1"}
}

local REQUIRED_FRONTIER_PACKS = {
  "chemical-science-pack",
  "production-science-pack",
  "utility-science-pack",
  "space-science-pack"
}

local function scalar(value)
  if value == nil then return "-" end
  if type(value) == "boolean" then return value and "true" or "false" end
  return tostring(value)
end

local function names_line(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[#out + 1] = tostring(value) end
  table.sort(out)
  return #out == 0 and "-" or table.concat(out, ",")
end

local function entry_line(entries)
  local output = {}
  for _, entry in ipairs(entries or {}) do
    local fields = {}
    for _, field in ipairs(ENTRY_FIELDS) do
      if entry[field] ~= nil then fields[#fields + 1] = field .. "=" .. scalar(entry[field]) end
    end
    output[#output + 1] = "{" .. table.concat(fields, ";") .. "}"
  end
  return #output == 0 and "-" or table.concat(output, "|")
end

local function identity(entry)
  return (entry.type or "item") .. ":" .. tostring(entry.name)
end

local function technology_binding(name)
  local technology = data_raw.technology(name)
  if type(technology) ~= "table" or type(technology.unit) ~= "table" then return name .. "[missing]" end
  local science, prerequisites = {}, {}
  for _, entry in ipairs(technology.unit.ingredients or {}) do
    science[#science + 1] = tostring(entry.name or entry[1]) .. ":" .. tostring(entry.amount or entry[2])
  end
  for _, prerequisite in ipairs(technology.prerequisites or {}) do prerequisites[#prerequisites + 1] = prerequisite end
  return name .. "[" .. names_line(science) .. "][" .. names_line(prerequisites) .. "]"
end

local function active_mods_line()
  local values = {}
  for name, version in pairs(mods or {}) do values[#values + 1] = name .. "=" .. tostring(version) end
  return names_line(values)
end

local function direct_output_producers(fact, index)
  local outputs, names = {}, {}
  for _, variant in ipairs(fact.variants or {}) do
    for _, result in ipairs(variant.results or {}) do outputs[identity(result)] = true end
  end
  for name, candidate in pairs(index.facts or {}) do
    local matches = false
    for _, variant in ipairs(candidate.variants or {}) do
      for _, result in ipairs(variant.results or {}) do
        if outputs[identity(result)] then matches = true; break end
      end
      if matches then break end
    end
    if matches then names[#names + 1] = name end
  end
  return names_line(names)
end

local function observe_bindings(name, input)
  local owners, unlocks = {}, {}
  for _, owner in ipairs((input.technologies_by_recipe_effect or {})[name] or {}) do owners[#owners + 1] = owner end
  for _, unlock in ipairs((input.unlocks_by_recipe or {})[name] or {}) do unlocks[#unlocks + 1] = technology_binding(unlock) end
  log("[mir-f210-current-ba-final-observer] BINDING recipe=" .. name
    .. " owners=" .. names_line(owners) .. " unlocks=" .. names_line(unlocks))
end

local function observe_variants(name, fact)
  for ordinal, variant in ipairs(fact.variants or {}) do
    log("[mir-f210-current-ba-final-observer] VARIANT recipe=" .. name
      .. " index=" .. tostring(ordinal)
      .. " hidden=" .. scalar(variant.hidden)
      .. " enabled=" .. scalar(variant.enabled)
      .. " declared_productivity=" .. scalar(variant.declared_allow_productivity)
      .. " effective_productivity=" .. scalar(variant.effective_allow_productivity)
      .. " maximum_productivity=" .. scalar(variant.effective_maximum_productivity)
      .. " inputs=" .. entry_line(variant.ingredients)
      .. " results=" .. entry_line(variant.results))
  end
end

local function collect_output_targets(fact, route, output_targets)
  for _, variant in ipairs(fact.variants or {}) do
    for _, result in ipairs(variant.results or {}) do
      local key = identity(result)
      local target = output_targets[key]
      if not target then target = {routes = {}}; output_targets[key] = target end
      target.routes[#target.routes + 1] = route
    end
  end
end

local function unit_ingredients_line(ingredients)
  local values = {}
  for _, ingredient in ipairs(ingredients or {}) do
    values[#values + 1] = tostring(ingredient.name or ingredient[1])
      .. ":" .. tostring(ingredient.amount or ingredient[2] or 1)
  end
  return names_line(values)
end

local function observe_early_science_technology(subject)
  local technology = data_raw.technology(subject.name)
  if type(technology) ~= "table" or type(technology.unit) ~= "table" then
    log("[mir-f210-current-ba-final-observer] EARLY_TECH family=" .. subject.family
      .. " technology=" .. subject.name .. " status=missing")
    return nil
  end
  local ingredients = technology.unit.ingredients or {}
  log("[mir-f210-current-ba-final-observer] EARLY_TECH family=" .. subject.family
    .. " technology=" .. subject.name .. " status=present"
    .. " unit_ingredients=" .. unit_ingredients_line(ingredients)
    .. " lab_accepts_unit=" .. scalar(science.valid_research_ingredients(ingredients)))
  return ingredients
end

local function route_reason_line(route)
  if type(route) ~= "table" then return "-" end
  local reachability = route.reachability or {}
  return "recipe=" .. scalar(route.recipe)
    .. ";unlocker=" .. scalar(route.unlocker)
    .. ";reachable=" .. scalar(route.reachable)
    .. ";status=" .. scalar(reachability.status)
    .. ";reason=" .. scalar(reachability.reason)
end

local function projection_reason_line(pack)
  local projection = production_reachability.pack_production_rejection_projection(pack, {
    limits = {candidates = 4, nodes = 64, depth = 16, bytes = 8192},
    subject = {stream = "research_material_tin", generated_technology = "recipe-prod-research_material_tin-4"}
  })
  if type(projection) ~= "table" then return "-" end
  local failure = projection.first_failure or {}
  return "status=" .. scalar(projection.status)
    .. ";prerequisite=" .. scalar(projection.prerequisite)
    .. ";kind=" .. scalar(failure.kind)
    .. ";reason=" .. scalar(failure.reason)
    .. ";candidates=" .. scalar(projection.candidate_count)
    .. ";truncated=" .. names_line((projection.truncation or {}).truncated)
end

local function observe_science_frontier()
  local early = {}
  for _, subject in ipairs(FRONTIER_EARLY_TECHNOLOGIES) do
    local ingredients = observe_early_science_technology(subject)
    if ingredients then early[#early + 1] = {family = subject.family, ingredients = ingredients} end
  end

  local selected, seen, required = {}, {}, {}
  for _, pack in ipairs(REQUIRED_FRONTIER_PACKS) do
    selected[#selected + 1] = pack
    seen[pack] = true
    required[pack] = true
  end
  for _, pack in ipairs(science.pack_list_all()) do
    if not seen[pack] then selected[#selected + 1] = pack; seen[pack] = true end
  end
  table.sort(selected)

  for _, pack in ipairs(selected) do
    local exists = science.science_pack_exists(pack)
    local recipe_status = science.recipe_unlock_facts.pack_recipe_status(pack) or {}
    local status, prerequisite = science.pack_production_status(pack, {}, {})
    local route = science.production_route_for_pack(pack)
    local rejection = status == "unreachable" and projection_reason_line(pack) or "-"
    log("[mir-f210-current-ba-final-observer] SCIENCE_PACK pack=" .. pack
      .. " required_frontier=" .. scalar(required[pack] == true)
      .. " official=" .. scalar(science.is_official_science_pack(pack))
      .. " mod_progression=" .. scalar(not science.is_official_science_pack(pack))
      .. " item_and_lab_input=" .. scalar(exists)
      .. " has_recipe=" .. scalar(recipe_status.has_recipe)
      .. " initially_available=" .. scalar(recipe_status.initially_available)
      .. " recipes=" .. names_line(recipe_status.recipes)
      .. " production_status=" .. scalar(status)
      .. " prerequisite=" .. scalar(prerequisite)
      .. " route=" .. route_reason_line(route)
      .. " rejection=" .. rejection)
  end

  for _, subject in ipairs(early) do
    log("[mir-f210-current-ba-final-observer] EARLY_LAB family=" .. subject.family
      .. " unit_ingredients=" .. unit_ingredients_line(subject.ingredients)
      .. " accepts=" .. scalar(science.valid_research_ingredients(subject.ingredients)))
  end
  log("[mir-f210-current-ba-final-observer] SCIENCE_FRONTIER PASS packs=" .. tostring(#selected)
    .. " early_present=" .. tostring(#early))
end

-- Chemical science is the first observed frontier missing in the combined
-- world. Inspect its exact final recipe and use the existing bounded
-- rejection projector once at its maximum documented work limit. A budget
-- result is still indeterminate evidence, never an admission override.
local function observe_chemical_science(input)
  local name = "chemical-science-pack"
  local fact = recipe_facts.view(name)
  if not fact then error("chemical science final recipe is missing") end
  log("[mir-f210-current-ba-final-observer] SCIENCE_RECIPE recipe=" .. name
    .. " source=" .. scalar(fact.source_class)
    .. " hidden=" .. scalar(fact.hidden)
    .. " enabled_without_research=" .. scalar(fact.enabled_without_research))
  observe_variants(name, fact)
  observe_bindings(name, input)
  for _, ingredient_name in ipairs({"bob-sodium-hydroxide", "angels-solid-sodium-hydroxide", "bob-salt"}) do
    local prototype = data_raw.prototype("item", ingredient_name)
    local producers = recipe_facts.recipes_by_output_identity_view("item", ingredient_name)
    log("[mir-f210-current-ba-final-observer] SCIENCE_INGREDIENT item=" .. ingredient_name
      .. " prototype=" .. scalar(prototype ~= nil)
      .. " hidden=" .. scalar(prototype and prototype.hidden)
      .. " producers=" .. names_line(producers)
      .. " producer_count=" .. tostring(#producers))
    for index, producer_name in ipairs(producers) do
      if index > 12 then break end
      local producer = recipe_facts.view(producer_name)
      log("[mir-f210-current-ba-final-observer] SCIENCE_PRODUCER item=" .. ingredient_name
        .. " recipe=" .. producer_name
        .. " source=" .. scalar(producer and producer.source_class)
        .. " hidden=" .. scalar(producer and producer.hidden)
        .. " enabled_without_research=" .. scalar(producer and producer.enabled_without_research))
      if producer then observe_variants(producer_name, producer) end
      observe_bindings(producer_name, input)
    end
  end
  local projection = production_reachability.pack_production_rejection_projection(name, {
    limits = {candidates = 16, nodes = 1024, depth = 128, bytes = 262144},
    subject = {stream = "research_material_aluminium",
      generated_technology = "recipe-prod-research_material_aluminium-1"}
  })
  local failure = projection and projection.first_failure or {}
  local truncation = projection and projection.truncation or {}
  local usage = truncation.usage or {}
  log("[mir-f210-current-ba-final-observer] SCIENCE_DIAGNOSTIC pack=" .. name
    .. " status=" .. scalar(projection and projection.status)
    .. " failure_kind=" .. scalar(failure.kind)
    .. " failure_reason=" .. scalar(failure.reason)
    .. " failure_recipe=" .. scalar(failure.recipe)
    .. " failure_technology=" .. scalar(failure.technology)
    .. " visits=" .. scalar(usage.visits)
    .. " max_depth=" .. scalar(usage.maximum_depth)
    .. " truncated=" .. names_line(truncation.truncated))
  for _, candidate in ipairs(projection and projection.candidates or {}) do
    local candidate_failure = candidate.first_failure or {}
    log("[mir-f210-current-ba-final-observer] SCIENCE_CANDIDATE recipe=" .. scalar(candidate.recipe)
      .. " structural=" .. scalar(candidate.structural_route and candidate.structural_route.status)
      .. " failure_kind=" .. scalar(candidate_failure.kind)
      .. " failure_reason=" .. scalar(candidate_failure.reason))
  end
end

-- Follow the real compiler decisions in an isolated ordinary context. The
-- capped rejection projector remains unchanged; its exhaustion is UNKNOWN.
-- These wrappers retain at most 64 distinct returned rejections, never alter
-- a result, and do not borrow or mutate the parent's acquisition/status memos.
local function observe_normal_science_decisions()
  local parent = compiler_context.current()
  local parent_states = {}
  for _, state_name in ipairs({"recipe_source", "recipe_index", "science_pack_production",
    "science_pack_recipe_status", "technology_researchability_index", "compiler_telemetry"}) do
    parent_states[state_name] = {value = parent:state_view(state_name), epoch = parent:state_epoch(state_name)}
  end
  local observation = compiler_context.new({execution_mode = parent:execution_mode()})
  for _, state_name in ipairs({"recipe_source", "recipe_index"}) do
    observation:set_state(state_name, assert(parent:state_view(state_name)))
  end
  local failures, seen = {}, {}
  for _, service_name in ipairs({
    "science.independent_pack_acquisition_witness",
    "science.prereq_tech_for_science_pack", "science.prereq_techs_for_science_pack",
    "science.production_route_for_pack"
  }) do
    observation:set_service(service_name, assert(parent:service(service_name)))
  end
  local reason_service = assert(parent:service("science.technology_researchability_reason"))
  observation:set_service("science.technology_researchability_reason", function(name, options)
    local reason = reason_service(name, options)
    local recipe = options and options.unlock_recipe_name or "-"
    local key = name .. "\0" .. recipe .. "\0" .. tostring(reason)
    if reason and not seen[key] and #failures < 64 then
      seen[key] = true
      failures[#failures + 1] = {technology = name, recipe = recipe, reason = reason}
    end
    return reason
  end)
  observation:set_service("science.pack_production_status", production_reachability.pack_production_status)
  observation:freeze_services()
  compiler_context.with_active(observation, function()
    for _, pack in ipairs({"logistic-science-pack", "chemical-science-pack"}) do
      local status, prerequisite = production_reachability.pack_production_status(pack, {}, {})
      log("[mir-f210-current-ba-final-observer] NORMAL_SCIENCE pack=" .. pack
        .. " status=" .. scalar(status) .. " prerequisite=" .. scalar(prerequisite))
    end
  end)
  for _, failure in ipairs(failures) do
    log("[mir-f210-current-ba-final-observer] NORMAL_REJECTION technology=" .. failure.technology
      .. " recipe=" .. failure.recipe .. " reason=" .. failure.reason)
  end
  assert(compiler_context.current() == parent, "normal observation did not restore parent context")
  for state_name, before in pairs(parent_states) do
    assert(parent:state_view(state_name) == before.value and parent:state_epoch(state_name) == before.epoch,
      "normal observation changed parent state " .. state_name)
  end
  log("[mir-f210-current-ba-final-observer] NORMAL_OBSERVATION PASS parent_state_unchanged=true"
    .. " retained_rejections=" .. tostring(#failures))
end

local function observe_hidden_output_consumers(output_targets, index)
  local count_by_output = {}
  for output in pairs(output_targets) do count_by_output[output] = 0 end
  for name, fact in pairs(index.facts or {}) do
    if fact.source_class == "hidden-internal" and fact.hidden == true and fact.enabled_without_research == false then
      for ordinal, variant in ipairs(fact.variants or {}) do
        if variant.hidden == true and variant.enabled == false then
          local matched = {}
          for _, ingredient in ipairs(variant.ingredients or {}) do
            local output = identity(ingredient)
            if output_targets[output] then matched[output] = true end
          end
          for output in pairs(matched) do
            count_by_output[output] = count_by_output[output] + 1
            log("[mir-f210-current-ba-final-observer] HIDDEN_OUTPUT_CONSUMER output=" .. output
              .. " routes=" .. names_line(output_targets[output].routes)
              .. " recipe=" .. name
              .. " index=" .. tostring(ordinal)
              .. " inputs=" .. entry_line(variant.ingredients)
              .. " results=" .. entry_line(variant.results))
          end
        end
      end
    end
  end
  local outputs = {}
  for output in pairs(output_targets) do outputs[#outputs + 1] = output end
  table.sort(outputs)
  for _, output in ipairs(outputs) do
    log("[mir-f210-current-ba-final-observer] HIDDEN_OUTPUT_SUMMARY output=" .. output
      .. " routes=" .. names_line(output_targets[output].routes)
      .. " count=" .. tostring(count_by_output[output]))
  end
end

-- The ordinary route guard intentionally reports only the first returned
-- ingredient name. Capture a deterministic recipe-by-recipe witness for the
-- current Gold candidate so a later review can distinguish a playable route
-- from a path that exists only through disabled or recovery recipes. This
-- mirrors material_graph's name-edge semantics and its bounded search.
local function observe_gold_return_path(index, input)
  local start_name, target_name = "bob-gold-plate", "angels-liquid-molten-gold"
  local adjacency, unique_name_edges, edge_count = {}, {}, 0
  local gold_route = recipe_facts.view("angels-plate-gold")
  local admitted, reason = recipe_matching.material_route_is_acyclic(gold_route)
  if admitted or reason ~= "potential-return-path:" .. target_name then
    error("Gold route safety endpoint changed: " .. tostring(reason))
  end
  local recipe_names = {}
  for name in pairs(index.facts or {}) do recipe_names[#recipe_names + 1] = name end
  table.sort(recipe_names)

  for _, recipe_name in ipairs(recipe_names) do
    local fact = index.facts[recipe_name]
    for variant_index, variant in ipairs(fact.variants or {}) do
      for input_index, ingredient in ipairs(variant.ingredients or {}) do
        if type(ingredient.name) == "string" and ingredient.name ~= "" then
          adjacency[ingredient.name] = adjacency[ingredient.name] or {}
          for result_index, result in ipairs(variant.results or {}) do
            if type(result.name) == "string" and result.name ~= "" then
              local pair_key = ingredient.name .. "\30" .. result.name
              if not unique_name_edges[pair_key] then
                unique_name_edges[pair_key] = true
                edge_count = edge_count + 1
                if edge_count > 100000 then error("Gold return-path witness exceeded material graph edge budget") end
              end
              adjacency[ingredient.name][#adjacency[ingredient.name] + 1] = {
                from_name = ingredient.name,
                to_name = result.name,
                recipe_name = recipe_name,
                variant_index = variant_index,
                input_index = input_index,
                result_index = result_index,
                ingredient = ingredient,
                result = result,
                fact = fact,
                variant = variant
              }
            end
          end
        end
      end
    end
  end

  -- material_graph() bounds the distinct untyped name edges, while retaining
  -- every edge in the witness adjacency so provenance stays deterministic.
  local function edge_key(edge)
    return table.concat({edge.recipe_name, tostring(edge.variant_index), edge.from_name,
      tostring(edge.ingredient.type or ""), edge.to_name, tostring(edge.result.type or ""),
      tostring(edge.input_index), tostring(edge.result_index)}, "\30")
  end
  for _, edges in pairs(adjacency) do
    table.sort(edges, function(left, right) return edge_key(left) < edge_key(right) end)
  end

  local queue, head, visited, predecessor = {start_name}, 1, {[start_name] = true}, {}
  while head <= #queue and not visited[target_name] do
    if head > 30000 then error("Gold return-path witness exceeded material search budget") end
    local current = queue[head]
    head = head + 1
    for _, edge in ipairs(adjacency[current] or {}) do
      if not visited[edge.to_name] then
        visited[edge.to_name] = true
        predecessor[edge.to_name] = edge
        queue[#queue + 1] = edge.to_name
      end
    end
  end
  if not visited[target_name] then
    error("Gold return-path witness no longer reaches " .. target_name .. " from " .. start_name)
  end

  local path, cursor = {}, target_name
  while cursor ~= start_name do
    local edge = predecessor[cursor]
    if not edge then error("Gold return-path witness predecessor chain is incomplete") end
    path[#path + 1] = edge
    cursor = edge.from_name
    if #path > 30000 then error("Gold return-path witness reconstruction exceeded search budget") end
  end
  local ordered = {}
  for index_in_path = #path, 1, -1 do ordered[#ordered + 1] = path[index_in_path] end

  log("[mir-f210-current-ba-final-observer] RETURN_PATH target=" .. target_name
    .. " start=item:" .. start_name .. " status=witnessed edges=" .. tostring(#ordered))
  for ordinal, edge in ipairs(ordered) do
    local fact, variant = edge.fact, edge.variant
    log("[mir-f210-current-ba-final-observer] RETURN_PATH_EDGE target=" .. target_name
      .. " step=" .. tostring(ordinal) .. "/" .. tostring(#ordered)
      .. " from=" .. identity(edge.ingredient)
      .. " to=" .. identity(edge.result)
      .. " recipe=" .. edge.recipe_name
      .. " variant=" .. tostring(edge.variant_index)
      .. " source=" .. scalar(fact.source_class)
      .. " hidden=" .. scalar(fact.hidden)
      .. " enabled_without_research=" .. scalar(fact.enabled_without_research)
      .. " variant_hidden=" .. scalar(variant.hidden)
      .. " variant_enabled=" .. scalar(variant.enabled)
      .. " productivity=" .. scalar(fact.effective_allow_productivity)
      .. " declared_productivity=" .. scalar(fact.declared_allow_productivity)
      .. " variant_productivity=" .. scalar(variant.effective_allow_productivity)
      .. " inputs=" .. entry_line(variant.ingredients)
      .. " results=" .. entry_line(variant.results))
    observe_bindings(edge.recipe_name, input)
  end
end

-- Separate ordinary visible recipe cycles from paths through hidden recipes.
-- Factorio's recycler can use generated hidden recycling recipes, so an
-- "absent" result here is not a player-safety proof. A "reachable" result is
-- useful counterevidence; neither outcome automatically admits a route.
local function observe_visible_return_paths(index)
  local adjacency, edges = {}, 0
  local recipe_names = {}
  for name in pairs(index.facts or {}) do recipe_names[#recipe_names + 1] = name end
  table.sort(recipe_names)
  for _, name in ipairs(recipe_names) do
    local fact = index.facts[name]
    if fact.source_class == "ordinary" and fact.hidden == false then
      for _, variant in ipairs(fact.variants or {}) do
        if variant.hidden == false then
          for _, ingredient in ipairs(variant.ingredients or {}) do
            if type(ingredient.name) == "string" and ingredient.name ~= "" then
              local next_edges = adjacency[ingredient.name]
              if not next_edges then next_edges = {}; adjacency[ingredient.name] = next_edges end
              for _, result in ipairs(variant.results or {}) do
                if type(result.name) == "string" and result.name ~= "" then
                  edges = edges + 1
                  if edges > 100000 then error("visible return observation exceeded edge budget") end
                  next_edges[#next_edges + 1] = {name = result.name, recipe = name}
                end
              end
            end
          end
        end
      end
    end
  end
  for _, next_edges in pairs(adjacency) do
    table.sort(next_edges, function(left, right)
      if left.name == right.name then return left.recipe < right.recipe end
      return left.name < right.name
    end)
  end
  for _, candidate in ipairs(CANDIDATES) do
    local fact = recipe_facts.view(candidate.name)
    if fact then
      local inputs, queue, visited, predecessor = {}, {}, {}, {}
      for _, variant in ipairs(fact.variants or {}) do
        for _, ingredient in ipairs(variant.ingredients or {}) do inputs[ingredient.name] = true end
        for _, result in ipairs(variant.results or {}) do
          if not visited[result.name] then
            visited[result.name] = true
            queue[#queue + 1] = result.name
          end
        end
      end
      local head, target = 1, nil
      while head <= #queue and not target do
        if head > 30000 then error("visible return observation exceeded search budget") end
        local current = queue[head]
        head = head + 1
        if inputs[current] then
          target = current
        else
          for _, edge in ipairs(adjacency[current] or {}) do
            if not visited[edge.name] then
              visited[edge.name] = true
              predecessor[edge.name] = {previous = current, recipe = edge.recipe}
              queue[#queue + 1] = edge.name
            end
          end
        end
      end
      local path = {}
      if target then
        local cursor = target
        while predecessor[cursor] do
          local edge = predecessor[cursor]
          path[#path + 1] = edge.recipe
          cursor = edge.previous
          if #path > 30000 then error("visible return observation exceeded path budget") end
        end
        local ordered = {}
        for i = #path, 1, -1 do ordered[#ordered + 1] = path[i] end
        path = ordered
      end
      log("[mir-f210-current-ba-final-observer] VISIBLE_RETURN recipe=" .. candidate.name
        .. " status=" .. (target and "reachable" or "absent")
        .. " target=" .. scalar(target)
        .. " steps=" .. tostring(#path)
        .. " path=" .. (#path == 0 and "-" or table.concat(path, ">")))
    end
  end
end

log("[mir-f210-current-ba-final-observer] ACTIVE_MODS " .. active_mods_line())
compiler_context.with_active(compiler_context.new(), function()
  local index = recipe_facts.index_view()
  local input = relationships.view("input")
  if type(index) ~= "table" or type(index.facts) ~= "table" or type(input) ~= "table" then
    error("MIR F210 current Bob/Angel final observer requires finalized recipe and relationship indexes")
  end
  local output_targets, observed, missing = {}, 0, 0
  for _, candidate in ipairs(CANDIDATES) do
    local fact = recipe_facts.view(candidate.name)
    if type(fact) ~= "table" then
      missing = missing + 1
      log("[mir-f210-current-ba-final-observer] ROUTE recipe=" .. candidate.name
        .. " family=" .. candidate.family .. " shape=" .. candidate.shape .. " status=missing")
    else
      observed = observed + 1
      local generic, generic_reason = recipe_matching.material_route_is_acyclic(fact)
      local boundary, boundary_reason = recipe_matching.relevant_route_fingerprints(fact)
      local risk = recipe_risk_facts.view(candidate.name)
      log("[mir-f210-current-ba-final-observer] ROUTE recipe=" .. candidate.name
        .. " family=" .. candidate.family .. " shape=" .. candidate.shape .. " status=present"
        .. " generic=" .. scalar(generic) .. " reason=" .. scalar(generic_reason)
        .. " source=" .. scalar(fact.source_class) .. " hidden=" .. scalar(fact.hidden)
        .. " enabled_without_research=" .. scalar(fact.enabled_without_research)
        .. " declared_productivity=" .. scalar(fact.declared_allow_productivity)
        .. " effective_productivity=" .. scalar(fact.effective_allow_productivity)
        .. " maximum_productivity=" .. scalar(fact.effective_maximum_productivity)
        .. " risk=" .. scalar(risk and risk.risk_fingerprint)
        .. " graph=" .. scalar(boundary and boundary.return_graph_fingerprint)
        .. " bindings=" .. scalar(boundary and boundary.bindings_fingerprint)
        .. " identities=" .. scalar(boundary and boundary.reachable_identity_count)
        .. " recipes=" .. scalar(boundary and boundary.relevant_recipe_count)
        .. " producers=" .. scalar(boundary and boundary.direct_output_producer_count)
        .. " boundary_reason=" .. scalar(boundary_reason)
        .. " direct_producer_names=" .. direct_output_producers(fact, index))
      observe_variants(candidate.name, fact)
      observe_bindings(candidate.name, input)
      collect_output_targets(fact, candidate.name, output_targets)
    end
  end
  observe_hidden_output_consumers(output_targets, index)
  observe_gold_return_path(index, input)
  observe_visible_return_paths(index)
  observe_science_frontier()
  observe_chemical_science(input)
  observe_normal_science_decisions()
  log("[mir-f210-current-ba-final-observer] DATA PASS read-only-finalized-contract-capture"
    .. " candidates=" .. tostring(#CANDIDATES)
    .. " observed=" .. tostring(observed)
    .. " missing=" .. tostring(missing))
end)
