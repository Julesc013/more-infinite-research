local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local context_construction = require("prototypes.mir.pipeline.compiler_orchestrator.context_construction")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local compiler_evidence = require("prototypes.mir.domain.evidence.compiler_evidence")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local public_artifacts = require("prototypes.mir.report.public_compiler_artifacts")
local execution_mode = require("prototypes.mir.domain.compiler.execution_mode")
local research_cost_compatibility = require("prototypes.mir.domain.research_cost.compatibility_slice")

local M = {}

local function maximum_level_policy(plan)
  local bindings = {}
  local function presentation(selected)
    if type(selected) == "number" and selected > 0
        and target_line.feature_enabled("scripted_techs") then
      return {
        mode = "finite-runtime-cap",
        internal_prototype_max_level = "infinite",
        show_levels_info = false,
        visible_when_disabled = true
      }
    end
    return {
      mode = "native-prototype-maximum",
      internal_prototype_max_level = selected,
      show_levels_info = true
    }
  end
  for _, row in ipairs(plan.stream_plan.rows or {}) do
    if row.action == "emit" then
      table.insert(bindings, {
        technology = row.technology_name,
        setting = "ips-max-level-" .. tostring(row.stream_key),
        selected = row.planned_max_level,
        source = "generated-stream",
        operation = "emit",
        presentation = presentation(row.planned_max_level)
      })
    elseif row.action == "adopt" and row.adoption then
      table.insert(bindings, {
        technology = row.adoption.owner,
        setting = "ips-max-level-" .. tostring(row.stream_key),
        selected = row.adoption.planned_max_level,
        source = "native-owner",
        operation = row.adoption.operation,
        presentation = presentation(row.adoption.planned_max_level)
      })
    end
  end
  for _, operation in ipairs(plan.base_extension_operations or {}) do
    table.insert(bindings, {
      technology = operation.technology_name,
      setting = "mir-max-level-" .. tostring(operation.key),
      selected = operation.planned_max_level,
      source = "base-continuation",
      operation = operation.operation,
      presentation = presentation(operation.planned_max_level)
    })
  end
  table.sort(bindings, function(left, right) return left.technology < right.technology end)
  return {
    schema = 2,
    kind = "MIRMaximumLevelPolicyV2",
    semantics = "absolute-highest-technology-level",
    bindings = bindings
  }
end

function M.publish(context)
  context = context or compiler_context.current()
  local plan = context_construction.compile(context)
  local final_result = context:state_view("final_compiler_result")
  if not final_result then error("Compiler artifacts cannot publish before CompilerResult finalization.", 2) end
  local mod_data = require("prototypes.mir.emit.mod_data")
  local include_internal = diagnostics.enabled()
    or execution_mode.include_full_diagnostics(plan.pure_compilation.execution_mode
      or context:execution_mode())
  local public_plan = public_artifacts.generation_plan(plan.stream_plan)
  local public_catalog = public_artifacts.technology_catalog(
    plan.technology_catalog, context:state_view("family_resolution") or {})
  local plan_public_bytes = public_artifacts.assert_byte_budget(public_plan)
  local catalog_public_bytes = public_artifacts.assert_byte_budget(public_catalog)
  telemetry.count("generation_plan_rows", #(plan.stream_plan.rows or {}))
  telemetry.count("generation_plan_public_bytes", plan_public_bytes)
  telemetry.count("technology_catalog_public_bytes", catalog_public_bytes)
  local design_count, design_bytes = 0, 0
  for _, row in ipairs(plan.stream_plan.rows or {}) do
    if row.technology_design then
      design_count = design_count + 1
      if include_internal then design_bytes = design_bytes + #fingerprint.canonical(row.technology_design) end
    end
  end
  telemetry.count("technology_design_count", design_count)
  telemetry.count("technology_design_canonical_bytes", design_bytes)
  mod_data.emit_generation_plan(public_plan)
  mod_data.emit_maximum_level_policy(maximum_level_policy(plan))
  mod_data.emit_technology_catalog(public_catalog)
  if include_internal then
    telemetry.count("generation_plan_internal_bytes", #fingerprint.canonical(plan.stream_plan))
    mod_data.emit_internal_generation_plan(plan.stream_plan)
    telemetry.count("technology_catalog_internal_bytes", #fingerprint.canonical(plan.technology_catalog))
    mod_data.emit_internal_technology_catalog(plan.technology_catalog)
  end
  local evidence_input = {
    compilation_plan_schema = plan.schema,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    compiler_input_fingerprint = plan.compiler_input.input_fingerprint,
    compiler_result = deepcopy(final_result),
    compiler_result_fingerprint = final_result.result_fingerprint,
    mutation_journal = context:state_view("mutation_journal"):snapshot(),
    technology_catalog_fingerprint = plan.technology_catalog_fingerprint,
    technology_graph_parity = context:artifact("technology_graph_parity"),
    provider_resolution = deepcopy(context:state_view("family_resolution") or {}),
    input_sanitation_ledger = deepcopy(plan.input_sanitation_ledger),
    output_sanitation_ledger = context:artifact("output_sanitation_ledger")
  }
  evidence_input.provider_decision_diagnostics = {}
  for _, row in ipairs((context:state_view("diagnostics") or {}).rows or {}) do
    if row.kind == "decision" and row.reason == "canonical_provider_decision_projection" then
      table.insert(evidence_input.provider_decision_diagnostics, deepcopy(row))
    end
  end
  if target_line.feature_enabled("productivity_family_adoption") then
    require("prototypes.mir.emit.transactions.productivity_family_adoption").emit_mod_data()
  end
  require("prototypes.mir.report.coverage").publish(context, {include_internal = include_internal})
  local research_cost_support = research_cost_compatibility.build({
    compiler_input = plan.compiler_input,
    compiler_result = final_result,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    stream_plan = plan.stream_plan,
    base_extension_operations = plan.base_extension_operations,
    current_target = target_line.factorio_version
  })
  research_cost_support = public_artifacts.research_cost_compatibility(research_cost_support)
  local research_cost_support_bytes = public_artifacts.assert_byte_budget(research_cost_support)
  telemetry.count("research_cost_support_public_bytes", research_cost_support_bytes)
  telemetry.observe_max("context_state_keys", context:state_key_count())
  local public_evidence
  for _ = 1, 4 do
    context_construction.record_work_volume()
    evidence_input.telemetry = telemetry.snapshot()
    public_evidence = public_artifacts.compiler_evidence(evidence_input)
    local evidence_bytes = public_artifacts.assert_byte_budget(public_evidence)
    telemetry.observe_max("compiler_evidence_public_bytes", evidence_bytes)
    local counters = telemetry.snapshot().counters
    telemetry.observe_max("public_artifact_total_bytes",
      (counters.generation_plan_public_bytes or 0)
      + (counters.technology_catalog_public_bytes or 0)
      + (counters.coverage_public_bytes or 0)
      + (counters.research_cost_support_public_bytes or 0)
      + evidence_bytes)
  end
  context_construction.record_work_volume()
  evidence_input.telemetry = telemetry.snapshot()
  public_evidence = public_artifacts.compiler_evidence(evidence_input)
  public_artifacts.assert_byte_budget(public_evidence)
  local internal_evidence = include_internal and compiler_evidence.build(evidence_input) or nil
  require("prototypes.mir.emit.research_cost_compatibility_adapter").publish(research_cost_support)
  require("prototypes.mir.emit.compiler_evidence_adapter").publish(public_evidence, internal_evidence)
  return true
end

return M
