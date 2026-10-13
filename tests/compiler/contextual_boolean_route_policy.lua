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

if #failures > 0 then error(table.concat(failures, "\n"), 0) end

return {
  assertions = assertions,
  cold_available = cold_available and true or false,
  warm_available = warm_second and true or false,
  boolean_hits = hits_after - hits_before,
  cold_route = route_vector(cold_route),
  warm_route = route_vector(warm_route)
}
