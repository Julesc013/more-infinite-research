local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {
  policy_id = "SciencePackProductionRoutePolicyV2",
  classes = {
    ordinary_primary = "ordinary-primary",
    ordinary_alternate = "ordinary-alternate",
    extraction = "extraction",
    recycling = "recycling",
    recovery = "recovery",
    self_return = "self-return",
    catalyst_regeneration = "catalyst-regeneration",
    script_non_recipe = "script/non-recipe",
    opaque = "opaque"
  }
}

local DEFAULT_PROGRESSION_CLASSES = {
  [M.classes.ordinary_primary] = true,
  [M.classes.ordinary_alternate] = true,
  [M.classes.extraction] = true
}

local DECLARABLE_NON_ORDINARY_CLASSES = {
  [M.classes.recycling] = true,
  [M.classes.recovery] = true,
  [M.classes.catalyst_regeneration] = true,
  [M.classes.opaque] = true
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

local function retain_route_class_when_present(routes, route_class)
  local matching = {}
  for _, route in ipairs(routes or {}) do
    if route.route_class == route_class then table.insert(matching, route) end
  end
  return #matching > 0 and matching or routes
end

local function nonempty_string(value)
  return type(value) == "string" and value ~= ""
end

local function exact_progression_declaration(route)
  if route.route_class == M.classes.self_return then
    return false, "self_return_cannot_prove_acquisition"
  end
  if route.progression_authoritative ~= true then
    return false, "non_authoritative_route_class"
  end
  if not DECLARABLE_NON_ORDINARY_CLASSES[route.route_class] then
    return false, "route_class_not_declarable"
  end
  local authority = route.progression_authority
  if type(authority) ~= "table"
      or authority.kind ~= "exact-profile" and authority.kind ~= "mep"
      or not nonempty_string(authority.id)
      or not nonempty_string(authority.process_ir_certificate)
      or not nonempty_string(authority.target_proof) then
    return false, "incomplete_progression_authority"
  end
  return true
end

function M.progression_authority(route)
  if type(route) ~= "table" then return false, "invalid_route" end
  if DEFAULT_PROGRESSION_CLASSES[route.route_class] then return true, "default_net_acquisition" end
  return exact_progression_declaration(route)
end

function M.select(routes)
  local reachable = {}
  local rejected = {}
  for _, route in ipairs(routes or {}) do
    local authoritative, authority_reason = M.progression_authority(route)
    if authoritative then
      if route.reachable == true then
        table.insert(reachable, route)
      else
        table.insert(rejected, {
          recipe = route.recipe,
          route_class = route.route_class,
          reason = ((route.reachability or {}).reason) or "route_not_reachable"
        })
      end
    else
      -- Classification is independent of graph reachability. Retain the
      -- stronger non-progression witness even when evaluating the route's
      -- unlocker also encounters a cycle (for example a recycler unlock whose
      -- recipe consumes the very science pack being resolved).
      table.insert(rejected, {
        recipe = route.recipe,
        route_class = route.route_class,
        reason = authority_reason
      })
    end
  end
  if #reachable == 0 then
    return nil, {
      policy_id = M.policy_id,
      status = "no-progression-authoritative-route",
      candidate_route_count = #(routes or {}),
      rejected_routes = rejected
    }
  end
  local reachable_count = #reachable

  local initial = {}
  for _, route in ipairs(reachable) do
    if route.initial == true then table.insert(initial, route) end
  end
  if #initial > 0 then reachable = initial end

  -- An immediately available alternate is a real first-acquisition route.
  -- Otherwise, retain the canonical ordinary recipe whenever it is reachable;
  -- a later alternate must not replace it merely because its unlock technology
  -- has a smaller synthetic burden or a trigger instead of science units.
  reachable = retain_route_class_when_present(reachable, M.classes.ordinary_primary)

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
  selected.provenance.rejected_non_progression_route_count = #rejected
  selected.provenance.graph_frontier_count = #graph_frontier
  selected.provenance.science_burden_frontier_count = #burden_frontier
  return selected, {
    policy_id = M.policy_id,
    status = "selected",
    candidate_route_count = #(routes or {}),
    reachable_progression_route_count = reachable_count,
    rejected_routes = rejected,
    selected_recipe = selected.recipe,
    selected_route_class = selected.route_class
  }
end

return M
