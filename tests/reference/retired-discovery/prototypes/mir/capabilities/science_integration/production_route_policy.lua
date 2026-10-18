local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {
  policy_id = "SciencePackProductionRoutePolicyV1"
}

local function as_set(values)
  local out, count = {}, 0
  for _, value in ipairs(values or {}) do
    if not out[value] then out[value], count = true, count + 1 end
  end
  return out, count
end

local function strict_subset(left, right)
  for value in pairs(left) do
    if not right[value] then return false end
  end
  return true -- Callers have already established strictly smaller cardinality.
end

local function sorted_gates(route)
  local gates, seen = {}, {}
  for _, technology_name in ipairs(route.unlockers or {}) do
    if technology_name and not seen[technology_name] then
      seen[technology_name] = true
      table.insert(gates, technology_name)
    end
  end
  -- Legacy singleton routes remain comparable while the planner consumes the
  -- plural gate contract.
  if route.unlocker and not seen[route.unlocker] then
    seen[route.unlocker] = true
    table.insert(gates, route.unlocker)
  end
  for _, technology_name in ipairs(route.prerequisite_closure or {}) do
    if technology_name and not seen[technology_name] then
      seen[technology_name] = true
      table.insert(gates, technology_name)
    end
  end
  table.sort(gates)
  return gates
end

local function retain_undominated(routes, set_field, count_field)
  local groups, sizes = {}, {}
  for _, route in ipairs(routes) do
    local size = route[count_field]
    if not groups[size] then groups[size], sizes[#sizes + 1] = {}, size end
    local group = groups[size]
    group[#group + 1] = route
  end
  table.sort(sizes)
  local minimal, admitted = {}, {}
  for _, size in ipairs(sizes) do
    local earlier_count = #minimal
    for _, candidate in ipairs(groups[size]) do
      local dominated = false
      -- Equal-sized sets cannot be strict subsets. A discarded dominator
      -- adds no information: one of its retained subsets also dominates.
      for index = 1, earlier_count do
        if strict_subset(minimal[index][set_field], candidate[set_field]) then
          dominated = true
          break
        end
      end
      if not dominated then
        minimal[#minimal + 1], admitted[candidate] = candidate, true
      end
    end
  end
  -- Keep the original input order, including complete comparator ties.
  local retained = {}
  for _, route in ipairs(routes) do
    if admitted[route] then retained[#retained + 1] = route end
  end
  return retained
end

local function numeric(value)
  return type(value) == "number" and value or math.huge
end

local ranking_fields = {
    "science_burden_count",
    "prerequisite_count",
    "unlock_depth",
    "research_count",
    "research_time"
}

local function prepare(route)
  local gates = sorted_gates(route)
  local gate_set = as_set(gates)
  local science_set, science_count = as_set(route.science_burden)
  local rank, progression = {}, route.progression_key or {}
  for index, field in ipairs(ranking_fields) do rank[index] = numeric(progression[field]) end
  return {route = route, gate_set = gate_set, gate_count = #gates,
    science_set = science_set, science_count = science_count, rank = rank,
    gates_key = table.concat(gates, "\0"), recipe_key = tostring(route.recipe or "")}
end

local function progression_less(left, right)
  for index = 1, #ranking_fields do
    local left_value = left.rank[index]
    local right_value = right.rank[index]
    if left_value ~= right_value then return left_value < right_value end
  end
  local left_gates = left.gates_key
  local right_gates = right.gates_key
  if left_gates ~= right_gates then return left_gates < right_gates end
  return left.recipe_key < right.recipe_key
end

function M.select(routes)
  local reachable = {}
  for _, route in ipairs(routes or {}) do
    if route.reachable == true then table.insert(reachable, route) end
  end
  if #reachable == 0 then return nil end
  local reachable_count = #reachable

  local initial = {}
  for _, route in ipairs(reachable) do
    if route.initial == true then table.insert(initial, route) end
  end
  if #initial > 0 then reachable = initial end

  local prepared = {}
  for _, route in ipairs(reachable) do prepared[#prepared + 1] = prepare(route) end
  local graph_frontier = retain_undominated(prepared, "gate_set", "gate_count")
  local burden_frontier = retain_undominated(graph_frontier, "science_set", "science_count")
  table.sort(burden_frontier, progression_less)

  local selected = deepcopy(burden_frontier[1].route)
  selected.provenance = selected.provenance or {}
  selected.provenance.selection_policy = M.policy_id
  selected.provenance.candidate_route_count = #(routes or {})
  selected.provenance.reachable_route_count = reachable_count
  selected.provenance.graph_frontier_count = #graph_frontier
  selected.provenance.science_burden_frontier_count = #burden_frontier
  if selected.provenance.route_enumeration then
    -- These counts describe evaluated records, not skipped alternatives.
    selected.provenance.selection_counts_complete = selected.provenance.route_enumeration.complete
  end
  return selected
end

return M
