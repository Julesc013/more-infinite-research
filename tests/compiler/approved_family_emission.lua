-- Actual catalogue, qualifier and common emitter; independent expected output.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
data = {raw = {item = {}, recipe = {}, technology = {}, tool = {}, lab = {}}}
function data:extend(rows)
  for _, row in ipairs(rows) do
    self.raw[row.type] = self.raw[row.type] or {}
    self.raw[row.type][row.name] = row
  end
end
mods = {base = "2.0.77", ["more-infinite-research"] = "4.4.20000"}
settings = {startup = {}}
feature_flags = {}
log = function() end
for _, name in ipairs({"pack_production_reachability", "recipe_route_feasibility",
  "production_route_policy", "technology_researchability"}) do
  package.preload["prototypes.mir.capabilities.science_integration." .. name] = function()
    error("Retired production solver loaded: " .. name)
  end
end
local roles = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
data.raw.lab.lab = {type = "lab", name = "lab", inputs = roles}
data.raw.item.lab = {type = "item", name = "lab", place_result = "lab"}
data.raw.recipe.lab = {type = "recipe", name = "lab", enabled = true,
  results = {{type = "item", name = "lab", amount = 1}}}
data.raw.item["iron-plate"] = {type = "item", name = "iron-plate",
  icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64}
data.raw.item["iron-ore"] = {type = "item", name = "iron-ore"}
data.raw.recipe["iron-plate"] = {type = "recipe", name = "iron-plate", category = "smelting", enabled = true,
  ingredients = {{"iron-ore", 1}}, results = {{type = "item", name = "iron-plate", amount = 1}}}
for i, name in ipairs(roles) do
  data.raw.tool[name] = {type = "tool", name = name}
  data.raw.recipe[name] = {type = "recipe", name = name, enabled = false,
    ingredients = {{"iron-plate", 1}}, results = {{type = "item", name = name, amount = 1}}}
  data.raw.technology[name] = {type = "technology", name = name, prerequisites = {},
    effects = {{type = "unlock-recipe", recipe = name}},
    research_trigger = {type = "craft-item", item = "iron-plate", count = 1}}
  if i > 1 then
    data.raw.technology[name].research_trigger = nil
    data.raw.technology[name].prerequisites = {roles[i - 1]}
    data.raw.technology[name].unit = {count = 10, time = 10, ingredients = {{roles[i - 1], 1}}}
  end
end
local Context = require("prototypes.mir.pipeline.compiler_context")
local compiler = require("prototypes.mir.pipeline.compiler_orchestrator")
local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local name = "recipe-prod-research_iron-1"
local expected = {
  name = name, max_level = "infinite", time = 60, count_formula = "8000*2^(L-1)",
  ingredients = {"automation-science-pack:1", "chemical-science-pack:1", "logistic-science-pack:1", "production-science-pack:1"},
  prerequisites = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "production-science-pack"},
  effects = {{type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1}}
}
local function assert_preserved()
  local actual = data.raw.technology[name]
  assert(actual, "Established non-core technology is missing")
  local ingredients, prerequisites = {}, deepcopy(actual.prerequisites or {})
  for _, row in ipairs(actual.unit.ingredients) do
    ingredients[#ingredients + 1] = (row.name or row[1]) .. ":" .. tostring(row.amount or row[2])
  end
  table.sort(ingredients)
  table.sort(prerequisites)
  local projection = {name = actual.name, max_level = actual.max_level, time = actual.unit.time,
    count_formula = actual.unit.count_formula, ingredients = ingredients,
    prerequisites = prerequisites, effects = actual.effects}
  assert(fingerprint.of(projection) == fingerprint.of(expected), "Established iron definition changed")
end
local counts, emitted_plan, emitted_journal
Context.with_active(Context.new(), function()
  local context = Context.current()
  local effect_safety = require("prototypes.mir.emit.effect_safety")
  local input_ledger, target_inventory = effect_safety.sanitize_all_technology_effects({pass = "input"})
  context:set_service("effect_target_inventory", target_inventory)
  context:record_artifact("input_sanitation_ledger", input_ledger)
  local plan = compiler.compile(context)
  local iron
  for _, row in ipairs(plan.stream_plan.rows) do
    if row.stream_key == "research_iron" then iron = row end
  end
  check(iron and iron.action == "emit", "Existing authored iron family must be admitted")
  check(#plan.stream_plan.rows > 100, "Use the actual catalogue, not a replacement five-family catalogue")
  compiler.apply_streams(context)
  compiler.apply_base_extensions(context)
  local output_ledger = effect_safety.sanitize_all_technology_effects({
    pass = "output", target_inventory = target_inventory
  })
  effect_safety.assert_target_inventory_unchanged(context:artifact("input_sanitation_ledger"), output_ledger)
  effect_safety.assert_registered_technology_effects(target_inventory)
  context:record_artifact("output_sanitation_ledger", output_ledger)
  local replacement_journal = require("prototypes.mir.emit.technology_replacement").new_journal()
  context:set_state("technology_replacement_journal", replacement_journal)
  context:freeze_state("technology_replacement_journal")
  context:record_artifact("technology_graph_parity",
    require("prototypes.mir.emit.technology_graph_safety").assert_registered_technologies(plan, replacement_journal))
  compiler.assert_output(context)
  check(context:state_view("final_compiler_result").dimensions.execution == "APPLIED",
    "Actual contract checks consume reduced finalization evidence")
  assert_preserved()
  check(true, "Shared planner and emitter preserve independently specified iron behavior")
  local journal = context:state_view("mutation_journal")
  check(journal and journal.plan_fingerprint == plan.transformation_plan.plan_fingerprint,
    "The actual emission journal is bound to the actual common plan")
  local full_journal = journal:finalize({allow_failed = true})
  local expected_realized = {}
  for index, entry in ipairs(full_journal.entries) do
    expected_realized[index] = {
      operation_id = entry.operation_id,
      status = entry.status,
      after_fingerprint = entry.after_fingerprint
    }
  end
  local final_evidence = context:state_view("final_compiler_result").execution_evidence
  check(final_evidence.journal_fingerprint == full_journal.journal_fingerprint
    and final_evidence.executed_operation_count == #full_journal.entries
    and final_evidence.failed_operation_count == full_journal.terminal_counts.failed
    and final_evidence.realized_output_fingerprint == fingerprint.of(expected_realized),
    "Actual contract-check summary preserves the full journal evidence projection")
  counts = {rows = #plan.stream_plan.rows, operations = #plan.transformation_plan.operations}
  emitted_plan, emitted_journal = plan.transformation_plan, journal
end)

local mutation_journal = require("prototypes.mir.domain.compiler.mutation_journal")
local transformation_plan = require("prototypes.mir.domain.compiler.transformation_plan")
local transformation_operation = require("prototypes.mir.domain.compiler.transformation_operation")
local function stable_finalization(journal, result, complete, label)
  check(result.finalized == true and result.complete == complete, label .. " finalization state")
  local bytes = fingerprint.canonical(result)
  check(bytes == fingerprint.canonical(journal:snapshot())
    and bytes == fingerprint.canonical(journal:finalize()), label .. " stable frozen bytes")
  local another = journal:finalize()
  another.terminal_counts.applied = 999
  another.missing_operations[1] = "changed-returned-copy"
  another.violations.duplicate[1] = "changed-returned-copy"
  if another.entries[1] then another.entries[1].before_snapshot.changed_returned_copy = true end
  result.terminal_counts.failed = 999
  if result.entries[1] then result.entries[1].after_projection.changed_returned_copy = true end
  check(bytes == fingerprint.canonical(journal:snapshot())
    and bytes == fingerprint.canonical(journal:finalize()), label .. " defensive copies")
end
local function rejected(action, fragment)
  local ok, message = pcall(action)
  check(not ok and tostring(message):find(fragment, 1, true), "reject " .. fragment)
end
stable_finalization(emitted_journal, emitted_journal:finalize(), true, "actual emitted catalogue")
local function plan_for(operations)
  return transformation_plan.new({phase = "journal-finalization-control", execution_mode = "SAFE",
    compilation_snapshot_fingerprint = emitted_plan.compilation_snapshot_fingerprint,
    policy_fingerprint = emitted_plan.policy_fingerprint, operations = operations})
end
local empty = mutation_journal.new(plan_for({}))
local empty_result = empty:finalize()
check(empty_result.required_operation_count == 0 and #empty_result.entries == 0
  and empty_result.terminal_counts.applied == 0 and empty_result.terminal_counts.failed == 0,
  "empty plan retains exact terminal counts")
stable_finalization(empty, empty_result, true, "empty plan")
local operation = emitted_plan.operations[1]
local one_plan = plan_for({operation})
local before, after = operation.expected_before_snapshot, operation.expected_after_projection
local default_entry = mutation_journal.new(one_plan)
local returned_entry = default_entry:record(operation, before, after, "applied")
returned_entry.after_projection.changed_default_entry_copy = true
check(default_entry:snapshot().entries[1].after_projection.changed_default_entry_copy == nil,
  "Default record return remains a defensive entry copy")
local reduced_entry = mutation_journal.new(one_plan)
check(reduced_entry:record(operation, before, after, "applied", nil, {return_entry = false}) == nil,
  "Internal executor record can omit its discarded entry copy")
local reduced_finalization = reduced_entry:finalize({return_snapshot = false})
check(reduced_finalization.entries == nil
  and reduced_finalization.executed_operation_count == 1
  and reduced_finalization.failed_operation_count == 0
  and #reduced_finalization.realized_operations == 1
  and reduced_finalization.realized_operations[1].operation_id == operation.operation_id
  and reduced_finalization.realized_operations[1].after_fingerprint == operation.expected_after_fingerprint,
  "Reduced finalization preserves only contract-check evidence")
reduced_finalization.realized_operations[1].after_fingerprint = "changed-reduced-return"
check(reduced_entry:snapshot().entries[1].after_fingerprint == operation.expected_after_fingerprint
  and reduced_entry:finalize({return_snapshot = false}).realized_operations[1].after_fingerprint
    == operation.expected_after_fingerprint,
  "Reduced finalization return is isolated from the cached full snapshot")
local before_finalize_summary = mutation_journal.new(one_plan)
rejected(function() before_finalize_summary:publication_summary() end,
  "publication summary requires finalization")
local missing = mutation_journal.new(one_plan)
rejected(function() missing:finalize() end, "MutationJournal is incomplete or failed: missing=1")
local missing_result = missing:snapshot()
check(missing_result.missing_operation_count == 1 and missing_result.missing_operations[1] == operation.operation_id,
  "failed finalization freezes the exact missing operation before raising")
local missing_summary = missing:finalize({allow_failed = true, return_snapshot = false})
check(missing_summary.missing_operation_count == 1 and missing_summary.realized_operations[1] == nil,
  "Cached failed finalization still reports reduced missing evidence")
stable_finalization(missing, missing_result, false, "missing operation")
local failed = mutation_journal.new(one_plan)
rejected(function() failed:record(operation, before, {}, "applied") end, "postcondition-mismatch")
local failed_result = failed:finalize({allow_failed = true})
check(failed_result.terminal_counts.failed == 1 and failed_result.missing_operation_count == 0,
  "failed execution remains recorded instead of missing")
local reduced_failed = mutation_journal.new(one_plan)
rejected(function() reduced_failed:record(operation, before, {}, "applied", nil, {return_entry = false}) end,
  "postcondition-mismatch")
local reduced_failed_summary = reduced_failed:finalize({allow_failed = true, return_snapshot = false})
check(reduced_failed_summary.failed_operation_count == 1
  and reduced_failed_summary.realized_operations[1].status == "failed",
  "Discarded internal record return preserves failed journal evidence")
stable_finalization(failed, failed_result, false, "failed operation")
local duplicate = mutation_journal.new(one_plan)
duplicate:record(operation, before, after, "applied")
rejected(function() duplicate:record(operation, before, after, "applied") end, "more than once")
local duplicate_result = duplicate:finalize({allow_failed = true})
check(duplicate_result.duplicate_operation_count == 1 and #duplicate_result.entries == 1,
  "duplicate rejection retains the original applied operation")
stable_finalization(duplicate, duplicate_result, false, "duplicate operation")
local other = deepcopy(operation)
other.operation_id = operation.operation_id .. "/undeclared"
other = transformation_operation.new(other)
local undeclared = mutation_journal.new(one_plan)
rejected(function() undeclared:assert_operation(other) end, "undeclared operation")
local undeclared_result = undeclared:finalize({allow_failed = true})
check(undeclared_result.undeclared_operation_count == 1 and undeclared_result.missing_operation_count == 1,
  "undeclared rejection retains the planned missing operation")
stable_finalization(undeclared, undeclared_result, false, "undeclared operation")
local changed = deepcopy(operation)
changed.allowed_delta = {changed = true}
changed = transformation_operation.new(changed)
local out_of_plan = mutation_journal.new(one_plan)
rejected(function() out_of_plan:assert_operation(changed) end, "differs from its bound plan")
local out_of_plan_result = out_of_plan:finalize({allow_failed = true})
check(out_of_plan_result.out_of_plan_operation_count == 1 and out_of_plan_result.missing_operation_count == 1,
  "changed operation retains its bound-plan violation")
stable_finalization(out_of_plan, out_of_plan_result, false, "out-of-plan operation")
local emitted = data.raw.technology[name]
data.raw.technology[name] = nil
check(not pcall(assert_preserved), "The preservation oracle rejects deletion of non-core research")
data.raw.technology[name] = deepcopy(emitted)
data.raw.technology[name].effects[1].change = 0.2
check(not pcall(assert_preserved), "The preservation oracle rejects a changed effect")
data.raw.technology[name] = emitted
assert_preserved()
check(true, "Opposing controls restore their copied test output")
return {assertions = checks, rows = counts.rows, operations = counts.operations}
