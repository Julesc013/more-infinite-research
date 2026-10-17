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
-- Real base-continuation input: this finite upstream research-speed chain is
-- admitted by the same planner that supplies production base operations.
data.raw.technology["research-speed-1"] = {
  type = "technology", name = "research-speed-1", prerequisites = {"production-science-pack"},
  effects = {{type = "laboratory-speed", modifier = 0.1}},
  unit = {count = 200, time = 60, ingredients = {{"automation-science-pack", 1}, {"production-science-pack", 1}}}
}
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
local counts, emitted_plan, emitted_journal, emitted_context, draft_fixture_row
Context.with_active(Context.new(), function()
  local context = Context.current()
  local effect_safety = require("prototypes.mir.emit.effect_safety")
  local input_ledger, target_inventory = effect_safety.sanitize_all_technology_effects({pass = "input"})
  context:set_service("effect_target_inventory", target_inventory)
  context:record_artifact("input_sanitation_ledger", input_ledger)
  local stream_compiler = require("prototypes.mir.planner.stream_compiler")
  local generation_plan = require("prototypes.mir.planner.generation_plan")
  local technology_design = require("prototypes.mir.domain.technology.technology_design")
  local draft = stream_compiler.compile_view(context)
  check(generation_plan.is_draft(draft) and context:state_view("generation_plan") == nil,
    "Pre-graph handoff remains private rather than publishing an incomplete GenerationPlan")
  local draft_iron
  for _, row in ipairs(draft.rows) do
    if row.stream_key == "research_iron" then draft_iron = row end
  end
  check(draft_iron and draft_iron.technology_design == nil,
    "Ordinary authored iron does not construct its discarded pre-graph TechnologyDesign")
  draft_fixture_row = deepcopy(draft_iron)
  check(not pcall(generation_plan.assert_trusted_artifact, draft)
    and not pcall(generation_plan.assert_trusted_draft, deepcopy(draft)),
    "Drafts cannot masquerade as final plans and copied drafts do not retain private authority")
  local public_plan = stream_compiler.latest_artifact(context)
  local pregraph_iron
  for _, row in ipairs(public_plan.rows) do
    if row.stream_key == "research_iron" then pregraph_iron = row.technology_design end
  end
  check(public_plan.schema == 3 and pregraph_iron ~= nil
    and public_plan.record_type == nil and context:state_view("generation_plan") == nil,
    "Explicit inspection materializes the complete existing public pre-graph plan contract")
  check(fingerprint.canonical(stream_compiler.compile(context)) == fingerprint.canonical(public_plan),
    "Explicit compile and latest-artifact inspection retain the same complete public plan")
  check(not pcall(require("prototypes.mir.planner.compilation_plan").finalize,
    deepcopy(draft), {}, {effect_target_inventory = target_inventory}),
    "The final compiler refuses a copied draft before consuming private preparations")
  local preparations = generation_plan.assert_trusted_draft(draft)
  local isolated_projection = technology_design.prepared_graph_projection(preparations[draft_iron], draft_iron)
  isolated_projection.effects[1].change = 123
  check(technology_design.prepared_graph_projection(preparations[draft_iron], draft_iron).effects[1].change == 0.1,
    "Graph projection exports cannot mutate the private preparation")
  local forged_row = {}
  for key, value in pairs(draft_iron) do forged_row[key] = value end
  forged_row.fields = deepcopy(draft_iron.fields)
  forged_row.fields.effects[1].change = 123
  check(not pcall(technology_design.prepared_graph_projection, preparations[draft_iron], forged_row),
    "A preparation refuses changed raw effect semantics before graph qualification")
  local malformed_row = deepcopy(draft_iron)
  malformed_row.spec.automatic_family = {creation_maturity = "not-a-valid-maturity"}
  check(not pcall(technology_design.prepare_generation_row, malformed_row),
    "Preparation retains the constructor's malformed-maturity validation")
  local plan = compiler.compile(context)
  local iron
  for _, row in ipairs(plan.stream_plan.rows) do
    if row.stream_key == "research_iron" then iron = row end
  end
  check(iron and iron.action == "emit", "Existing authored iron family must be admitted")
  local expected_final_design = technology_design.with_qualification(pregraph_iron, iron)
  check(fingerprint.canonical(iron.technology_design) == fingerprint.canonical(expected_final_design),
    "Single final binding equals the independently materialized pre-graph plus qualification path")
  check(context:state_view("generation_plan").schema == 3
    and stream_compiler.latest_artifact(context).record_type == nil,
    "Only the complete final GenerationPlan is installed before publication and emission")
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
  emitted_context = context
end)

Context.with_active(emitted_context, function()
  local generation_plan = require("prototypes.mir.planner.generation_plan")
  local technology_design = require("prototypes.mir.domain.technology.technology_design")
  local compilation_plan = require("prototypes.mir.planner.compilation_plan")
  local function compare_draft_case(change)
    local input = deepcopy(draft_fixture_row)
    change(input)
    local ordinary_row = deepcopy(input)
    ordinary_row.technology_design = technology_design.from_generation_row(ordinary_row)
    local ordinary = generation_plan.new()
    ordinary:add_owned_derived(ordinary_row)
    local draft = generation_plan.prepare({input})
    local options = {effect_target_inventory = emitted_context:service("effect_target_inventory")}
    local expected = compilation_plan.finalize(ordinary:finalize():artifact_view(), {}, options)
    local actual = compilation_plan.finalize(draft, {}, options)
    check(fingerprint.canonical(actual.stream_plan.rows) == fingerprint.canonical(expected.stream_plan.rows),
      "Draft sanitation/graph decision preserves the complete full-path final rows")
    return actual.stream_plan.rows[1], actual
  end
  local sanitized = compare_draft_case(function(row)
    row.fields.effects[#row.fields.effects + 1] = {type = "unlock-recipe", recipe = "missing-draft-control-recipe"}
  end)
  check(sanitized.action == "emit" and #sanitized.fields.effects == 1
    and #sanitized.effect_integrity.removed == 1
    and #sanitized.technology_design.design.effects.value == 1,
    "Sanitation re-prepares retained effect semantics before graph and final binding")
  local rejected_row, rejected_plan = compare_draft_case(function(row)
    row.fields.prerequisites = {"missing-draft-control-prerequisite"}
  end)
  check(rejected_row.action == "skip" and rejected_row.reason == "prerequisite_missing"
    and rejected_row.technology_design.materialization.kind == "diagnose"
    and #rejected_plan.technology_catalog.candidates[1].alternatives == 2,
    "Graph rejection retains a complete final skip design and explicit safe diagnostic")
  local erased = compare_draft_case(function(row)
    row.fields.effects = {{type = "unlock-recipe", recipe = "missing-draft-control-recipe"}}
  end)
  check(erased.action == "skip" and erased.reason == "no_valid_effect_targets"
    and erased.technology_design.materialization.kind == "diagnose",
    "Zero retained effects preserve the full rejection contract rather than binding stale preparation")
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

-- Base continuation effects are pruned before their final TechnologyDesign is
-- bound.  Keep the former two-bind sequence as a local oracle so the focused
-- structural/binding split cannot change a public operation or rejection.
local compilation_model = require("prototypes.mir.planner.compilation_plan.model")
local base_classify = require("prototypes.mir.planner.base_continuations.classify")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local technology_effects = require("prototypes.mir.integrity.technology_effects")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local target_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory").capture()
local function legacy_sanitize_base_operations(base_plan, inventory)
  local operations, removed_count, skipped_count, rejected_candidates = {}, 0, 0, {}
  for _, source_operation in ipairs(base_plan or {}) do
    local operation = compilation_model.normalized_base_operation(source_operation)
    local kept, removed = technology_effects.sanitize_effects(
      (operation.technology and operation.technology.effects) or {},
      "CompilationPlan " .. tostring(operation.technology_name), "generated", inventory)
    removed_count = removed_count + #removed
    operation.technology.effects = kept
    if #kept > 0 and technology_effects.has_possible_research_effects(kept) then
      operation.gates.effect_valid = gate_contract.passed(
        "effect-contracts",
        {#removed > 0 and "effect-contracts:sanitized" or "effect-contracts:all-targets-exist"})
      operation.technology_design = technology_design.from_base_extension_operation(operation)
      table.insert(operations, operation)
    else
      skipped_count = skipped_count + 1
      local reason = #removed > 0 and "no_valid_effect_targets" or "no_base_extension_effects"
      local evidence = #removed > 0 and "effect-contracts:all-targets-missing"
        or "effect-contracts:no-base-effects"
      if #kept > 0 then
        reason = "zero_base_extension_effects"
        evidence = "effect-contracts:zero-base-effect-changes"
      end
      operation.gates.effect_valid = gate_contract.failed("effect-contracts", reason, {evidence})
      operation.technology_design = technology_design.from_base_extension_operation(operation)
      table.insert(rejected_candidates, {
        candidate_id = "base-continuation/" .. tostring(operation.key),
        key = operation.key,
        action = "reject",
        reason = reason,
        gates = operation.gates,
        technology_design = operation.technology_design,
        candidate_fingerprint = fingerprint.of({key = operation.key, reason = reason, gates = operation.gates})
      })
    end
  end
  return operations, {
    removed_effect_count = removed_count,
    skipped_base_extension_count = skipped_count,
    rejected_candidates = rejected_candidates
  }
end
local function base_binding_source(effects)
  return {
    schema = 1,
    operation = "emit_base_extension",
    key = "approved-family-binding-control",
    manifest_id = "base-continuation/approved-family-binding-control",
    base_technology_name = "production-science-pack",
    technology_name = "approved-family-binding-control-infinite",
    technology = {
      type = "technology",
      name = "approved-family-binding-control-infinite",
      localised_name = {"technology-name.approved-family-binding-control"},
      localised_description = {"technology-description.approved-family-binding-control"},
      prerequisites = {"production-science-pack"},
      effects = deepcopy(effects),
      unit = {count_formula = "1000*2^(L-1)", ingredients = {{"automation-science-pack", 1}}, time = 60},
      max_level = "infinite",
      upgrade = true,
      level = 1
    },
    gates = base_classify.accepted_gate_vector(
      "approved-family-binding-control", "approved-family-binding-control-infinite")
  }
end
local retained_and_missing_effects = {
  {type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1},
  {type = "unlock-recipe", recipe = "missing-approved-family-binding-control"}
}
local original_from_base = technology_design.from_base_extension_operation
local original_fingerprint_of = fingerprint.of
local binding_counts = {base_design_constructions = 0, fingerprint_calls = 0}
technology_design.from_base_extension_operation = function(...)
  binding_counts.base_design_constructions = binding_counts.base_design_constructions + 1
  return original_from_base(...)
end
fingerprint.of = function(...)
  binding_counts.fingerprint_calls = binding_counts.fingerprint_calls + 1
  return original_fingerprint_of(...)
end
local legacy_operations, legacy_integrity = legacy_sanitize_base_operations(
  {base_binding_source(retained_and_missing_effects)}, target_inventory)
local legacy_counts = deepcopy(binding_counts)
binding_counts.base_design_constructions, binding_counts.fingerprint_calls = 0, 0
local candidate_source = base_binding_source(retained_and_missing_effects)
local candidate_source_fingerprint = original_fingerprint_of(candidate_source)
local candidate_operations, candidate_integrity = compilation_model.sanitize_base_operations(
  {candidate_source}, target_inventory)
local candidate_counts = deepcopy(binding_counts)
technology_design.from_base_extension_operation = original_from_base
fingerprint.of = original_fingerprint_of
check(fingerprint.canonical(candidate_operations) == fingerprint.canonical(legacy_operations)
  and fingerprint.canonical(candidate_integrity) == fingerprint.canonical(legacy_integrity),
  "Base sanitation binds the same accepted operation and integrity evidence after effect pruning")
check(candidate_counts.base_design_constructions == legacy_counts.base_design_constructions - 1
  and candidate_counts.fingerprint_calls < legacy_counts.fingerprint_calls,
  "Base sanitation avoids the discarded pre-sanitization TechnologyDesign and its fingerprints")
check(candidate_source_fingerprint == fingerprint.of(candidate_source)
  and candidate_operations[1].technology.type == "technology"
  and #candidate_operations[1].technology.effects == 1
  and candidate_integrity.removed_effect_count == 1,
  "Base sanitation retains the copied canonical projection while leaving source effects unchanged")
candidate_operations[1].technology.effects[1].change = 99
check(candidate_source.technology.effects[1].change == 0.1
  and technology_design.prototype_projection(candidate_operations[1].technology_design, {validated = true}).effects[1].change == 0.1,
  "Base sanitation does not share its returned projection with source or trusted design ownership")
local rejected_effects = {{type = "unlock-recipe", recipe = "missing-approved-family-binding-control"}}
local legacy_rejected, legacy_rejected_integrity = legacy_sanitize_base_operations(
  {base_binding_source(rejected_effects)}, target_inventory)
local candidate_rejected, candidate_rejected_integrity = compilation_model.sanitize_base_operations(
  {base_binding_source(rejected_effects)}, target_inventory)
check(fingerprint.canonical(candidate_rejected) == fingerprint.canonical(legacy_rejected)
  and fingerprint.canonical(candidate_rejected_integrity) == fingerprint.canonical(legacy_rejected_integrity)
  and #candidate_rejected == 0 and candidate_rejected_integrity.rejected_candidates[1].reason == "no_valid_effect_targets",
  "Base sanitation preserves rejected-candidate design and evidence after all targets are removed")
local incomplete_gates = base_binding_source(retained_and_missing_effects)
incomplete_gates.gates.effect_valid = nil
rejected(function() compilation_model.sanitize_base_operations({incomplete_gates}, target_inventory) end,
  "Technology hard-gate vector is missing")
local malformed_effects = base_binding_source(retained_and_missing_effects)
malformed_effects.technology.effects = "not-a-table"
check(not pcall(function() compilation_model.sanitize_base_operations({malformed_effects}, target_inventory) end),
  "Base sanitation refuses malformed non-table effects")
rejected(function() compilation_model.sanitize_base_operations(
  {base_binding_source(retained_and_missing_effects)}, nil) end,
  "Effect target validation requires an explicit target inventory")
local missing_technology = base_binding_source(retained_and_missing_effects)
missing_technology.technology = nil
rejected(function() compilation_model.sanitize_base_operations({missing_technology}, target_inventory) end,
  "TechnologyDesign base continuation operation is required.")
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
