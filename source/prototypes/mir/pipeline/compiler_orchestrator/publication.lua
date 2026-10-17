local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local context_construction = require("prototypes.mir.pipeline.compiler_orchestrator.context_construction")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local compiler_evidence = require("prototypes.mir.domain.evidence.compiler_evidence")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local public_artifacts = require("prototypes.mir.report.public_compiler_artifacts")
local execution_mode = require("prototypes.mir.domain.compiler.execution_mode")
local family_resolver = require("prototypes.mir.families.resolver")
local research_cost_compatibility = require("prototypes.mir.domain.research_cost.compatibility_slice")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

-- The bounded research-cost support artifact has admitted exact dispositions
-- only for Factorio 2.0 and 2.1.  Factorio-1 packages retain their reduced
-- research surface but do not emit a proof whose target contract they cannot
-- satisfy.  New target lines must be admitted here deliberately.
local RESEARCH_COST_SUPPORT_DISPOSITION_BY_TARGET = {
  ["2.1"] = "emit",
  ["2.0"] = "emit",
  ["1.1"] = "omit-unqualified",
  ["1.0"] = "omit-unqualified"
}

function M.publish(context)
  context = context or compiler_context.current()
  local plan = context_construction.compile(context)
  local final_result = context:state_view("final_compiler_result")
  if not final_result then error("Compiler artifacts cannot publish before CompilerResult finalization.", 2) end
  local mod_data = require("prototypes.mir.emit.mod_data")
  local publishes_mod_data = target_line.mod_data_supported()
  local include_internal = diagnostics.enabled()
    or execution_mode.include_full_diagnostics(plan.pure_compilation.execution_mode
      or context:execution_mode())
  -- Older engines retain the exact compiler-evidence log below, but have no
  -- mod-data consumer. Do not construct unused public or internal projections.
  if publishes_mod_data then
    local public_plan = public_artifacts.generation_plan(plan.stream_plan)
    local public_catalog = public_artifacts.technology_catalog(
      plan.technology_catalog, context:state_view("family_resolution") or {})
    local plan_public_bytes = public_artifacts.assert_byte_budget(public_plan)
    local catalog_public_bytes = public_artifacts.assert_byte_budget(public_catalog)
    telemetry.count("generation_plan_public_bytes", plan_public_bytes)
    telemetry.count("technology_catalog_public_bytes", catalog_public_bytes)
    mod_data.emit_generation_plan(public_plan)
    local maximum_level_policy = context_construction.maximum_level_policy(context)
    if maximum_level_policy then mod_data.emit_maximum_level_policy(maximum_level_policy) end
    mod_data.emit_technology_catalog(public_catalog)
    if include_internal then
      telemetry.count("generation_plan_internal_bytes", #fingerprint.canonical(plan.stream_plan))
      mod_data.emit_internal_generation_plan(plan.stream_plan)
      telemetry.count("technology_catalog_internal_bytes", #fingerprint.canonical(plan.technology_catalog))
      mod_data.emit_internal_technology_catalog(plan.technology_catalog)
    end
  end
  telemetry.count("generation_plan_rows", #(plan.stream_plan.rows or {}))
  local design_count, design_bytes = 0, 0
  for _, row in ipairs(plan.stream_plan.rows or {}) do
    if row.technology_design then
      design_count = design_count + 1
      if include_internal and publishes_mod_data then
        design_bytes = design_bytes + #fingerprint.canonical(row.technology_design)
      end
    end
  end
  telemetry.count("technology_design_count", design_count)
  telemetry.count("technology_design_canonical_bytes", design_bytes)
  local journal = context:state_view("mutation_journal")
  if not journal then error("Compiler artifacts cannot publish without a MutationJournal.", 2) end
  -- Public evidence reads a fixed projection of the finalized result and
  -- journal. Avoid copying operation snapshots, parity proofs, and developer
  -- decision rows unless the explicitly requested internal evidence consumes
  -- them below. The output sanitation ledger remains an exported report input,
  -- so it retains the Context defensive-copy boundary.
  local output_sanitation_ledger = context:artifact("output_sanitation_ledger")
  local evidence_input = {
    compilation_plan_schema = plan.schema,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    compiler_result = final_result,
    mutation_journal = journal:publication_summary(),
    input_sanitation_ledger = plan.input_sanitation_ledger,
    output_sanitation_ledger = output_sanitation_ledger
  }
  -- Keep the complete developer evidence input at the original publication
  -- boundary. Subsequent report publishers add diagnostic rows, so capturing
  -- it later would silently change the explicit internal artifact. Ordinary
  -- publication never enters this branch.
  local internal_evidence_input = nil
  if include_internal and publishes_mod_data then
    local provider_decision_diagnostics = {}
    for _, row in ipairs((context:state_view("diagnostics") or {}).rows or {}) do
      if row.kind == "decision" and row.reason == "canonical_provider_decision_projection" then
        table.insert(provider_decision_diagnostics, deepcopy(row))
      end
    end
    internal_evidence_input = {
      compilation_plan_schema = plan.schema,
      compilation_fingerprint = plan.compilation_fingerprint,
      qualification_fingerprint = plan.qualification_fingerprint,
      compiler_input_fingerprint = plan.compiler_input.input_fingerprint,
      compiler_result = final_result,
      compiler_result_fingerprint = final_result.result_fingerprint,
      mutation_journal = journal:snapshot(),
      technology_catalog_fingerprint = plan.technology_catalog_fingerprint,
      technology_graph_parity = context:artifact("technology_graph_parity"),
      input_sanitation_ledger = plan.input_sanitation_ledger,
      output_sanitation_ledger = output_sanitation_ledger,
      provider_decision_diagnostics = provider_decision_diagnostics
    }
  end
  if target_line.feature_enabled("productivity_family_adoption") then
    require("prototypes.mir.emit.transactions.productivity_family_adoption").emit_mod_data()
  end
  if publishes_mod_data then
    require("prototypes.mir.report.coverage").publish(context, {include_internal = include_internal})
  end
  local research_cost_disposition = RESEARCH_COST_SUPPORT_DISPOSITION_BY_TARGET[target_line.factorio_version]
  if not research_cost_disposition then
    error("Research-cost publication target is not admitted: " .. tostring(target_line.factorio_version), 2)
  end
  local research_cost_support
  if research_cost_disposition == "emit" then
    research_cost_support = research_cost_compatibility.build({
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
  end
  telemetry.observe_max("context_state_keys", context:state_key_count())
  -- Public evidence freezes telemetry before its own canonicalization and
  -- budget check. Reconstructing it to embed its own size repeats expensive
  -- work and makes the payload's telemetry depend on that reconstruction.
  context_construction.record_work_volume()
  evidence_input.telemetry = telemetry.snapshot()
  local public_evidence = public_artifacts.compiler_evidence(evidence_input)
  local evidence_bytes = public_artifacts.assert_byte_budget(public_evidence)
  if publishes_mod_data then
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
  local internal_evidence = nil
  if internal_evidence_input then
    -- Preserve the established timing of the resolver inspection: report
    -- publishers have completed before the explicit internal artifact reads it.
    internal_evidence_input.provider_resolution = family_resolver.inspection_snapshot()
    internal_evidence_input.telemetry = evidence_input.telemetry
    internal_evidence = compiler_evidence.build(internal_evidence_input)
  end
  if research_cost_support then
    require("prototypes.mir.emit.research_cost_compatibility_adapter").publish(research_cost_support)
  end
  require("prototypes.mir.emit.compiler_evidence_adapter").publish(public_evidence, internal_evidence)
  return true
end

return M
