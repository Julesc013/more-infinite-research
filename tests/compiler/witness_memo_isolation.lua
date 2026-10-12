local hooks = assert(WITNESS_MEMO_HOOKS, "Missing witness memo test hooks")
local feasibility = assert(WITNESS_MEMO_MODULE, "Missing witness memo module")

local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end

local function make_state()
  local state = {
    recipe_source_epoch = "memo-epoch",
    recipe_index = TEST_RECIPE_INDEX,
    visiting = {},
    acquisition_memo = {},
    stable_acquisition_memo = {},
    stable_acquisition_generation = 0
  }
  feasibility.bind_state_context(state, TEST_COMPILER_CONTEXT)
  return state
end

local shared = {kind = "minable-resource", output = {type = "item", name = "ore"}}
local receiver = {kind = "recipe", output = {type = "item", name = "receiver"}}
local launcher = {kind = "recipe", output = {type = "item", name = "launcher"}}
local ammunition = {kind = "recipe", output = {type = "item", name = "ammo"}}
local witness = {
  kind = "recipe",
  output = {type = "item", name = "root"},
  recipe_witness = shared,
  ingredients = {shared, shared},
  receiver = {acquisition = receiver},
  machine = {
    kind = "machine-capture",
    acquisition = shared,
    launcher = launcher,
    ammunition = ammunition
  }
}

local cycle = {kind = "cycle"}
cycle.self = cycle
local cloned_cycle = hooks.clone_witness_graph(cycle)
check(cloned_cycle ~= cycle and cloned_cycle.self == cloned_cycle,
  "The graph clone must preserve a structural cycle without retaining the source node")

local state = make_state()
TEST_PRODUCTION_STATE.route_witness_state = state
local root_key = feasibility.acquisition_key({type = "item", name = "root"})
local other_key = feasibility.acquisition_key({type = "item", name = "other"})
hooks.retain_witness_memo(state.stable_acquisition_memo, root_key, witness)
local other_witness = {kind = "recipe", output = {type = "item", name = "other"}, ingredients = {shared}}
hooks.retain_witness_memo(state.stable_acquisition_memo, other_key, other_witness)
local stored_root = state.stable_acquisition_memo[root_key]
local stored_other = state.stable_acquisition_memo[other_key]
check(stored_root ~= witness and stored_root.ingredients[1] == stored_root.ingredients[2],
  "The memo must own a graph and preserve its repeated aliases")

local private_options = {recipe_index = TEST_RECIPE_INDEX}
feasibility.enable_compiler_owned_witness_sharing(private_options)
check(hooks.private_witness_memo_allowed(private_options, state),
  "A compiler-marked, Context-owned state may borrow its private memo DAG")
local copied_private_options = hooks.copy_options(private_options)
check(hooks.private_witness_memo_allowed(copied_private_options, state),
  "Private ownership must survive the isolated initial-route option copy")
local private_first = feasibility.acquisition_witness({type = "item", name = "root"}, private_options, state)
local private_other = feasibility.acquisition_witness({type = "item", name = "other"}, private_options, state)
local private_second = feasibility.acquisition_witness({type = "item", name = "root"}, private_options, state)
check(private_first == stored_root and private_second == stored_root and private_other == stored_other,
  "Private warm calls must reuse the exact memo DAG regardless of query order")

local public_options = {recipe_index = TEST_RECIPE_INDEX}
local public_first = feasibility.acquisition_witness({type = "item", name = "root"}, public_options, state)
local public_second = feasibility.acquisition_witness({type = "item", name = "root"}, public_options, state)
check(public_first ~= stored_root and public_second ~= stored_root and public_first ~= public_second,
  "Public warm calls must receive independent graphs")
check(public_first.ingredients[1] == public_first.ingredients[2]
    and public_first.ingredients[1] == public_first.machine.acquisition,
  "Public isolation must preserve the selected witness DAG aliases")
public_first.ingredients[1].kind = "mutated-public-child"
public_first.machine.launcher.kind = "mutated-public-launcher"
check(stored_root.ingredients[1].kind == "minable-resource"
    and stored_root.machine.launcher.kind == "recipe"
    and public_second.ingredients[1].kind == "minable-resource"
    and public_second.machine.launcher.kind == "recipe",
  "A public caller mutation must not alter either the memo or a later caller")

local custom_options = {recipe_index = TEST_RECIPE_INDEX, source_witness = function() return nil end}
feasibility.enable_compiler_owned_witness_sharing(custom_options)
check(not hooks.private_witness_memo_allowed(custom_options, state),
  "Custom source witnesses must retain isolated output even with a private marker")
local diagnostic_options = {recipe_index = TEST_RECIPE_INDEX, diagnostic_failure = function() end}
feasibility.enable_compiler_owned_witness_sharing(diagnostic_options)
check(not hooks.private_witness_memo_allowed(diagnostic_options, state),
  "Diagnostic callers must retain isolated output even with a private marker")
local foreign_state = make_state()
foreign_state.recipe_index = {}
check(not hooks.private_witness_memo_allowed(private_options, foreign_state),
  "A state whose index is not the compiler-owned canonical index cannot borrow a DAG")
local unrelated_canonical_state = make_state()
check(not hooks.private_witness_memo_allowed(private_options, unrelated_canonical_state),
  "A public state with the live Context and canonical index cannot borrow the compiler witness DAG")

local probe_parent = make_state()
probe_parent.source_catalog = {immutable = true}
probe_parent.machine_categories = {immutable = true}
probe_parent.machine_placement_items = {immutable = true}
probe_parent.mining_drills = {immutable = true}
probe_parent.capturable_spawners = {immutable = true}
probe_parent.surface_locations = {immutable = true}
local private_probe = hooks.initial_failure_probe(probe_parent, {recipe_index = TEST_RECIPE_INDEX})
check(private_probe ~= nil and private_probe.state ~= probe_parent,
  "An eligible canonical query must create a distinct private failure-probe state")
local probe_state = private_probe.state
probe_state.visiting = {active = true}
probe_state.acquisition_memo[root_key] = stored_root
probe_state.stable_acquisition_memo[root_key] = stored_root
local probe_options = {recipe_index = TEST_RECIPE_INDEX, initial_failure_probe = true}
check(hooks.private_witness_memo_allowed(probe_options, probe_state),
  "A module-created initial-failure probe can reuse only its own internal graph")
hooks.retire_private_probe_witness_memos(probe_state)
check(next(probe_state.visiting) == nil and next(probe_state.acquisition_memo) == nil
    and next(probe_state.stable_acquisition_memo) == nil
    and probe_state.source_catalog.immutable and probe_state.machine_categories.immutable
    and probe_state.machine_placement_items.immutable and probe_state.mining_drills.immutable
    and probe_state.capturable_spawners.immutable and probe_state.surface_locations.immutable
    and probe_state.stable_acquisition_generation == 2,
  "Settled private failure probes must drop all witness results but retain immutable catalogs")

check((TEST_TELEMETRY.science_private_witness_memo_hits or 0) == 3,
  "The controlled private warm path must record each of its three borrowed DAG hits")
check((TEST_TELEMETRY.science_isolated_witness_memo_hits or 0) == 2,
  "The controlled public warm path must record both isolated hits")
check((TEST_TELEMETRY.science_witness_memo_graph_clones or 0) == 2,
  "The two cold memo writes must establish the graph-clone operation count")

print("MIR-WITNESS-MEMO-ISOLATION-PASS " .. assertions)
return {
  assertions = assertions,
  private_hits = TEST_TELEMETRY.science_private_witness_memo_hits or 0,
  isolated_hits = TEST_TELEMETRY.science_isolated_witness_memo_hits or 0,
  graph_clone_calls = TEST_TELEMETRY.science_witness_memo_graph_clones or 0
}
