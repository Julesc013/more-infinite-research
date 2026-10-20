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
-- Target adapters own phase reporting; the common qualifier owns the decision.
local f200_science = require("prototypes.mir.planner.science")
check(f200_science.phase_diagnostic_fields(nil) == nil,
  "F200 explicitly has no science-phase reporting fields")
local f210_science = assert(loadfile(source_root .. "/prototypes/mir/planner/science.lua"))()
local phase_fields = f210_science.phase_diagnostic_fields({
  policy_id = "phase-policy", status = "normalized", removed_packs = {"old-pack"},
  requested_packs = {"request-pack"}, retained_required_packs = {"required-pack"}
})
check(fingerprint.canonical(phase_fields) == fingerprint.canonical({
  science_phase_policy_id = "phase-policy", science_phase_policy_status = "normalized",
  science_phase_removed_packs = "old-pack", science_phase_requested_packs = "request-pack",
  science_phase_required_packs = "required-pack"
}), "Common phase reporting preserves all five exact F210 fields")
check(not pcall(f210_science.phase_diagnostic_fields, nil),
  "F210 phase reporting refuses a missing science decision")

-- Exercise merge_fields(nil, nonempty_native_fields) through the actual common
-- qualifier. Keep the synthetic owner out of the ordinary catalogue context.
local native_owner = "mir452-fixture-native-laboratory-speed-1"
data.raw.technology[native_owner] = {
  type = "technology", name = native_owner, enabled = true, max_level = "infinite",
  prerequisites = {"production-science-pack"},
  effects = {{type = "laboratory-speed", modifier = 0.1}},
  unit = {count = 100, time = 30, ingredients = {{"automation-science-pack", 1}}}
}
Context.with_active(Context.new(), function()
  local qualifier = require("prototypes.mir.planner.stream_compiler.qualify")
  local descriptor = require("prototypes.mir.domain.streams.descriptor")
  local row = qualifier.plan("mir452_native_phase_probe", descriptor.normalize("mir452_native_phase_probe", {
    icon_item = "iron-plate", science_packs = roles, adopt_exact_native_effect_owner = true,
    direct_effects = {
      {type = "laboratory-speed", modifier = 0.1},
      {type = "worker-robot-battery", modifier = 0.1}
    }
  }))
  check(row.action == "emit" and row.reason == "direct_effect"
    and #row.fields.effects == 1 and row.fields.effects[1].type == "worker-robot-battery",
    "Mixed native coverage retains exactly the unowned direct effect")
  local details = row.diagnostics
  check(details.native_effect_owners == native_owner and details.owners == native_owner
    and type(details.native_effect_policy) == "string"
    and details.native_effect_covered_identities ~= ""
    and details.native_effect_emitted_identities ~= "",
    "F200 nil phase fields do not suppress following native-owner diagnostics")
  check(row.science_phase_policy == nil and details.science_phase_policy_id == nil
    and details.science_phase_policy_status == nil and details.science_phase_removed_packs == nil
    and details.science_phase_requested_packs == nil and details.science_phase_required_packs == nil,
    "The common qualifier preserves F200's absent phase metadata")
end)
data.raw.technology[native_owner] = nil

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

  local function draft_fingerprints(change)
    local input = deepcopy(draft_fixture_row)
    change(input)
    local draft = generation_plan.prepare({input}, {source_fingerprints = {}})
    local preparations = generation_plan.assert_trusted_draft(draft)
    return technology_design.preparation_fingerprint(preparations[draft.rows[1]], draft.rows[1]),
      draft.plan_fingerprint, draft
  end

  local baseline_preparation, baseline_plan, baseline_draft = draft_fingerprints(function() end)
  check(next(baseline_draft.source_fingerprints) == nil,
    "Compact preparation controls do not rely on global source fingerprints")
  local compact_preparation_cases = {
    {"fields", function(row) row.fields.effects[1].change = 0.2 end},
    {"spec", function(row) row.spec.migration_policy = "draft-material-control" end},
    {"materialization", function(row)
      row.materialization = {kind = "continuation", base_technology = "research-speed-1",
        chain_key = "draft-material-control"}
    end},
    {"identity authority", function(row) row.identity_authority = "draft-material-control" end},
    {"direct effects", function(row) row.direct_effects = not row.direct_effects end}
  }
  for _, case in ipairs(compact_preparation_cases) do
    local preparation, plan_fingerprint, draft = draft_fingerprints(case[2])
    check(preparation ~= baseline_preparation and plan_fingerprint ~= baseline_plan
      and next(draft.source_fingerprints) == nil,
      "Compact preparation material binds authored " .. case[1] .. " semantics")
  end

  local function adoption_fingerprints(expected_count)
    return draft_fingerprints(function(row)
      row.fields.count = nil
      row.adoption = {expected_snapshot = {unit = {count = expected_count}}}
    end)
  end
  local adoption_preparation, adoption_plan, adoption_draft = adoption_fingerprints(101)
  local changed_adoption_preparation, changed_adoption_plan, changed_adoption_draft = adoption_fingerprints(102)
  check(adoption_preparation ~= changed_adoption_preparation and adoption_plan ~= changed_adoption_plan
    and next(adoption_draft.source_fingerprints) == nil
    and next(changed_adoption_draft.source_fingerprints) == nil,
    "Compact preparation material binds adopted expected count when authored fields omit it")

  local gate_contract = require("prototypes.mir.domain.technology.gate")
  local inherited_plan_cases = {
    {"source", function(row) row.source = "draft-material-source" end},
    {"provider ids", function(row) row.provider_ids = {"draft-material-provider"} end},
    {"family ids", function(row) row.family_ids = {"draft-material-family"} end},
    {"reason", function(row) row.reason = "draft-material-reason" end},
    {"target profile", function(row) row.target_profile_fingerprint = "draft-material-target" end},
    {"technology risk", function(row) row.technology_risk = {kind = "draft-material-risk"} end},
    {"diagnostics", function(row) row.diagnostics = {draft_material = true} end},
    {"gates", function(row)
      row.gates.effect_valid = gate_contract.passed("draft-material-gate", {changed = true})
    end}
  }
  for _, case in ipairs(inherited_plan_cases) do
    local preparation, plan_fingerprint, draft = draft_fingerprints(case[2])
    check(preparation == baseline_preparation and plan_fingerprint ~= baseline_plan
      and next(draft.source_fingerprints) == nil,
      "GenerationDraft row authority binds inherited " .. case[1] .. " semantics")
  end

  do
    local target_line = require("prototypes.mir.platform.factorio.target_line")
    local qualify = require("prototypes.mir.planner.stream_compiler.qualify")
    local registry = require("prototypes.mir.streams.registry")
    local prior = target_line.supports.legacy_numeric_research_cost
    target_line.supports.legacy_numeric_research_cost = true
    local descriptor = require("prototypes.mir.domain.streams.descriptor")
    local cases = {
      {"research_iron", registry.get("research_iron")},
      {"mir452_numeric_crafting_probe", descriptor.normalize("mir452_numeric_crafting_probe", {
        icon_item = "iron-plate", science_packs = roles,
        direct_effects = {{type = "character-crafting-speed", modifier = 0.1}}
      })}
    }
    for _, case in ipairs(cases) do
      local key = case[1]
      local input = qualify.plan(key, case[2])
      check(input.action == "emit", "Numeric-cost control uses an actual admitted " .. key .. ":" .. tostring(input.reason))
      local draft = generation_plan.prepare({input})
      local handles = generation_plan.assert_trusted_draft(draft)
      -- The planner row and its graph projection must agree on the actual
      -- numeric target cost before any technology reaches emission.
      local projection = technology_design.prepared_graph_projection(handles[input], input)
      check(input.fields.count_formula == nil and input.fields.count == 8000,
        "Numeric target row carries its actual first-level cost")
      check(projection.unit.count == 8000 and projection.unit.count_formula == nil,
        "Numeric graph projection agrees with its source row")
      check(input.fields.cost_model.count_formula ~= nil,
        "The full progression cost model remains available")
      local final = generation_plan.materialize_draft(draft)
      check(final.rows[1].fields.count == 8000 and final.rows[1].technology_design ~= nil,
        "Complete public numeric plan retains its design and exact cost")
      local changed = {}
      for k, v in pairs(input) do changed[k] = v end
      changed.fields = deepcopy(input.fields)
      changed.fields.count = 8001
      check(not pcall(technology_design.prepared_graph_projection, handles[input], changed),
        "Strict preparation rejects a changed numeric cost")
      for _, invalid in ipairs({0, -1, 0.5, math.huge, '8000'}) do
        local bad = deepcopy(input)
        bad.fields.count = invalid
        check(not pcall(generation_plan.prepare, {bad}),
          "Numeric row rejects invalid cost " .. tostring(invalid))
      end
      local missing = deepcopy(input)
      missing.fields.count = nil
      check(not pcall(generation_plan.prepare, {missing}), "Missing both cost forms is rejected")
      local ambiguous = deepcopy(input)
      ambiguous.fields.count_formula = ambiguous.fields.cost_model.count_formula
      check(not pcall(generation_plan.prepare, {ambiguous}), "Two cost representations are rejected")
    end
    target_line.supports.legacy_numeric_research_cost = prior
  end

  local plan = compiler.compile(context)
  local input_snapshot = plan.compiler_input.compilation_snapshot
  local snapshot_contract = require("prototypes.mir.domain.compiler.compilation_snapshot")
  local exported_snapshot = snapshot_contract.snapshot(input_snapshot, {full = true})
  local original_inventory = fingerprint.canonical(input_snapshot.effect_target_inventory)
  exported_snapshot.effect_target_inventory.recipe = {}
  check(fingerprint.canonical(input_snapshot.effect_target_inventory) == original_inventory,
    "Mutating an exported snapshot cannot change the shared planning target inventory")
  check(not pcall(snapshot_contract.verify_untrusted, exported_snapshot),
    "An imported snapshot with a changed target inventory fails independent verification")
  local original_recipe = data.raw.recipe["iron-plate"]
  data.raw.recipe["iron-plate"] = nil
  check(not pcall(effect_safety.assert_current_target_inventory,
    context:service("effect_target_inventory")),
    "Removing an actual target remains detectable at the mutation boundary")
  data.raw.recipe["iron-plate"] = original_recipe
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
  local initial_base = ((plan.compiler_input or {}).compilation_snapshot or {}).base_continuation_inputs or {}
  local initial_operations = initial_base.operations or {}
  local final_operations = plan.base_extension_operations or {}
  check(#initial_operations > 0 and #final_operations > 0
    and initial_operations[1].technology_design ~= nil and final_operations[1].technology_design ~= nil,
    "The input snapshot retains its bound base design while the final graph result is fully bound")
  for _, operation in ipairs(final_operations) do
    local expected_design = technology_design.from_base_extension_operation(operation)
    local prototype = technology_design.prototype_projection(operation.technology_design, {validated = true})
    local expected_prototype = deepcopy(prototype)
    expected_prototype.type = "technology"
    check(fingerprint.canonical(operation.technology_design) == fingerprint.canonical(expected_design)
      and fingerprint.canonical(expected_prototype) == fingerprint.canonical(operation.technology),
      "Final accepted base operation binds exact post-graph design and prototype semantics")
    local initial_before = fingerprint.canonical(initial_operations[1].technology_design)
    if #prototype.effects > 0 then prototype.effects[1].modifier = 99; prototype.effects[1].change = 99 end
    check(fingerprint.canonical(initial_operations[1].technology_design) == initial_before,
      "Final base prototype projection cannot mutate the preserved input-snapshot design")
  end
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

  -- P17 owns final rows only after graph qualification.  The real ordinary
  -- compiler result supplies the input here; isolated rows exercise the
  -- compact private handoff and every exported complete-record boundary.
  local p17_actual_plan = emitted_context:state_snapshot("compilation_plan")
  local p17_ordinary
  for _, row in ipairs((p17_actual_plan.stream_plan or {}).rows or {}) do
    if row.stream_key == "research_iron" then p17_ordinary = row; break end
  end
  check(p17_ordinary and p17_ordinary.action == "emit"
    and p17_ordinary.gates.prerequisites_acyclic.evaluator == "technology-graph",
    "P17 ordinary final ownership starts from the post-graph emitted row")
  local p17_work_counts = emitted_context:state_view("compiler_telemetry").counters
  check(counts.rows == 115
    and p17_work_counts.full_record_copy_count == 0
    and p17_work_counts.technology_design_full_copies == 0,
    "P17's complete ordinary compiler run retains zero full-record and Design copies for every final row"
      .. " rows=" .. tostring(counts.rows)
      .. " full_record_copies=" .. tostring(p17_work_counts.full_record_copy_count)
      .. " design_full_copies=" .. tostring(p17_work_counts.technology_design_full_copies))

  local p17_input = deepcopy(p17_ordinary)
  p17_input.gates.target_supported.p17_unknown = {nested = {captured = true}}
  p17_input.technology_design = technology_design.from_generation_row(p17_input)
  p17_input.technology_design.provenance.fields["ownership.action"].p17_unknown = {
    nested = {captured = true}
  }
  local p17_owner = generation_plan.new({source_fingerprints = {
    p17 = {nested = {captured = true}}
  }})
  p17_owner:add_owned_derived(p17_input)
  check(next(p17_input) == nil,
    "P17 consumes the compiler-owned post-graph row after its transfer into the private Plan owner")
  local p17_view = p17_owner:finalize():artifact_view()
  check(p17_view.rows[1].gates == nil and p17_view.rows[1].technology_design == nil,
    "P17 stores compact final row handles only in its trusted internal Plan view")

  local p17_first_export = generation_plan.export_artifact(p17_view)
  local p17_first_row = p17_first_export.rows[1]
  check(p17_first_row.gates.prerequisites_acyclic.evaluator == "technology-graph"
    and p17_first_row.gates.target_supported.p17_unknown.nested.captured == true
    and p17_first_row.technology_design.provenance.fields["ownership.action"].p17_unknown.nested.captured == true,
    "P17 expands complete post-graph Gate and Design provenance at export")
  p17_first_row.gates.target_supported.evidence.p17_export_mutation = {caller = true}
  p17_first_row.technology_design.provenance.fields["ownership.action"].p17_unknown.nested.captured = false
  p17_first_export.source_fingerprints.p17.nested.captured = false
  p17_first_export.validation_summary.action_counts.emit = 999
  local p17_second_export = generation_plan.export_artifact(p17_view)
  check(p17_second_export.rows[1].gates.target_supported.evidence.p17_export_mutation == nil
    and p17_second_export.rows[1].technology_design.provenance.fields["ownership.action"].p17_unknown.nested.captured == true
    and p17_second_export.source_fingerprints.p17.nested.captured == true
    and p17_second_export.validation_summary.action_counts.emit == 1,
    "P17 row, metadata, and summary export mutations cannot reach private ownership")
  -- Public Plan:add is the supported mutable import boundary. It deep-copies
  -- the caller row, unlike the compiler-owned consumed transfer above.
  -- Use an unmodified ordinary public record for the public import path. The
  -- P17 internal row above carries deliberate provenance additions and is
  -- consumed, so it is not an external untrusted-input fixture.
  local p17_public_input = deepcopy(p17_ordinary)
  local p17_public_owner = generation_plan.new({source_fingerprints = {
    p17_public = {nested = {captured = true}}
  }})
  p17_public_owner:add(p17_public_input)
  p17_public_input.gates.target_supported.evidence.p17_public_producer_mutation = {after_add = true}
  p17_public_input.technology_design.design.ownership.value.action = "p17-tampered-public-action"
  p17_public_input.technology_design.provenance.fields["ownership.action"].p17_public_mutation = {
    nested = {after_add = true}
  }
  local p17_public_export = p17_public_owner:finalize():artifact()
  check(p17_public_export.rows[1].gates.target_supported.evidence.p17_public_producer_mutation == nil
    and p17_public_export.rows[1].technology_design.design.ownership.value.action ~= "p17-tampered-public-action"
    and p17_public_export.rows[1].technology_design.provenance.fields["ownership.action"].p17_public_mutation == nil,
    "P17 supported public Plan:add deep admission isolates mutable producer rows")

  local p17_forged_external = generation_plan.export_artifact(p17_view)
  p17_forged_external.rows[1].gates.target_supported.evidence.p17_forged_external = true
  check(not pcall(compilation_plan.finalize, p17_forged_external, {}, {
    effect_target_inventory = emitted_context:service("effect_target_inventory")
  }), "P17 forged external schema-3 rows re-enter through untrusted Gate admission")

  -- The same owner boundary also covers an existing native technology patch,
  -- including its complete expected snapshot rather than an emit-only shape.
  local p17_adopt = deepcopy(p17_ordinary)
  local p17_native_owner = "p17-owned-native-owner"
  p17_adopt.action, p17_adopt.reason, p17_adopt.technology_name = "adopt", p17_native_owner, nil
  local p17_expected_snapshot = {
    name = p17_native_owner,
    effects = deepcopy(p17_adopt.fields.effects),
    prerequisites = deepcopy(p17_adopt.fields.prerequisites),
    unit = {
      ingredients = deepcopy(p17_adopt.fields.ingredients),
      count_formula = p17_adopt.fields.count_formula,
      count = p17_adopt.fields.count,
      time = p17_adopt.fields.research_time
    },
    max_level = p17_adopt.fields.max_level,
    localised_name = deepcopy(p17_adopt.fields.localised_name),
    localised_description = deepcopy(p17_adopt.fields.localised_description),
    icon = p17_adopt.fields.icon,
    icon_size = p17_adopt.fields.icon_size,
    icons = deepcopy(p17_adopt.fields.icons),
    order = p17_adopt.fields.order,
    level = p17_adopt.fields.level,
    enabled = p17_adopt.fields.enabled,
    hidden = p17_adopt.fields.hidden,
    upgrade = p17_adopt.fields.upgrade
  }
  p17_adopt.adoption = {
    schema = 2, owner = p17_native_owner, operation = "fixture-patch",
    configured_fields = {}, effects = deepcopy(p17_adopt.fields.effects),
    input_snapshot = deepcopy(p17_expected_snapshot), expected_snapshot = deepcopy(p17_expected_snapshot)
  }
  p17_adopt.adoption.input_fingerprint = fingerprint.of(p17_adopt.adoption.input_snapshot)
  p17_adopt.technology_design = technology_design.from_generation_row(p17_adopt)
  p17_adopt.adoption.output_fingerprint = p17_adopt.technology_design.prototype_fingerprint
  p17_adopt.technology_design = technology_design.from_generation_row(p17_adopt)
  local p17_adopt_owner = generation_plan.new()
  p17_adopt_owner:add_owned_derived(p17_adopt)
  check(next(p17_adopt) == nil,
    "P17 consumes compiler-owned native patch rows after private final transfer")
  local p17_adopt_view = p17_adopt_owner:finalize():artifact_view()
  local p17_adopt_export = generation_plan.export_artifact(p17_adopt_view)
  check(p17_adopt_view.rows[1].gates == nil and p17_adopt_export.rows[1].action == "adopt"
    and p17_adopt_export.rows[1].adoption.owner == p17_native_owner
    and type(p17_adopt_export.rows[1].technology_design.gates) == "table",
    "P17 native patch rows retain compact internal identity and complete export")

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
Context.with_active(emitted_context, function()
  local compilation_plan = require("prototypes.mir.planner.compilation_plan")
  -- Accepted sanitizer output is structural only.  These opponents prove every
  -- terminal base decision rebinds a complete design before it becomes a public
  -- candidate or operation.
  local target_inventory = emitted_context:service("effect_target_inventory")
  local function final_base_candidate(artifact, key)
    for _, candidate in ipairs((artifact.technology_catalog or {}).base_candidates or {}) do
      if candidate.key == key then return candidate end
    end
  end
  local collision_operation = base_binding_source({
    {type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1}
  })
  local collision = compilation_plan.finalize(emitted_context:state_view("compilation_plan").stream_plan,
    {collision_operation}, {effect_target_inventory = target_inventory})
  local collision_candidate = final_base_candidate(collision, collision_operation.key)
  check(collision_candidate and collision_candidate.reason == "covered_by_planned_operation"
    and collision_candidate.technology_design ~= nil
    and technology_design.verify_untrusted(collision_candidate.technology_design),
    "Combined ownership omission binds the complete rejected base candidate after its terminal decision")
  local graph_operation = base_binding_source({
    {type = "laboratory-speed", modifier = 0.2}
  })
  graph_operation.key = "graph-deferred-base-control"
  graph_operation.manifest_id = "base-continuation/graph-deferred-base-control"
  graph_operation.technology_name = "graph-deferred-base-control-infinite"
  graph_operation.technology.name = graph_operation.technology_name
  graph_operation.technology.prerequisites = {"missing-base-graph-control"}
  local graph_rejected = compilation_plan.finalize(emitted_context:state_view("compilation_plan").stream_plan,
    {graph_operation}, {effect_target_inventory = target_inventory})
  local graph_candidate = final_base_candidate(graph_rejected, graph_operation.key)
  check(graph_candidate and graph_candidate.reason == "prerequisite_missing"
    and graph_candidate.technology_design ~= nil
    and technology_design.verify_untrusted(graph_candidate.technology_design)
    and graph_candidate.technology_design.gates.prerequisites_acyclic.passed == false,
    "Graph rejection binds the complete failed base candidate only after the graph decision")
  local policy_row
  for _, source_row in ipairs(emitted_context:state_view("compilation_plan").stream_plan.rows) do
    if type(source_row.fields) == "table" then policy_row = deepcopy(source_row); break end
  end
  check(policy_row ~= nil, "Policy opponent requires an existing emitted stream row")
  policy_row.action = "skip"
  policy_row.reason = "covered_by_existing_infinite_native_modifier"
  policy_row.stream_key = "weapon-policy-deferred-base-control"
  policy_row.manifest_id = "weapon-policy-deferred-base-control"
  policy_row.technology_name = "weapon-policy-deferred-base-control"
  policy_row.fields.effects = {{type = "gun-speed", ammo_category = "bullet", modifier = 0.1}}
  policy_row.spec.direct_effects = deepcopy(policy_row.fields.effects)
  policy_row.diagnostics = {
    owners = "external-native-owner",
    native_effect_covered_categories = "bullet"
  }
  policy_row.technology_design = technology_design.from_generation_row(policy_row)
  local policy_stream = deepcopy(emitted_context:state_view("compilation_plan").stream_plan)
  table.insert(policy_stream.rows, policy_row)
  local policy_operation = base_binding_source({
    {type = "gun-speed", ammo_category = "bullet", modifier = 0.1}
  })
  policy_operation.key = "weapon-shooting-speed"
  policy_operation.manifest_id = "base-continuation/weapon-policy-deferred-base-control"
  policy_operation.technology_name = "weapon-policy-deferred-base-control-infinite"
  policy_operation.technology.name = policy_operation.technology_name
  local prior_ammo_categories = data.raw["ammo-category"]
  data.raw["ammo-category"] = {bullet = {type = "ammo-category", name = "bullet"}}
  local policy_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory").capture()
  local policy_rejected = compilation_plan.finalize(policy_stream,
    {policy_operation}, {effect_target_inventory = policy_inventory})
  data.raw["ammo-category"] = prior_ammo_categories
  local policy_candidate = final_base_candidate(policy_rejected, policy_operation.key)
  check(policy_candidate and policy_candidate.reason == "covered_by_existing_infinite_native_modifier"
    and policy_candidate.technology_design ~= nil
    and technology_design.verify_untrusted(policy_candidate.technology_design)
    and policy_candidate.technology_design.gates.effect_valid.passed == false,
    "Native weapon policy binds the complete failed base candidate after its terminal coverage decision")

  -- A partial native overlap must retain the unowned category, then bind its
  -- final TechnologyDesign only after policy, ownership and graph decisions.
  local partial_operation = base_binding_source({
    {type = "gun-speed", ammo_category = "bullet", modifier = 0.1},
    {type = "gun-speed", ammo_category = "rocket", modifier = 0.2}
  })
  partial_operation.key = "weapon-shooting-speed"
  partial_operation.manifest_id = "base-continuation/weapon-policy-partial-base-control"
  partial_operation.technology_name = "weapon-policy-partial-base-control-infinite"
  partial_operation.technology.name = partial_operation.technology_name
  partial_operation.technology_design = technology_design.from_base_extension_operation(partial_operation)
  partial_operation.technology = technology_design.prototype_projection(
    partial_operation.technology_design, {validated = true})
  partial_operation.technology.type = "technology"
  local partial_source_fingerprint = fingerprint.canonical(partial_operation)
  local partial_stream = deepcopy(emitted_context:state_view("compilation_plan").stream_plan)
  table.insert(partial_stream.rows, deepcopy(policy_row))
  local prior_partial_ammo_categories = data.raw["ammo-category"]
  data.raw["ammo-category"] = {
    bullet = {type = "ammo-category", name = "bullet"},
    rocket = {type = "ammo-category", name = "rocket"}
  }
  local partial_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory").capture()
  local partial = compilation_plan.finalize(partial_stream, {partial_operation},
    {effect_target_inventory = partial_inventory})
  data.raw["ammo-category"] = prior_partial_ammo_categories
  local partial_final
  for _, operation in ipairs(partial.base_extension_operations or {}) do
    if operation.key == partial_operation.key then partial_final = operation end
  end
  local partial_candidate = final_base_candidate(partial, partial_operation.key)
  local partial_input = (((partial.compiler_input or {}).compilation_snapshot or {})
    .base_continuation_inputs or {}).operations[1]
  local partial_input_projection = partial_input and partial_input.technology_design
    and technology_design.prototype_projection(partial_input.technology_design, {validated = true})
  local partial_expected = partial_final and technology_design.from_base_extension_operation(partial_final)
  local partial_projection = partial_final and technology_design.prototype_projection(
    partial_final.technology_design, {validated = true})
  if partial_projection then partial_projection.type = "technology" end
  check(partial_final and partial_candidate and partial_candidate.action == "create"
    and #partial_final.technology.effects == 1
    and partial_final.technology.effects[1].ammo_category == "rocket"
    and partial_final.planned_policy == "weapon-speed-overlap-resolved"
    and fingerprint.canonical(partial_final.technology_design) == fingerprint.canonical(partial_expected)
    and fingerprint.canonical(partial_final.technology) == fingerprint.canonical(partial_projection)
    and partial_candidate.design_fingerprint == partial_final.technology_design.design_fingerprint,
    "Partial native weapon coverage retains the unowned category and binds the exact accepted terminal design")
  check(partial_final and fingerprint.canonical(partial_operation) == partial_source_fingerprint
    and partial_input_projection and #partial_input_projection.effects == 2
    and partial_input_projection.effects[1].ammo_category == "bullet"
    and partial_input_projection.effects[2].ammo_category == "rocket"
    and partial_final.technology_design.design_fingerprint
      ~= partial_operation.technology_design.design_fingerprint,
    "Partial native weapon filtering preserves the full source/input design without aliasing its final design")

end)

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
local legacy_structural = deepcopy(legacy_operations)
legacy_structural[1].technology_design = nil
check(fingerprint.canonical(candidate_operations) == fingerprint.canonical(legacy_structural)
  and fingerprint.canonical(candidate_integrity) == fingerprint.canonical(legacy_integrity)
  and candidate_operations[1].technology_design == nil,
  "Base sanitation preserves the accepted structural operation and integrity evidence while deferring final design binding")
check(candidate_counts.base_design_constructions == 0
  and candidate_counts.base_design_constructions == legacy_counts.base_design_constructions - 2
  and candidate_counts.fingerprint_calls < legacy_counts.fingerprint_calls,
  "Base sanitation avoids both discarded pre-graph TechnologyDesign bindings and their fingerprints")
check(candidate_source_fingerprint == fingerprint.of(candidate_source)
  and candidate_operations[1].technology.type == "technology"
  and #candidate_operations[1].technology.effects == 1
  and candidate_integrity.removed_effect_count == 1,
  "Base sanitation retains the copied structural projection while leaving source effects unchanged")
candidate_operations[1].technology.effects[1].change = 99
check(candidate_source.technology.effects[1].change == 0.1,
  "Base sanitation does not share its deferred structural projection with the source operation")
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
do
  -- The former executor sequence is an independent full-journal oracle. The
  -- new owner must bind the actual capture, not merely reuse expected digests.
  local old = mutation_journal.new(one_plan)
  fingerprint.reset_metrics()
  old:assert_before(operation, before)
  old:record(operation, before, after, "applied", nil, {skip_precheck = true, return_entry = false})
  local old_metrics = fingerprint.metrics()
  local owned = mutation_journal.new(one_plan)
  local captured = deepcopy(before)
  local captures, applied = 0, 0
  fingerprint.reset_metrics()
  local returned = owned:execute(operation, function()
    captures = captures + 1
    return captures == 1 and captured or after
  end, function(actual_operation)
    check(actual_operation == operation, "Execution retains the exact admitted operation")
    applied = applied + 1
    captured.changed_during_mutation = true
    return "actual-emitter-result"
  end)
  local owned_metrics = fingerprint.metrics()
  check(owned_metrics.fingerprint_calls == old_metrics.fingerprint_calls - 1
      and owned_metrics.canonical_calls == old_metrics.canonical_calls - 1,
    "Owned execution eliminates one complete before-state encoding per operation")
  check(captures == 2 and applied == 1 and returned == "actual-emitter-result",
    "Owned execution captures both actual states and invokes emission once")
  check(fingerprint.canonical(owned:finalize()) == fingerprint.canonical(old:finalize()),
    "Owned execution preserves full journal bytes and isolates before-state aliases")
  local exported = owned:snapshot()
  exported.entries[1].before_snapshot.changed_export = true
  check(owned:snapshot().entries[1].before_snapshot.changed_export == nil,
    "Owned execution retains defensive full snapshot exports")
  rejected(function() owned:execute(operation, function() return before end, function() end) end,
    "MutationJournal is finalized")
  for _, failure in ipairs({"precondition", "postcondition", "mutation"}) do
    local journal = mutation_journal.new(one_plan)
    local reads, writes = 0, 0
    rejected(function()
      journal:execute(operation, function()
        reads = reads + 1
        if failure == "precondition" or (failure == "postcondition" and reads == 2) then return {} end
        return reads == 1 and before or after
      end, function()
        writes = writes + 1
        if failure == "mutation" then error("controlled-emitter-failure") end
      end)
    end, failure == "mutation" and "mutation-error" or failure .. "-mismatch")
    local result = journal:finalize({allow_failed = true})
    check(result.terminal_counts.failed == 1 and result.missing_operation_count == 0,
      failure .. " failure remains an actual failed terminal record")
    check(reads == (failure == "precondition" and 1 or 2)
        and writes == (failure == "precondition" and 0 or 1),
      failure .. " failure preserves before/after capture and mutation boundaries")
  end
end
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
do
  -- Exercise the real patch executor and adoption transaction as well as the
  -- ordinary create operations already executed above. No emitter is mocked.
  local native_contract = require("prototypes.mir.domain.native_owner.contract")
  local design_contract = require("prototypes.mir.domain.technology.technology_design")
  local row
  for _, candidate in ipairs(emitted_context:state_view("compilation_plan").stream_plan.rows) do
    if candidate.action == "emit" then row = deepcopy(candidate); break end
  end
  check(row ~= nil, "Native patch control starts from a real admitted stream")
  local owner = "mir-owned-mutation-native-control"
  local expected = native_contract.snapshot(data.raw.technology[row.technology_name])
  expected.name = owner
  local input = deepcopy(expected)
  input.unit.count_formula = "50*L+1"
  local prototype = deepcopy(input)
  prototype.type = "technology"
  data.raw.technology[owner] = prototype
  row.action = "adopt"
  row.technology_name = nil
  row.adoption = {owner = owner, key = row.stream_key, operation = "configure_native_owner",
    configured_fields = {"unit"}, input_snapshot = input, expected_snapshot = expected,
    input_fingerprint = fingerprint.of(input), output_fingerprint = fingerprint.of(expected)}
  row.technology_design = design_contract.from_generation_row(row)
  local snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot").new({
    stream_inputs = {rows = {row}}, base_continuation_inputs = {operations = {}}
  })
  local compiled = require("prototypes.mir.planner.compiler").compile(snapshot,
    require("prototypes.mir.domain.compiler.policy_snapshot").new({}))
  local patch_plan = compiled.transformation_plan
  check(#patch_plan.operations == 1 and patch_plan.operations[1].action == "patch",
    "Actual planner admits the native patch control")
  local journal = mutation_journal.new(patch_plan)
  Context.with_active(Context.new(), function()
    require("prototypes.mir.emit.technology_operation_executor").apply_plan(patch_plan, journal)
  end)
  local result = journal:finalize()
  check(result.complete and result.terminal_counts.applied == 1
      and fingerprint.of(native_contract.snapshot(prototype)) == row.adoption.output_fingerprint,
    "Real native patch emission satisfies the independently captured postcondition")
  check(fingerprint.canonical(result.entries[1].before_snapshot) == fingerprint.canonical(input)
      and fingerprint.canonical(result.entries[1].after_projection) == fingerprint.canonical(expected),
    "Real patch journal preserves both actual native snapshots")
  data.raw.technology[owner] = nil
end
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
