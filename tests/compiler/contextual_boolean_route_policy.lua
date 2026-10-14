-- Source-bound real-context control for the Boolean acquisition companion.
--
-- The historical shared-witness experiment proved that importing a full
-- witness across queries can lose query-local preferred-route history.  This
-- control deliberately keeps the same S/T/Y/P shape, but warms only the
-- complete Boolean answer.  The later public witness and P route must remain
-- exactly the cold route; availability must never seed or replace a witness.

local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local production = require("prototypes.mir.capabilities.science_integration.pack_production_reachability")

local assertions, failures = 0, {}
local function check(id, condition, detail)
  assertions = assertions + 1
  if condition then return end
  failures[#failures + 1] = id .. ": " .. detail
end

local function run(context, callback)
  return compiler_context.with_active(context, callback)
end

local function new_context()
  local context = compiler_context.new({execution_mode = "SAFE"})
  science_packs.ensure_services(context)
  context:freeze_services()
  return context
end

local function pairs_from(value)
  local out, seen = {}, {}
  local function visit(node)
    if type(node) ~= "table" or seen[node] then return end
    seen[node] = true
    if node.kind == "research-unlocked-recipe" then
      out[(node.recipe or "") .. "\0" .. (node.unlocker or "")] = true
    end
    for _, child in pairs(node.ingredients or {}) do visit(child) end
    visit(node.recipe_witness)
    local machine = node.machine
    if type(machine) == "table" then
      visit(machine.acquisition)
      visit(machine.launcher)
      visit(machine.ammunition)
    end
    if type(node.receiver) == "table" then visit(node.receiver.acquisition) end
  end
  visit(value)
  return out
end

local function route_pairs(route)
  local out = {}
  for _, pair in ipairs((route and route.provenance and route.provenance.selected_research_unlock_pairs) or {}) do
    out[(pair.recipe or "") .. "\0" .. (pair.unlocker or "")] = true
  end
  return out
end

local function pair_text(pair_set)
  local values = {}
  for value in pairs(pair_set or {}) do values[#values + 1] = value:gsub("\0", "::") end
  table.sort(values)
  return table.concat(values, "|")
end

local function route_vector(route)
  local unlockers, selected_pairs = {}, {}
  for _, unlocker in ipairs((route and route.unlockers) or {}) do unlockers[#unlockers + 1] = unlocker end
  for key in pairs(route_pairs(route)) do selected_pairs[#selected_pairs + 1] = key end
  table.sort(unlockers)
  table.sort(selected_pairs)
  return table.concat({
    tostring(route and route.recipe or ""),
    table.concat(unlockers, ","),
    table.concat(selected_pairs, "|")
  }, "\n")
end

local function assert_facts(context)
  return run(context, function()
    local index = recipe_facts.index_view()
    return index.facts["r_s0"] and index.facts["r_s0"].enabled_without_research == false
      and index.facts["r_s1"] and index.facts["r_s1"].enabled_without_research == false
      and index.facts["r_ta"] and index.facts["r_ta"].enabled_without_research == false
      and index.facts["r_tb"] and index.facts["r_tb"].enabled_without_research == false
      and index.facts["r_y"] and index.facts["r_y"].enabled_without_research == false
      and index.facts["r_p"] and index.facts["r_p"].enabled_without_research == false
      and #((index.by_output_identity or {})["item\0S"] or {}) == 2
      and #((index.by_output_identity or {})["item\0T"] or {}) == 2
  end)
end

local function availability(context, item_name)
  return run(context, function()
    return production.item_acquisition_available(item_name, {P = true}, {})
  end)
end

local function witness(context, item_name)
  return run(context, function()
    return production.item_acquisition_witness(item_name, {P = true}, {})
  end)
end

local function p_route(context)
  return run(context, function()
    return production.production_route_for_pack("P")
  end)
end

local function prepare_p_query(context)
  return run(context, function()
    local unlockers = production.researchable_unlockers_for_recipe("r_y")
    return production.item_acquisition_witness("seed", {P = true}, {}) ~= nil
      and lab_compatibility.valid_research_ingredients({{name = "P", amount = 1}})
      and #unlockers == 1 and unlockers[1] == "Y0"
  end)
end

-- The runner provides a fully real Factorio-like prototype table. Confirm its
-- initial and canonical facts so this test cannot pass from hand-written maps.
local cold = new_context()
check("CB-ROUTE-01", assert_facts(cold),
  "The actual recipe index must retain ordered disabled S, T, Y and P recipes")
check("CB-ROUTE-02", run(cold, function()
  return production.item_acquisition_witness("seed", {P = true}, {}) ~= nil
    and lab_compatibility.valid_research_ingredients({{name = "P", amount = 1}})
end), "The seed and P lab must be initially obtainable through default services")
check("CB-ROUTE-02A", prepare_p_query(cold),
  "The real P/Y research index must be constructed before the independent route query")

local cold_available, cold_paired = availability(cold, "Y")
local cold_witness = witness(cold, "Y")
local cold_witness_pairs = pairs_from(cold_witness)
check("CB-ROUTE-03", cold_paired == true and cold_available == (cold_witness ~= nil),
  "The canonical Boolean answer must equal the public real witness availability")
check("CB-ROUTE-04", cold_witness_pairs["r_y\0Y0"] and cold_witness_pairs["r_s0\0S0"]
  and cold_witness_pairs["r_tb\0TB"] and not cold_witness_pairs["r_ta\0TA"],
  "Under P's active guard, real Y proof selects T's later TB branch")
local cold_route = p_route(cold)
local cold_pairs = route_pairs(cold_route)
check("CB-ROUTE-05", cold_route and cold_route.recipe == "r_p" and cold_pairs["r_p\0P0"],
  "The ordinary public P route must still expose a selected provenance vector")

-- Two fresh Boolean calls have exactly the same guards as P's Y ingredient.
-- A completed Boolean cache may answer the second call, but it cannot export
-- a witness or recreate the retired cross-query witness-memo behavior.
local warm = new_context()
check("CB-ROUTE-06A", assert_facts(warm),
  "The warmed Context must start from the same canonical recipe facts")
check("CB-ROUTE-06B", prepare_p_query(warm),
  "The warmed Context must construct the same real P/Y research index")
local warm_counters = warm:state_view("compiler_telemetry").counters
local hits_before = warm_counters.science_contextual_boolean_acquisition_hits or 0
local warm_first, warm_first_paired = availability(warm, "Y")
local warm_second, warm_second_paired = availability(warm, "Y")
local hits_after = warm:state_view("compiler_telemetry").counters
  .science_contextual_boolean_acquisition_hits or 0
check("CB-ROUTE-07", warm_first_paired == true and warm_second_paired == true
  and warm_first == cold_available and warm_second == cold_available,
  "Cold and repeated contextual Boolean answers must agree without changing truth")
check("CB-ROUTE-07A", hits_after > hits_before,
  "The second exact contextual Boolean query must reuse only its completed truth answer")

local warm_witness = witness(warm, "Y")
local warm_witness_pairs = pairs_from(warm_witness)
check("CB-ROUTE-08", warm_witness ~= nil and pair_text(warm_witness_pairs) == pair_text(cold_witness_pairs),
  "A public witness after Boolean warming must retain the cold witness's selected proof")

-- The strong retired RP-CONTEXT-13/14 shape: Y internally proves S -> T=TB
-- while S is active, then P asks Y and a sibling T under its own route
-- policy.  A Boolean Y hit cannot seed, erase or otherwise alter that later
-- witness-local history or its public selected provenance.
local warm_route = p_route(warm)
check("CB-ROUTE-10", route_vector(warm_route) == route_vector(cold_route),
  "Warm Boolean availability and cold P route must keep the same selected recipe, gates and provenance")

-- The public witness contract remains isolated: callers cannot turn a Boolean
-- answer into mutable memo state by modifying their later witness copy.
if warm_witness and type(warm_witness.ingredients) == "table" and warm_witness.ingredients[1] then
  warm_witness.ingredients[1].kind = "caller-mutated"
end
local after_mutation = witness(warm, "Y")
check("CB-ROUTE-11", after_mutation ~= warm_witness
  and pair_text(pairs_from(after_mutation)) == pair_text(cold_witness_pairs),
  "Mutating a public witness copy after Boolean warming cannot alter a later answer")

-- The negative research-unlock memo includes the positive projection as a
-- prefix.  The caller has already constructed that projection for the
-- positive memo lookup, so an ordinary Context-owned query can reuse it.
-- The test-only hooks are injected by the Python runner into its private Lua
-- module copy; the player module exports no test authority.
local r29 = production.__mir_contextual_boolean_route_policy_test_hooks
check("CB-ROUTE-12A", type(r29) == "table"
  and type(r29.positive_witness_memo_key) == "function"
  and type(r29.negative_witness_memo_key) == "function"
  and type(r29.research_unlocked_output_witness) == "function",
  "The controlled module copy exposes the exact private key boundary")

local function r29_active_set_key(values)
  local names = {}
  for name, active in pairs(values or {}) do if active then names[#names + 1] = tostring(name) end end
  table.sort(names)
  return table.concat(names, "\1")
end

local function r29_identity_key(identity)
  local base = identity.type .. "\0" .. identity.name
  if identity.type == "fluid"
    and (identity.minimum_temperature ~= nil or identity.maximum_temperature ~= nil) then
    local minimum = identity.minimum_temperature and string.format("%.17g", identity.minimum_temperature) or ""
    local maximum = identity.maximum_temperature and string.format("%.17g", identity.maximum_temperature) or ""
    return base .. "\0temperature\0" .. minimum .. "\0" .. maximum
  end
  return base
end

local function r29_old_negative_key(identity, context, state, visiting_packs, visiting_technologies)
  return table.concat({
    r29_identity_key(identity),
    r29_active_set_key(visiting_packs),
    r29_active_set_key(visiting_technologies),
    tostring(state.recipe_source_epoch),
    r29_active_set_key(state.visiting),
    r29_active_set_key(context.pairs),
    r29_active_set_key(context.technologies)
  }, "\0")
end

local r29_identity = {type = "fluid", name = "fixture-steam", minimum_temperature = 100, maximum_temperature = 500}
local r29_visiting_packs = {P = true, S = true}
local r29_visiting_technologies = {Y0 = true}
local r29_context = {pairs = {["r_y\0Y0"] = true}, technologies = {Y0 = true}}
local r29_state = {recipe_source_epoch = 17, visiting = {["r29-active"] = true}}
local r29_expected = r29_old_negative_key(
  r29_identity, r29_context, r29_state, r29_visiting_packs, r29_visiting_technologies)
r29.reset_positive_key_call_count()
local r29_positive = r29.positive_witness_memo_key(
  r29_identity, r29_visiting_packs, r29_visiting_technologies)
check("CB-ROUTE-12B", r29.positive_key_call_count() == 1,
  "The positive memo projection is prepared once before the negative lookup")
r29.reset_positive_key_call_count()
local r29_reused = r29.negative_witness_memo_key(
  r29_identity, r29_context, r29_state, r29_visiting_packs, r29_visiting_technologies, r29_positive)
local r29_key_reuse = r29_reused == r29_expected and r29.positive_key_call_count() == 0
check("CB-ROUTE-12", r29_key_reuse,
  "An ordinary exact negative key reuses the already prepared positive projection without changing bytes")

local opaque_pairs_calls = 0
local function opaque_active_map(values)
  return setmetatable({}, {
    __pairs = function()
      opaque_pairs_calls = opaque_pairs_calls + 1
      return next, values, nil
    end
  })
end
local r29_opaque_packs = opaque_active_map({P = true, S = true})
local r29_opaque_technologies = opaque_active_map({Y0 = true})
local r29_opaque_expected = r29_old_negative_key(
  r29_identity, r29_context, r29_state, r29_opaque_packs, r29_opaque_technologies)
local r29_opaque_positive = r29.positive_witness_memo_key(
  r29_identity, r29_opaque_packs, r29_opaque_technologies)
r29.reset_positive_key_call_count()
local r29_opaque_reused = r29.negative_witness_memo_key(
  r29_identity, r29_context, r29_state, r29_opaque_packs, r29_opaque_technologies, r29_opaque_positive)
local opaque_identity_reads = 0
local r29_opaque_identity = setmetatable({}, {
  __index = function(_, key)
    opaque_identity_reads = opaque_identity_reads + 1
    return r29_identity[key]
  end
})
local r29_opaque_identity_expected = r29_old_negative_key(
  r29_opaque_identity, r29_context, r29_state, r29_visiting_packs, r29_visiting_technologies)
local r29_opaque_identity_positive = r29.positive_witness_memo_key(
  r29_opaque_identity, r29_visiting_packs, r29_visiting_technologies)
r29.reset_positive_key_call_count()
local r29_opaque_identity_reused = r29.negative_witness_memo_key(
  r29_opaque_identity, r29_context, r29_state, r29_visiting_packs, r29_visiting_technologies,
  r29_opaque_identity_positive)
local r29_opaque_fallback = r29_opaque_reused == r29_opaque_expected
  and r29_opaque_identity_reused == r29_opaque_identity_expected
  and r29.positive_key_call_count() == 1 and opaque_pairs_calls >= 6 and opaque_identity_reads >= 6
check("CB-ROUTE-13", r29_opaque_fallback,
  "Opaque identity or active maps retain the historical second positive-key observation")

local r29_opaque_key_fallback = true
for position = 1, 2 do
  local stringifications = 0
  local opaque_name = setmetatable({}, {__tostring = function()
    stringifications = stringifications + 1
    return "opaque-active-name"
  end})
  local packs = position == 1 and {[opaque_name] = true} or {}
  local technologies = position == 2 and {[opaque_name] = true} or {}
  local expected = r29_old_negative_key(r29_identity, r29_context, r29_state, packs, technologies)
  stringifications = 0
  local positive = r29.positive_witness_memo_key(r29_identity, packs, technologies)
  local actual = r29.negative_witness_memo_key(
    r29_identity, r29_context, r29_state, packs, technologies, positive)
  local retained = actual == expected and stringifications == 2
  r29_opaque_key_fallback = r29_opaque_key_fallback and retained
  check("CB-ROUTE-13-KEY-" .. position, retained,
    "Plain active maps with opaque keys retain both historical stringifications")
end

local r29_negative_hit, r29_diagnostic_bypass = run(cold, function()
  local state = cold:state_view("science_pack_production").route_witness_state
  local options = {active_unlock_context = {pairs = {}, technologies = {}}, technology_reason_memo = {}}
  local missing = {type = "item", name = "r29-no-output"}
  r29.reset_positive_key_call_count()
  local first = r29.research_unlocked_output_witness(missing, options, state, {}, {})
  local entries = options.research_unlock_negative_memo_entries
  r29.reset_positive_key_call_count()
  local second = r29.research_unlocked_output_witness(missing, options, state, {}, {})
  local hit = first == nil and second == nil and entries == 1
    and options.research_unlock_negative_memo_entries == 1 and r29.positive_key_call_count() == 1
  local diagnostic = {active_unlock_context = {pairs = {}, technologies = {}}, diagnostic_observer = {}}
  r29.reset_positive_key_call_count()
  local projected = r29.research_unlocked_output_witness(missing, diagnostic, state, {}, {})
  local bypass = projected == nil and diagnostic.research_unlock_positive_memo == nil
    and diagnostic.research_unlock_negative_memo == nil and r29.positive_key_call_count() == 0
  return hit, bypass
end)
check("CB-ROUTE-14", r29_negative_hit and r29_diagnostic_bypass,
  "A preloaded negative remains exact while diagnostics retain their cache-free path")

if #failures > 0 then error(table.concat(failures, "\n"), 0) end

return {
  assertions = assertions,
  cold_available = cold_available and true or false,
  warm_available = warm_second and true or false,
  boolean_hits = hits_after - hits_before,
  cold_route = route_vector(cold_route),
  warm_route = route_vector(warm_route),
  r29_key_reuse = r29_key_reuse,
  r29_opaque_fallback = r29_opaque_fallback,
  r29_opaque_key_fallback = r29_opaque_key_fallback,
  r29_negative_hit = r29_negative_hit and r29_diagnostic_bypass
}
