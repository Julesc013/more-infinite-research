-- Source-bound controls for the disabled-producer dominance sieve. They use
-- the module's private helpers and the real route policy, while their expected
-- decisions are stated as independently constructed selector outcomes.
local hooks = assert(ROUTE_CONSTRUCTION_SIEVE_HOOKS)
local policy = assert(ROUTE_CONSTRUCTION_SIEVE_POLICY)

local assertions = 0
local function check(name, condition)
  assertions = assertions + 1
  if not condition then error("route construction sieve assertion failed: " .. name, 2) end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[copy(key)] = copy(item) end
  return result
end

local function equal(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
  for key, value in pairs(right) do if not equal(value, left[key]) then return false end end
  return true
end

local function route(recipe, unlockers, prerequisite_closure, extra)
  local result = {
    recipe = recipe,
    reachable = true,
    initial = false,
    unlockers = copy(unlockers or {}),
    prerequisite_closure = copy(prerequisite_closure or {}),
    science_burden = {},
    progression_key = {
      science_burden_count = 0,
      prerequisite_count = 0,
      unlock_depth = 0,
      research_count = 0,
      research_time = 0
    }
  }
  for key, value in pairs(extra or {}) do result[key] = copy(value) end
  return result
end

local function winner(routes)
  local selected = policy.select(routes)
  return selected and selected.recipe or nil
end

local function cannot_win(recipe_name, routes, excluded_unlocker, observer)
  return hooks.disabled_producer_cannot_win(recipe_name, routes, excluded_unlocker, observer)
end

-- A canonical gate set must include plural gates, the legacy singleton, and
-- the closure exactly once. The helper must leave both its input and returned
-- data isolated across calls.
local duplicate_route = route("duplicate", {"T", "T"}, {"P", "T", "P"}, {unlocker = "legacy"})
local duplicate_snapshot = copy(duplicate_route)
local duplicate_set, duplicate_count = hooks.route_gate_set(duplicate_route)
check("gate-set-cardinality", duplicate_count == 3)
check("gate-set-membership", duplicate_set.T and duplicate_set.P and duplicate_set.legacy)
duplicate_set.injected = true
local repeat_set, repeat_count = hooks.route_gate_set(duplicate_route)
check("gate-set-isolation", repeat_count == 3 and not repeat_set.injected and equal(duplicate_route, duplicate_snapshot))

-- A strict known lower bound makes a disabled route unable to survive the
-- selector. This verifies the same winner with the candidate present, rather
-- than reproducing the helper's subset loop in the fixture.
local strict_incumbent = route("incumbent", {"P"}, {})
local strict_candidate = route("disabled-strict", {"T"}, {"P"})
local strict_inputs = {strict_incumbent}
local strict_snapshot = copy(strict_inputs)
check("strict-lower-bound", cannot_win("disabled-strict", strict_inputs) == true)
check("strict-selector-winner", winner(strict_inputs) == winner({strict_incumbent, strict_candidate}))
check("strict-input-isolation", equal(strict_inputs, strict_snapshot))
check("strict-repeat-after-cache", cannot_win("disabled-strict", strict_inputs) == true)

-- A recipe may aggregate through any declared outer unlocker. One incomparable
-- rebinding option must block the sieve even when another unlocker is dominated.
local rebinding_incumbent = route("incumbent", {"P"}, {})
local rebinding_candidate = route("multi-escape", {"T", "U"}, {"P", "Q"})
check("multi-unlocker-escape", cannot_win("multi-escape", {rebinding_incumbent}) == false)
check("multi-unlocker-selector", winner({rebinding_incumbent, rebinding_candidate}) == "incumbent")

-- Each possible outer unlocker is safely dominated here. This is distinct from
-- the escape case and confirms universal quantification over the unlocker list.
local all_dominated = route("incumbent", {"P"}, {})
local all_dominated_candidate = route("multi-dominated", {"T", "V"}, {"P"})
check("all-outer-unlockers-dominated", cannot_win("multi-dominated", {all_dominated}) == true)
check("all-outer-selector-winner", winner({all_dominated, all_dominated_candidate}) == "incumbent")

-- Equal closed gates may only be skipped for the same sole outer unlocker and
-- an incumbent whose semantic recipe key wins the policy tie-break.
local equal_earlier = route("a-existing", {"T"}, {"P"})
local equal_later_candidate = route("z-equal", {"T"}, {"P"})
check("equal-earlier-recipe", cannot_win("z-equal", {equal_earlier}) == true)
check("equal-earlier-selector", winner({equal_earlier, equal_later_candidate}) == "a-existing")

local equal_later = route("z-existing", {"T"}, {"P"})
local equal_earlier_candidate = route("a-earlier", {"T"}, {"P"})
check("equal-earlier-candidate-retained", cannot_win("a-earlier", {equal_later}) == false)
check("equal-earlier-candidate-wins", winner({equal_later, equal_earlier_candidate}) == "a-earlier")

local nonsingleton_equal = route("a-nonsingleton", {"T", "P"}, {})
check("equal-nonsingleton-retained", cannot_win("z-equal", {nonsingleton_equal}) == false)

-- Cardinality alone cannot prove subset membership. An incomparable route must
-- remain eligible even if its gate count is smaller than the disabled route.
local incomparable = route("a-incomparable", {"Q"}, {})
local incomparable_candidate = route("disabled-strict", {"T"}, {"P"})
check("incomparable-retained", cannot_win("disabled-strict", {incomparable}) == false)
check("incomparable-selector-uses-policy", winner({incomparable, incomparable_candidate}) == "disabled-strict")

-- Guards deliberately forbid sieve decisions when the proof is contextual,
-- incomplete, or lacks an actual candidate / incumbent.
check("observer-guard", cannot_win("disabled-strict", {strict_incumbent}, nil, {}) == false)
check("excluded-unlocker-guard", cannot_win("disabled-strict", {strict_incumbent}, "T") == false)
check("no-routes-guard", cannot_win("disabled-strict", {}) == false)
check("no-unlocker-guard", cannot_win("no-unlocker", {strict_incumbent}) == false)
check("structural-unknown-guard", cannot_win("structural-unknown", {strict_incumbent}) == false)

-- Legacy singleton data and duplicates remain safe through the strict route,
-- and distinct contextual calls must not be affected by prior static caching.
local legacy_strict = route("legacy-strict", {"P", "P"}, {}, {unlocker = "P"})
check("legacy-duplicate-strict", cannot_win("disabled-strict", {legacy_strict}) == true)
check("post-cache-unknown", cannot_win("structural-unknown", {strict_incumbent}) == false)

return {assertions = assertions}
