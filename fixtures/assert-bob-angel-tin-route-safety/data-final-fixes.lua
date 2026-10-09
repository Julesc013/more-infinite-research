local MAX_GRAPH_NODES = 30000
local MAX_GRAPH_EDGES = 100000
local MAX_GRAPH_DEPTH = 64
local MAX_SEARCH_ENTRIES = 30000
local MAX_RECIPE_ARITY = 24

local final_plate_producers = {
  ["angels-plate-tin"] = {
    role = "non-recycling",
    positive_ingredients = {{type = "fluid", name = "angels-liquid-molten-tin", amount = 40}},
    declared_products = {{type = "item", name = "bob-tin-plate", amount = 4}},
    role_evidence = {evidence_kind = "productive-final-plate-transformation", hidden = nil, enabled = false, category = nil, auto_recycle = false, allow_decomposition = nil, allow_productivity = true, recovery_structure = "not-applicable"},
    witness_target = {type = "fluid", name = "angels-liquid-molten-tin", amount = 40}
  },
  ["angels-plate-tin-2"] = {
    role = "non-recycling",
    positive_ingredients = {{type = "item", name = "angels-roll-tin", amount = 1}},
    declared_products = {{type = "item", name = "bob-tin-plate", amount = 4}},
    role_evidence = {evidence_kind = "productive-final-plate-transformation", hidden = nil, enabled = false, category = nil, auto_recycle = false, allow_decomposition = false, allow_productivity = true, recovery_structure = "not-applicable"},
    witness_target = {type = "item", name = "angels-roll-tin", amount = 1}
  },
  ["angels-plate-tin-recycling"] = {
    role = "recycling",
    positive_ingredients = {{type = "item", name = "bob-tin-plate", amount = 1}},
    declared_products = {{type = "item", name = "bob-tin-plate", amount = 1}},
    role_evidence = {evidence_kind = "hidden-disabled-recovery-structure", hidden = true, enabled = false, category = nil, auto_recycle = nil, allow_decomposition = nil, allow_productivity = nil, recovery_structure = "same-final-plate-input-and-output"}
  },
  ["angels-wire-tin-recycling"] = {
    role = "recycling",
    positive_ingredients = {{type = "item", name = "angels-wire-tin", amount = 1}},
    declared_products = {{type = "item", name = "bob-tin-plate", amount = 0}, {type = "item", name = "copper-cable", amount = 0}},
    role_evidence = {evidence_kind = "hidden-disabled-recovery-structure", hidden = true, enabled = false, category = nil, auto_recycle = nil, allow_decomposition = false, allow_productivity = nil, recovery_structure = "all-declared-products-zero-amount"}
  },
  ["bob-tin-plate"] = {
    role = "non-recycling",
    positive_ingredients = {{type = "item", name = "bob-tin-ore", amount = 1}},
    declared_products = {{type = "item", name = "bob-tin-plate", amount = 1}},
    role_evidence = {evidence_kind = "productive-final-plate-transformation", hidden = true, enabled = false, category = nil, auto_recycle = false, allow_decomposition = false, allow_productivity = true, recovery_structure = "not-applicable"},
    witness_target = {type = "item", name = "bob-tin-ore", amount = 1}
  },
  ["bob-tin-plate-recycling"] = {
    role = "recycling",
    positive_ingredients = {{type = "item", name = "bob-tin-plate", amount = 1}},
    declared_products = {{type = "item", name = "bob-tin-plate", amount = 1}},
    role_evidence = {evidence_kind = "hidden-disabled-recovery-structure", hidden = true, enabled = false, category = nil, auto_recycle = nil, allow_decomposition = nil, allow_productivity = nil, recovery_structure = "same-final-plate-input-and-output"}
  }
}

local function fail(message)
  error("[mir-bob-angel-tin-route-safety] " .. message)
end

local function sorted_keys(values)
  local result = {}
  for value in pairs(values) do result[#result + 1] = value end
  table.sort(result)
  return result
end

local function recipe_entries(values, fallback_name, fallback_amount, label)
  local result = {}
  if values ~= nil and type(values) ~= "table" then return nil, label .. " is not a table" end
  local source = values
  if source == nil and fallback_name ~= nil then source = {{name = fallback_name, amount = fallback_amount or 1}} end
  for _, value in pairs(source or {}) do
    if type(value) ~= "table" then return nil, label .. " entry is not a table" end
    local name = value.name or value[1]
    local amount = value.amount or value[2] or value.amount_min
    if type(name) ~= "string" or name == "" or type(amount) ~= "number" or amount < 0 then
      return nil, label .. " entry is malformed"
    end
    result[#result + 1] = {type = value.type or "item", name = name, amount = amount}
    if #result > MAX_RECIPE_ARITY then return nil, label .. " exceeds arity budget" end
  end
  return result
end

local function build_graph(recipes, node_limit, edge_limit)
  node_limit = node_limit or MAX_GRAPH_NODES
  edge_limit = edge_limit or MAX_GRAPH_EDGES
  local graph = {}
  local node_count = 0
  local edge_count = 0
  local function add_node(name)
    if graph[name] == nil then
      graph[name] = {}
      node_count = node_count + 1
      if node_count > node_limit then return false end
    end
    return true
  end
  for _, recipe_name in ipairs(sorted_keys(recipes)) do
    local recipe = recipes[recipe_name]
    local inputs, input_error = recipe_entries(recipe.ingredients, nil, nil, recipe_name .. " inputs")
    local outputs, output_error = recipe_entries(recipe.results, recipe.result, recipe.result_count, recipe_name .. " outputs")
    if input_error or output_error then return nil, input_error or output_error end
    for _, input in ipairs(inputs) do
      if input.amount > 0 and not add_node(input.name) then return nil, "node budget exceeded" end
      for _, output in ipairs(outputs) do
        if input.amount > 0 and output.amount > 0 then
          if not add_node(output.name) then return nil, "node budget exceeded" end
          edge_count = edge_count + 1
          if edge_count > edge_limit then return nil, "edge budget exceeded" end
          graph[input.name][#graph[input.name] + 1] = {recipe = recipe_name, to = output.name}
        end
      end
    end
  end
  for _, edges in pairs(graph) do table.sort(edges, function(left, right) return left.recipe == right.recipe and left.to < right.to or left.recipe < right.recipe end) end
  return graph, nil, {node_count = node_count, edge_count = edge_count}
end

local function find_path(graph, source, target, search_limit)
  search_limit = search_limit or MAX_SEARCH_ENTRIES
  local queue = {{node = source, path = {}}}
  local head = 1
  local seen = {[source] = 0}
  while head <= #queue do
    local current = queue[head]
    head = head + 1
    local depth = #current.path
    if head > search_limit then return nil, "search-budget" end
    if depth >= MAX_GRAPH_DEPTH then return nil, "depth-budget" end
    for _, edge in ipairs(graph[current.node] or {}) do
      local next_path = {}
      for index, step in ipairs(current.path) do next_path[index] = step end
      next_path[#next_path + 1] = {from = current.node, recipe = edge.recipe, to = edge.to}
      if edge.to == target then return next_path, nil end
      if seen[edge.to] == nil then
        seen[edge.to] = depth + 1
        queue[#queue + 1] = {node = edge.to, path = next_path}
      end
    end
  end
  return nil, nil
end

local function path_text(path)
  local steps = {}
  for _, step in ipairs(path or {}) do steps[#steps + 1] = step.from .. "--" .. step.recipe .. "-->" .. step.to end
  return table.concat(steps, "|")
end

local function entries_text(entries)
  local parts = {}
  for _, entry in ipairs(entries or {}) do
    parts[#parts + 1] = entry.type .. ":" .. entry.name .. ":" .. tostring(entry.amount)
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function sorted_entries(entries, positive_only, label)
  local result, seen = {}, {}
  for _, entry in ipairs(entries or {}) do
    if not positive_only or entry.amount > 0 then
      local key = entry.type .. ":" .. entry.name
      if seen[key] then fail(label .. " duplicate identity " .. key) end
      seen[key] = true
      result[#result + 1] = {type = entry.type, name = entry.name, amount = entry.amount}
    end
  end
  table.sort(result, function(left, right)
    local left_key = left.type .. ":" .. left.name
    local right_key = right.type .. ":" .. right.name
    return left_key < right_key
  end)
  return result
end

local function exact_entries(actual, expected, positive_only, label)
  local normalized_actual = sorted_entries(actual, positive_only, label .. " actual")
  local normalized_expected = sorted_entries(expected, false, label .. " expected")
  if #normalized_actual ~= #normalized_expected then fail(label .. " identity count differs") end
  for index, expected_entry in ipairs(normalized_expected) do
    local observed = normalized_actual[index]
    if observed.type ~= expected_entry.type or observed.name ~= expected_entry.name or observed.amount ~= expected_entry.amount then
      fail(label .. " identity differs at " .. tostring(index))
    end
  end
  return normalized_actual
end

local function state_text(value)
  if value == nil then return "nil" end
  return tostring(value)
end

local function role_state_text(evidence)
  return "hidden=" .. state_text(evidence.hidden) .. " enabled=" .. state_text(evidence.enabled) .. " category=" .. state_text(evidence.category) .. " auto-recycle=" .. state_text(evidence.auto_recycle) .. " allow-decomposition=" .. state_text(evidence.allow_decomposition) .. " allow-productivity=" .. state_text(evidence.allow_productivity)
end

local function assert_structural_role(recipe, expected, actual_inputs, actual_outputs, label)
  local evidence = expected.role_evidence
  if recipe.hidden ~= evidence.hidden or recipe.enabled ~= evidence.enabled or recipe.category ~= evidence.category or recipe.auto_recycle ~= evidence.auto_recycle or recipe.allow_decomposition ~= evidence.allow_decomposition or recipe.allow_productivity ~= evidence.allow_productivity then
    fail(label .. " role state differs")
  end
  if evidence.evidence_kind == "productive-final-plate-transformation" then
    local positive_outputs = sorted_entries(actual_outputs, true, label .. " positive outputs")
    if #positive_outputs ~= 1 or positive_outputs[1].type ~= "item" or positive_outputs[1].name ~= "bob-tin-plate" or positive_outputs[1].amount <= 0 then
      fail(label .. " productive final plate structure differs")
    end
    if evidence.recovery_structure ~= "not-applicable" then fail(label .. " productive recovery structure differs") end
  elseif evidence.evidence_kind == "hidden-disabled-recovery-structure" then
    if evidence.recovery_structure == "same-final-plate-input-and-output" then
      local inputs = sorted_entries(actual_inputs, true, label .. " recovery inputs")
      local outputs = sorted_entries(actual_outputs, true, label .. " recovery outputs")
      if #inputs ~= 1 or #outputs ~= 1 or inputs[1].type ~= "item" or inputs[1].name ~= "bob-tin-plate" or inputs[1].amount ~= 1 or outputs[1].type ~= "item" or outputs[1].name ~= "bob-tin-plate" or outputs[1].amount ~= 1 then
        fail(label .. " same final plate recovery structure differs")
      end
    elseif evidence.recovery_structure == "all-declared-products-zero-amount" then
      if #actual_outputs == 0 then fail(label .. " zero-output recovery structure absent") end
      for _, output in ipairs(actual_outputs) do if output.amount ~= 0 then fail(label .. " zero-output recovery structure differs") end end
    else
      fail(label .. " unknown recovery structure")
    end
  else
    fail(label .. " unknown role evidence kind")
  end
end

local expected_paths = {
  ["angels-plate-tin"] = {
    target = "angels-liquid-molten-tin",
    steps = {
      {from = "bob-tin-plate", recipe = "bob-bronze-alloy", to = "bob-bronze-alloy"},
      {from = "bob-bronze-alloy", recipe = "angels-advanced-chemical-plant", to = "angels-advanced-chemical-plant"},
      {from = "angels-advanced-chemical-plant", recipe = "angels-advanced-chemical-plant-recycling", to = "electronic-circuit"},
      {from = "electronic-circuit", recipe = "agricultural-tower", to = "agricultural-tower"},
      {from = "agricultural-tower", recipe = "agricultural-tower-recycling", to = "spoilage"},
      {from = "spoilage", recipe = "burnt-spoilage", to = "angels-solid-carbon"},
      {from = "angels-solid-carbon", recipe = "angels-ingot-tin-3", to = "angels-ingot-tin"},
      {from = "angels-ingot-tin", recipe = "angels-liquid-molten-tin", to = "angels-liquid-molten-tin"}
    }
  },
  ["angels-plate-tin-2"] = {
    target = "angels-roll-tin",
    steps = {
      {from = "bob-tin-plate", recipe = "bob-bronze-alloy", to = "bob-bronze-alloy"},
      {from = "bob-bronze-alloy", recipe = "angels-advanced-chemical-plant", to = "angels-advanced-chemical-plant"},
      {from = "angels-advanced-chemical-plant", recipe = "angels-advanced-chemical-plant-recycling", to = "electronic-circuit"},
      {from = "electronic-circuit", recipe = "poison-capsule", to = "poison-capsule"},
      {from = "poison-capsule", recipe = "poison-capsule-recycling", to = "coal"},
      {from = "coal", recipe = "angels-coal-cracking-2", to = "angels-liquid-mineral-oil"},
      {from = "angels-liquid-mineral-oil", recipe = "angels-liquid-coolant", to = "angels-liquid-coolant"},
      {from = "angels-liquid-coolant", recipe = "angels-roll-tin-2", to = "angels-roll-tin"}
    }
  },
  ["bob-tin-plate"] = {
    target = "bob-tin-ore",
    steps = {
      {from = "bob-tin-plate", recipe = "bob-bronze-alloy", to = "bob-bronze-alloy"},
      {from = "bob-bronze-alloy", recipe = "angels-advanced-chemical-plant", to = "angels-advanced-chemical-plant"},
      {from = "angels-advanced-chemical-plant", recipe = "angels-advanced-chemical-plant-recycling", to = "angels-clay-brick"},
      {from = "angels-clay-brick", recipe = "angels-sintering-oven", to = "angels-sintering-oven"},
      {from = "angels-sintering-oven", recipe = "angels-sintering-oven-recycling", to = "iron-plate"},
      {from = "iron-plate", recipe = "sulfuric-acid", to = "sulfuric-acid"},
      {from = "sulfuric-acid", recipe = "angels-ore3-crystal", to = "angels-ore3-crystal"},
      {from = "angels-ore3-crystal", recipe = "angels-ore3-crystal-processing", to = "bob-tin-ore"}
    }
  }
}

local function exact_path(actual, expected, label)
  if #actual ~= #expected then fail(label .. " witness length differs") end
  for index, step in ipairs(expected) do
    local observed = actual[index]
    if observed.from ~= step.from or observed.recipe ~= step.recipe or observed.to ~= step.to then
      fail(label .. " witness differs at " .. tostring(index))
    end
  end
end

local graph, graph_error, graph_meta = build_graph(data.raw.recipe)
if not graph then fail("graph construction failed closed: " .. graph_error) end
if graph_meta.node_count ~= 1074 then fail("observed graph node count differs " .. tostring(graph_meta.node_count)) end

local observed_declared = {}
for _, recipe_name in ipairs(sorted_keys(data.raw.recipe)) do
  local outputs, output_error = recipe_entries(data.raw.recipe[recipe_name].results, data.raw.recipe[recipe_name].result, data.raw.recipe[recipe_name].result_count, recipe_name .. " outputs")
  if output_error then fail("declared producer scan failed closed: " .. output_error) end
  for _, output in ipairs(outputs) do if output.name == "bob-tin-plate" then observed_declared[recipe_name] = true end end
end
for recipe_name in pairs(final_plate_producers) do if not observed_declared[recipe_name] then fail("declared producer absent " .. recipe_name) end end
for recipe_name in pairs(observed_declared) do if not final_plate_producers[recipe_name] then fail("unexpected declared producer " .. recipe_name) end end

for _, recipe_name in ipairs(sorted_keys(final_plate_producers)) do
  local expected = final_plate_producers[recipe_name]
  local recipe = data.raw.recipe[recipe_name]
  if not recipe then fail("declared final producer is absent " .. recipe_name) end
  local inputs, input_error = recipe_entries(recipe.ingredients, nil, nil, recipe_name .. " inputs")
  local outputs, output_error = recipe_entries(recipe.results, recipe.result, recipe.result_count, recipe_name .. " outputs")
  if input_error or output_error then fail("declared producer structure failed closed " .. tostring(input_error or output_error)) end
  local positive_inputs = exact_entries(inputs, expected.positive_ingredients, true, recipe_name .. " positive ingredients")
  local declared_outputs = exact_entries(outputs, expected.declared_products, false, recipe_name .. " declared products")
  assert_structural_role(recipe, expected, inputs, outputs, recipe_name)
  log("[mir-bob-angel-tin-route-safety] STRUCTURE recipe=" .. recipe_name .. " role=" .. expected.role .. " evidence=" .. expected.role_evidence.evidence_kind .. " inputs=" .. entries_text(positive_inputs) .. " outputs=" .. entries_text(declared_outputs) .. " " .. role_state_text(expected.role_evidence) .. " recovery=" .. expected.role_evidence.recovery_structure)
  if expected.role == "non-recycling" then
    local witness_target = expected.witness_target
    if #positive_inputs ~= 1 or positive_inputs[1].type ~= witness_target.type or positive_inputs[1].name ~= witness_target.name or positive_inputs[1].amount ~= witness_target.amount or witness_target.name ~= expected_paths[recipe_name].target then
      fail(recipe_name .. " witness target is not bound to exact positive ingredient set")
    end
    local path, path_error = find_path(graph, "bob-tin-plate", expected_paths[recipe_name].target)
    if path_error or not path then fail("route classification failed closed " .. recipe_name .. " " .. tostring(path_error or "missing-return-path")) end
    exact_path(path, expected_paths[recipe_name].steps, recipe_name)
    log("[mir-bob-angel-tin-route-safety] CLASSIFIED recipe=" .. recipe_name .. " role=non-recycling classification=unsafe-under-conservative-potential-return-certificate reason=potential-return-path:" .. expected_paths[recipe_name].target .. " witness=" .. path_text(path))
  else
    log("[mir-bob-angel-tin-route-safety] CLASSIFIED recipe=" .. recipe_name .. " role=recycling classification=excluded-recovery")
  end
end

local direct_plate_to_ore = {}
for _, recipe_name in ipairs(sorted_keys(data.raw.recipe)) do
  local recipe = data.raw.recipe[recipe_name]
  local inputs, input_error = recipe_entries(recipe.ingredients, nil, nil, recipe_name .. " inputs")
  local outputs, output_error = recipe_entries(recipe.results, recipe.result, recipe.result_count, recipe_name .. " outputs")
  if input_error or output_error then fail("direct edge scan failed closed: " .. tostring(input_error or output_error)) end
  local consumes_plate, produces_ore = false, false
  for _, input in ipairs(inputs) do if input.name == "bob-tin-plate" and input.amount > 0 then consumes_plate = true end end
  for _, output in ipairs(outputs) do if output.name == "bob-tin-ore" and output.amount > 0 then produces_ore = true end end
  if consumes_plate and produces_ore then direct_plate_to_ore[#direct_plate_to_ore + 1] = recipe_name end
end
if #direct_plate_to_ore ~= 0 then fail("direct plate to ore edge unexpectedly present") end

local synthetic_safe = { ["synthetic-input"] = {{recipe = "synthetic-forward", to = "synthetic-final"}}, ["synthetic-final"] = {} }
local safe_path, safe_error = find_path(synthetic_safe, "synthetic-final", "synthetic-input")
if safe_path or safe_error then fail("synthetic known-safe control differs") end
local synthetic_over_budget = { ["synthetic-start"] = {{recipe = "synthetic-one", to = "synthetic-middle"}}, ["synthetic-middle"] = {{recipe = "synthetic-two", to = "synthetic-target"}}, ["synthetic-target"] = {} }
local over_budget_path, over_budget_error = find_path(synthetic_over_budget, "synthetic-start", "synthetic-target", 1)
if over_budget_path or over_budget_error ~= "search-budget" then fail("synthetic search-budget control differs") end
local malformed_entries, malformed_error = recipe_entries({{amount = 1}}, nil, nil, "synthetic malformed")
if malformed_entries or malformed_error ~= "synthetic malformed entry is malformed" then fail("synthetic malformed control differs") end
local node_graph, node_error = build_graph({synthetic = {ingredients = {{name = "a", amount = 1}}, results = {{name = "b", amount = 1}}}}, 1, 10)
if node_graph or node_error ~= "node budget exceeded" then fail("synthetic node-budget control differs") end
local edge_graph, edge_error = build_graph({synthetic = {ingredients = {{name = "a", amount = 1}}, results = {{name = "b", amount = 1}}}}, 10, 0)
if edge_graph or edge_error ~= "edge budget exceeded" then fail("synthetic edge-budget control differs") end
local structural_drift_rejected = pcall(function()
  exact_entries({{type = "item", name = "bob-tin-ore", amount = 2}}, final_plate_producers["bob-tin-plate"].positive_ingredients, true, "synthetic structural drift")
end)
if structural_drift_rejected then fail("synthetic structural drift was not rejected") end
local witness_drift = {}
for index, step in ipairs(expected_paths["bob-tin-plate"].steps) do witness_drift[index] = {from = step.from, recipe = step.recipe, to = step.to} end
witness_drift[4].to = "synthetic-drift"
local witness_drift_rejected = pcall(function() exact_path(witness_drift, expected_paths["bob-tin-plate"].steps, "synthetic witness drift") end)
if witness_drift_rejected then fail("synthetic witness drift was not rejected") end

-- Factorio modules cannot require a sibling mod's private matcher. The harness
-- separately binds the observable MIR log for bob-tin-plate; the Angel rows are
-- intentionally independent-checker-only classifications.
log("[mir-bob-angel-tin-route-safety] DATA PASS graph-nodes=1074 declared=6 recycling=3 non-recycling-unsafe=3 direct-plate-to-ore=0 synthetic-safe=pass synthetic-fail-closed=pass mir-bob-log-agreement=deferred")
