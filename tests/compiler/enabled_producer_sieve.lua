-- Source-bound controls for the enabled-only producer sieve.  The candidate
-- list comes from the actual feasibility module; expected outcomes below are
-- stated against the enabled-pass contract, not a duplicate route solver.
local hooks = assert(ENABLED_PRODUCER_SIEVE_HOOKS, "Missing producer-sieve hooks")
local feasibility = assert(ENABLED_PRODUCER_SIEVE_MODULE, "Missing feasibility module")

local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end

local function contains(values, wanted)
  for _, value in ipairs(values or {}) do if value == wanted then return true end end
  return false
end

local function state_for(index)
  local state = {
    recipe_source_epoch = "enabled-producer-sieve-epoch",
    recipe_index = index,
    visiting = {}, acquisition_memo = {}, stable_acquisition_memo = {},
    stable_acquisition_generation = 0,
    producer_orderings = {}, producer_ordering_entry_count = 0,
    producer_ordering_node_count = 0, producer_ordering_estimated_bytes = 0,
    machine_placement_items = {}, surface_results = {}
  }
  feasibility.bind_state_context(state, TEST_SIEVE_CONTEXT)
  return state
end

local function variant(enabled, output, options)
  options = options or {}
  return {
    name = options.name or "default", enabled = enabled, hidden = options.hidden == true,
    categories = {"crafting"}, ingredients = {},
    surface_conditions = options.surface_conditions,
    results = {{type = options.type or "item", name = output, amount = 1,
      probability = 1, temperature = options.temperature}}
  }
end

local function fact(variants, options)
  options = options or {}
  return {
    hidden = options.hidden == true,
    variants = variants,
    source_class = options.source_class or "ordinary"
  }
end

local output_key = "item\0target"
local names = {}
local facts = {
  ["enabled"] = fact({variant(true, "target")}),
  ["mixed"] = fact({variant(false, "target"), variant(true, "target")}),
  -- This candidate is deliberately indexed under target but has an
  -- incompatible detailed result.  The sieve must leave quantity/product
  -- semantics to route_for_recipe rather than changing the route contract.
  ["shape-unknown"] = fact({variant(true, "not-target")}),
  -- These remain in the enabled candidate list. Output temperature and
  -- surface feasibility are route properties, not sieve properties.
  ["surface-failing"] = fact({variant(true, "target", {
    surface_conditions = {{property = "pressure", min = 999, max = 999}}
  })}),
  ["mixed-hidden-disabled-enabled"] = fact({
    variant(true, "target", {name = "hidden", hidden = true}),
    variant(false, "target", {name = "disabled"}),
    variant(true, "target", {name = "enabled"})
  }),
  ["temperature-mismatch"] = fact({variant(true, "target", {
    type = "fluid", temperature = 20
  })}),
  ["hidden"] = fact({variant(true, "target")}, {hidden = true}),
}
for number = 1, 128 do
  local name = string.format("disabled-%03d", number)
  facts[name] = fact({variant(false, "target")})
  table.insert(names, name)
end
table.insert(names, "enabled")
table.insert(names, "mixed")
table.insert(names, "shape-unknown")
table.insert(names, "hidden")
table.insert(names, "surface-failing")
table.insert(names, "mixed-hidden-disabled-enabled")

local exact_buckets = {
  [output_key] = names,
  ["fluid\0target"] = {"temperature-mismatch"}
}
local bucket_reads = 0
local canonical = {facts = facts, by_output_identity = setmetatable({}, {
  __index = function(_, key)
    bucket_reads = bucket_reads + 1
    return exact_buckets[key]
  end
})}
TEST_SIEVE_CONTEXT.states.recipe_index = canonical
local normal_state = state_for(canonical)
local identity = {type = "item", name = "target"}

TEST_SIEVE_TELEMETRY = {}
local first = hooks.sorted_producers(canonical, identity, {}, normal_state)
check(#first == 5 and contains(first, "enabled") and contains(first, "mixed")
    and contains(first, "shape-unknown") and contains(first, "surface-failing"),
  "The normal enabled-only pass must retain every potentially enabled producer")
check(contains(first, "mixed-hidden-disabled-enabled"),
  "A recipe with hidden and disabled siblings must retain its visible enabled variant")
check(not contains(first, "hidden") and not contains(first, "disabled-001"),
  "Hidden and disabled-only producers must not enter the normal enabled-only pass")
check((TEST_SIEVE_TELEMETRY.science_initial_disabled_producers_sieved or 0) == 129,
  "The exact disabled-only and hidden candidates must be counted once on a cold ordering")

first[1] = "caller-corruption"
local second = hooks.sorted_producers(canonical, identity, {}, normal_state)
check(#second == 5 and not contains(second, "caller-corruption") and contains(second, "enabled"),
  "A caller mutation must not alter the bounded cached producer ordering")
check(bucket_reads == 1,
  "A warm canonical ordering must reuse its cached copy before reading the producer bucket")
local warm_bucket_reads = bucket_reads
check((TEST_SIEVE_TELEMETRY.science_initial_disabled_producers_sieved or 0) == 129,
  "A warm ordering must reuse its filtered names without repeating the sieve")
local cold_sieved = TEST_SIEVE_TELEMETRY.science_initial_disabled_producers_sieved or 0

local hot_identity = {type = "fluid", name = "target", minimum_temperature = 100}
local hot = hooks.sorted_producers(canonical, hot_identity, {}, normal_state)
check(#hot == 1 and hot[1] == "temperature-mismatch",
  "An enabled recipe with an unsuitable product temperature must reach full route proof")

local diagnostic = hooks.sorted_producers(canonical, identity, {diagnostic_observer = {}}, normal_state)
check(#diagnostic == #names and contains(diagnostic, "disabled-001") and contains(diagnostic, "hidden"),
  "Diagnostic ordering must retain every rejected producer for its explanation")

local callback_order = hooks.sorted_producers(canonical, identity, {
  diagnostic_failure = function() end
}, normal_state)
check(#callback_order == #names and contains(callback_order, "disabled-001"),
  "An explicit diagnostic callback must retain its ordinary complete producer order")

local foreign = {facts = facts, by_output_identity = {[output_key] = names}}
local foreign_state = state_for(foreign)
local foreign_order = hooks.sorted_producers(foreign, identity, {}, foreign_state)
check(#foreign_order == #names and contains(foreign_order, "disabled-001"),
  "A mutable caller-owned index must retain the uncached complete producer order")

-- An all-disabled producer set must still reach the existing researched-output
-- fallback.  The sieve only removes it from the enabled pass; it cannot turn
-- research availability into an impossible result.
local researched_facts = {
  ["research-only"] = fact({variant(false, "target")})
}
local researched_index = {
  facts = researched_facts,
  by_output_identity = {[output_key] = {"research-only"}}
}
TEST_SIEVE_CONTEXT.states.recipe_index = researched_index
local research_state = state_for(researched_index)
local research_calls = 0
local research_result = feasibility.acquisition_witness(identity, {
  recipe_index = researched_index,
  research_unlock_witness = function(requested_identity)
    research_calls = research_calls + 1
    return {kind = "research-unlocked-recipe", output = {
      type = requested_identity.type, name = requested_identity.name
    }}
  end
}, research_state)
check(research_calls == 1 and research_result and research_result.kind == "research-unlocked-recipe",
  "An all-disabled producer set must still invoke the researched-output fallback")

-- The callback-bearing path must still produce exact route diagnostics.  No
-- enabled candidate can succeed in this empty-machine world, so the disabled
-- producer remains visible to the callback instead of being silently omitted.
TEST_SIEVE_CONTEXT.states.recipe_index = researched_index
local diagnostic_state = state_for(researched_index)
local reasons = {}
feasibility.acquisition_witness(identity, {
  recipe_index = researched_index,
  diagnostic_failure = function(failure) table.insert(reasons, failure.reason) end
}, diagnostic_state)
check(contains(reasons, "recipe-not-enabled"),
  "The diagnostic callback must still observe a disabled producer rejection")

return {
  assertions = assertions,
  cold_sieved = cold_sieved,
  filtered = #second,
  complete = #diagnostic,
  research_calls = research_calls,
  warm_bucket_reads = warm_bucket_reads
}
