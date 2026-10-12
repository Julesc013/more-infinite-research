local hooks = assert(STABLE_WITNESS_DAG_HOOKS, "Missing stable witness DAG test hooks")
local feasibility = assert(STABLE_WITNESS_DAG_MODULE, "Missing stable witness DAG module")

local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end

local function make_state(index)
  local state = {
    recipe_source_epoch = "stable-witness-epoch",
    recipe_index = index or TEST_RECIPE_INDEX,
    visiting = {}, acquisition_memo = {}, stable_acquisition_memo = {}
  }
  feasibility.bind_state_context(state, TEST_COMPILER_CONTEXT)
  return state
end

local function source(kind)
  return {kind = kind or "minable-resource"}
end

local function recipe(machine, ingredients)
  return {kind = "recipe", machine = machine or {kind = "character-crafting"}, ingredients = ingredients}
end

local function placement(witness)
  return {kind = "machine-placement", acquisition = witness}
end

local function private_options(state)
  local options = {recipe_index = state.recipe_index}
  feasibility.enable_compiler_owned_witness_sharing(options)
  return options
end

local function classify_for_options(witness, options, state, metrics)
  local allowed = hooks.private_witness_memo_allowed(options, state)
  return hooks.stable_acquisition_witness_for_query(witness, allowed, metrics), allowed
end

local state = make_state()
TEST_PRODUCTION_STATE.route_witness_state = state
local options = private_options(state)
check(hooks.private_witness_memo_allowed(options, state),
  "Only the live compiler route-witness state may select the private walker")

-- The alias graph represents a shared machine/ingredient subroute that is
-- common across many candidate recipes. The old classifier is the direct
-- semantic oracle; the private path should establish each witness once.
local seed = source()
local shared = recipe(placement(seed), {seed, seed})
local alias_root = recipe({kind = "character-crafting"}, {})
for index = 1, 128 do alias_root.ingredients[index] = shared end
local alias_metrics = {}
local alias_result, alias_allowed = classify_for_options(alias_root, options, state, alias_metrics)
check(alias_allowed and alias_result == hooks.stable_acquisition_witness(alias_root),
  "Private plain DAG classification must equal the current classifier")
check(alias_metrics.witness_nodes == 3 and alias_metrics.completed_nodes == 3,
  "An aliased route must classify each witness node exactly once")
check(alias_metrics.completed_hits == 129 and not alias_metrics.fell_back,
  "An aliased route must reuse completed nodes without an external cache")

-- Ordinary shallow sources and hand-crafted recipes avoid allocating the DAG
-- maps altogether. False optional fields retain the current Lua truthiness.
local false_optional_source = {kind = "minable-resource", machine = false, ingredients = false}
local false_optional_metrics = {}
check(classify_for_options(false_optional_source, options, state, false_optional_metrics) == true
    and false_optional_metrics.fast_path and false_optional_metrics.witness_nodes == 0,
  "A shallow source with false optional fields must take the exact fast path")
local unsupported_metrics = {}
check(classify_for_options({kind = "unsupported"}, options, state, unsupported_metrics) == false
    and unsupported_metrics.fast_path,
  "An unsupported plain witness kind must retain its immediate false result")
local missing_machine_metrics = {}
check(classify_for_options({kind = "recipe"}, options, state, missing_machine_metrics) == false
    and missing_machine_metrics.fast_path,
  "A recipe without a machine must retain its immediate false result")
local unsupported_machine_metrics = {}
check(classify_for_options(recipe({kind = "unsupported-machine"}, {}), options, state,
    unsupported_machine_metrics) == false and unsupported_machine_metrics.fast_path,
  "An unsupported plain recipe machine must retain its immediate false result")
local small = recipe({kind = "character-crafting"}, {source(), source()})
local small_metrics = {}
check(classify_for_options(small, options, state, small_metrics)
    == hooks.stable_acquisition_witness(small) and small_metrics.fast_path
    and small_metrics.witness_nodes == 0,
  "A shallow hand-crafted source-leaf recipe must avoid DAG allocation")

-- A warm private query must inspect current values again: mutation of a
-- retained witness cannot be hidden by a pointer-keyed classification cache.
shared.machine.kind = "unsupported-machine"
local mutated_metrics = {}
local mutated_result = classify_for_options(alias_root, options, state, mutated_metrics)
check(mutated_result == false and mutated_result == hooks.stable_acquisition_witness(alias_root)
    and mutated_metrics.witness_nodes == 2,
  "A second private call must observe the current mutated graph")
shared.machine.kind = "machine-placement"

-- Public/context-invalid callers keep the exact old classifier and cannot
-- cause the private per-call metrics path to run.
local public_metrics = {}
local public_options = {recipe_index = TEST_RECIPE_INDEX}
local public_result, public_allowed = classify_for_options(alias_root, public_options, state, public_metrics)
check(not public_allowed and public_result == hooks.stable_acquisition_witness(alias_root)
    and next(public_metrics) == nil,
  "An ordinary public caller must retain the original classifier")
local foreign_state = make_state()
check(not hooks.private_witness_memo_allowed(options, foreign_state),
  "A foreign query state must not select the private walker")
local original_context = TEST_CURRENT_CONTEXT
TEST_CURRENT_CONTEXT = TEST_OTHER_CONTEXT
local context_metrics = {}
local context_result, context_allowed = classify_for_options(alias_root, options, state, context_metrics)
check(not context_allowed and context_result == hooks.stable_acquisition_witness(alias_root)
    and next(context_metrics) == nil,
  "A source-context change must bypass the private walker")
TEST_CURRENT_CONTEXT = original_context
local custom_options = private_options(state)
custom_options.source_witness = function() return nil end
check(not hooks.private_witness_memo_allowed(custom_options, state),
  "Custom witness callbacks must bypass private classification")
local diagnostic_options = private_options(state)
diagnostic_options.diagnostic_observer = {}
check(not hooks.private_witness_memo_allowed(diagnostic_options, state),
  "Diagnostic callers must bypass private classification")

-- Any metatable would make direct field access or ipairs externally defined.
-- Fall back to the established current-value classifier rather than treating
-- that structure as false or retaining a partial completed-node result.
local meta_root = setmetatable(source(), {})
local meta_root_metrics = {}
check(classify_for_options(meta_root, options, state, meta_root_metrics)
    == hooks.stable_acquisition_witness(meta_root) and meta_root_metrics.fell_back,
  "A metatable-backed witness node must fall back")
local meta_machine = recipe(setmetatable({kind = "character-crafting"}, {}), {})
local meta_machine_metrics = {}
check(classify_for_options(meta_machine, options, state, meta_machine_metrics)
    == hooks.stable_acquisition_witness(meta_machine) and meta_machine_metrics.fell_back,
  "A metatable-backed machine must fall back")
local meta_ingredients = recipe({kind = "character-crafting"}, setmetatable({}, {}))
local meta_ingredients_metrics = {}
check(classify_for_options(meta_ingredients, options, state, meta_ingredients_metrics)
    == hooks.stable_acquisition_witness(meta_ingredients) and meta_ingredients_metrics.fell_back,
  "A metatable-backed ingredient collection must fall back")
local meta_child = recipe({kind = "character-crafting"}, {setmetatable(source(), {})})
local meta_child_metrics = {}
check(classify_for_options(meta_child, options, state, meta_child_metrics)
    == hooks.stable_acquisition_witness(meta_child) and meta_child_metrics.fell_back,
  "A metatable-backed nested witness must fall back")

-- A structural cycle can only refuse stable-memo retention. The classifier's
-- result is never the route feasibility result, so this does not turn a
-- previously reached acquisition route into a rejected route.
local cycle = recipe({kind = "character-crafting"}, {})
cycle.ingredients[1] = cycle
local cycle_metrics = {}
check(classify_for_options(cycle, options, state, cycle_metrics) == false
    and cycle_metrics.refused_cycle and not cycle_metrics.fell_back,
  "A plain structural cycle must refuse only stable retention")

-- The completed-node cap bounds only dedup metadata. A large acyclic graph
-- remains exactly stable; nodes after the cap are traversed normally rather
-- than being classified false or unknown.
local wide = recipe({kind = "character-crafting"}, {})
for index = 1, 300 do wide.ingredients[index] = {kind = "minable-resource", ingredients = {}} end
local post_cap_alias = {kind = "minable-resource", ingredients = {}}
for index = 301, 428 do wide.ingredients[index] = post_cap_alias end
local wide_metrics = {}
check(classify_for_options(wide, options, state, wide_metrics) == true
    and wide_metrics.completed_nodes == 256 and wide_metrics.witness_nodes == 429
    and wide_metrics.completed_hits == 0,
  "A graph beyond the completed-node cap must retain full exact classification")

-- Unshared structures establish the same answer. The private walk avoids no
-- cache and uses the shallow source-leaf fast path, which makes the alias
-- result a sharing benefit instead of an accidental policy shortcut.
local unshared = recipe({kind = "character-crafting"}, {})
for index = 1, 128 do unshared.ingredients[index] = source() end
local unshared_metrics = {}
check(classify_for_options(unshared, options, state, unshared_metrics)
    == hooks.stable_acquisition_witness(unshared)
    and unshared_metrics.fast_path and unshared_metrics.witness_nodes == 0
    and unshared_metrics.completed_hits == 0,
  "Unshared graphs must preserve the current classification")
local non_leaf = recipe({kind = "character-crafting"}, {recipe({kind = "character-crafting"}, {})})
local non_leaf_metrics = {}
check(classify_for_options(non_leaf, options, state, non_leaf_metrics)
    == hooks.stable_acquisition_witness(non_leaf) and not non_leaf_metrics.fast_path
    and non_leaf_metrics.witness_nodes == 2,
  "A non-leaf ingredient must retain exact DAG classification")
local mixed = recipe({kind = "character-crafting"}, {source(), recipe({kind = "character-crafting"}, {})})
local mixed_metrics = {}
check(classify_for_options(mixed, options, state, mixed_metrics)
    == hooks.stable_acquisition_witness(mixed) and not mixed_metrics.fast_path
    and mixed_metrics.witness_nodes == 3,
  "A mixed leaf/non-leaf collection must not receive the shallow fast answer")

-- Broad acyclic comparison guards optional/invalid shapes as well as ordinary
-- recipe, placement and capture paths. No persistent cache is involved.
math.randomseed(43020261013)
local function random_plain(depth)
  if depth == 0 then
    if math.random(1, 4) == 1 then return {kind = "unknown"} end
    return source()
  end
  local flavor = math.random(1, 6)
  if flavor == 1 then return {kind = "unknown"} end
  if flavor == 2 then return source() end
  local ingredients = {}
  for index = 1, math.random(0, 3) do ingredients[index] = random_plain(depth - 1) end
  if flavor == 3 then return recipe({kind = "character-crafting"}, ingredients) end
  if flavor == 4 then return recipe(placement(random_plain(depth - 1)), ingredients) end
  if flavor == 5 then
    return recipe({kind = "machine-capture", launcher = random_plain(depth - 1),
      ammunition = random_plain(depth - 1)}, ingredients)
  end
  return {kind = "minable-resource", machine = placement(random_plain(depth - 1)),
    ingredients = ingredients}
end
for index = 1, 1000 do
  local witness = random_plain(4)
  check(classify_for_options(witness, options, state)
      == hooks.stable_acquisition_witness(witness),
    "Private/plain equivalence mismatch at generated witness " .. index)
end

local function benchmark(classifier, witness, iterations)
  local start = os.clock()
  for _ = 1, iterations do classifier(witness) end
  return os.clock() - start
end
local small_old_seconds = benchmark(hooks.stable_acquisition_witness, small, 5000)
local small_private_seconds = benchmark(function(witness)
  return hooks.stable_acquisition_witness_for_query(witness, true)
end, small, 5000)
local alias_old_seconds = benchmark(hooks.stable_acquisition_witness, alias_root, 250)
local alias_private_seconds = benchmark(function(witness)
  return hooks.stable_acquisition_witness_for_query(witness, true)
end, alias_root, 250)
local unshared_old_seconds = benchmark(hooks.stable_acquisition_witness, unshared, 250)
local unshared_private_seconds = benchmark(function(witness)
  return hooks.stable_acquisition_witness_for_query(witness, true)
end, unshared, 250)

print("MIR-PRIVATE-STABLE-WITNESS-DAG-PASS " .. assertions)
return {
  assertions = assertions,
  alias_nodes = alias_metrics.witness_nodes,
  alias_hits = alias_metrics.completed_hits,
  unshared_nodes = unshared_metrics.witness_nodes,
  wide_nodes = wide_metrics.witness_nodes,
  small_old_seconds = small_old_seconds,
  small_private_seconds = small_private_seconds,
  alias_old_seconds = alias_old_seconds,
  alias_private_seconds = alias_private_seconds,
  unshared_old_seconds = unshared_old_seconds,
  unshared_private_seconds = unshared_private_seconds
}
