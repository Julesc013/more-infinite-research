local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {
  policy_id = "SciencePackProductionRoutePolicyV1"
}

local function as_set(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[value] = true end
  return out
end

local function strict_subset(left, right)
  local left_set = as_set(left)
  local right_set = as_set(right)
  local strictly_smaller = false
  for value in pairs(left_set) do
    if not right_set[value] then return false end
  end
  for value in pairs(right_set) do
    if not left_set[value] then strictly_smaller = true end
  end
  return strictly_smaller
end

local function graph_precedes(left, right)
  if not left.unlocker or not right.unlocker then return false end
  local left_closure = as_set(left.prerequisite_closure)
  local right_closure = as_set(right.prerequisite_closure)
  return right_closure[left.unlocker] == true and left_closure[right.unlocker] ~= true
end

local function retain_undominated(routes, precedes)
  local retained = {}
  for candidate_index, candidate in ipairs(routes) do
    local dominated = false
    for other_index, other in ipairs(routes) do
      if candidate_index ~= other_index and precedes(other, candidate) then
        dominated = true
        break
      end
    end
    if not dominated then table.insert(retained, candidate) end
  end
  return retained
end

local function numeric(value)
  return type(value) == "number" and value or math.huge
end

local function progression_less(left, right)
  local left_progression = left.progression_key or {}
  local right_progression = right.progression_key or {}
  for _, field in ipairs({
    "science_burden_count",
    "prerequisite_count",
    "unlock_depth",
    "research_count",
    "research_time"
  }) do
    local left_value = numeric(left_progression[field])
    local right_value = numeric(right_progression[field])
    if left_value ~= right_value then return left_value < right_value end
  end
  local left_unlocker = tostring(left.unlocker or "")
  local right_unlocker = tostring(right.unlocker or "")
  if left_unlocker ~= right_unlocker then return left_unlocker < right_unlocker end
  return tostring(left.recipe or "") < tostring(right.recipe or "")
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

  local graph_frontier = retain_undominated(reachable, graph_precedes)
  local burden_frontier = retain_undominated(graph_frontier, function(left, right)
    return strict_subset(left.science_burden, right.science_burden)
  end)
  table.sort(burden_frontier, progression_less)

  local selected = deepcopy(burden_frontier[1])
  selected.provenance = selected.provenance or {}
  selected.provenance.selection_policy = M.policy_id
  selected.provenance.candidate_route_count = #(routes or {})
  selected.provenance.reachable_route_count = reachable_count
  selected.provenance.graph_frontier_count = #graph_frontier
  selected.provenance.science_burden_frontier_count = #burden_frontier
  return selected
end

return M
