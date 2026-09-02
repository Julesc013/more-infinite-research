local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local context_construction = require("prototypes.mir.pipeline.compiler_orchestrator.context_construction")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local compiler_result_contract = require("prototypes.mir.domain.compiler.compiler_result")
local telemetry = require("prototypes.mir.report.compiler_telemetry")

local M = {}

function M.snapshot(context)
  local plan = context_construction.compile(context)
  local current_result = context:state_view("compiler_result") or plan.compiler_result
  local snapshot = {
    schema = plan.schema,
    fingerprint = plan.fingerprint,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    semantic_fingerprint = plan.semantic_fingerprint,
    source_fingerprints = plan.source_fingerprints,
    compiler_input = plan.compiler_input,
    compiler_result = current_result,
    planned_compiler_result = plan.compiler_result,
    compilation_snapshot_fingerprint = plan.compilation_snapshot_fingerprint,
    qualification_snapshot_fingerprint = plan.qualification_snapshot_fingerprint,
    policy_fingerprint = plan.policy_fingerprint,
    transformation_plan = plan.transformation_plan,
    transformation_plan_fingerprint = plan.transformation_plan_fingerprint,
    mutation_journal = context:has_state("mutation_journal")
      and context:state_view("mutation_journal"):snapshot() or nil,
    technology_catalog = plan.technology_catalog,
    technology_catalog_fingerprint = plan.technology_catalog_fingerprint,
    input_sanitation_ledger = plan.input_sanitation_ledger,
    operations = plan.operations,
    stream_plan = plan.stream_plan,
    base_extension_operations = plan.base_extension_operations,
    validation_summary = plan.validation_summary,
    telemetry = telemetry.snapshot()
  }
  snapshot.telemetry_fingerprint = fingerprint.of(snapshot.telemetry)
  snapshot.run_fingerprint = fingerprint.of({
    qualification_fingerprint = snapshot.qualification_fingerprint,
    telemetry_fingerprint = snapshot.telemetry_fingerprint
  })
  return deepcopy(snapshot)
end

function M.assert_output(context)
  context = context or compiler_context.current()
  local plan = context_construction.compile(context)
  local output_validation = require("prototypes.mir.planner.output_validator").assert_compilation_artifact(
    plan,
    {designs_validated = true}
  )
  local journal = context:state_view("mutation_journal")
  if not journal then error("CompilerResult finalization requires a MutationJournal.", 2) end
  local finalized_journal = journal:finalize({allow_failed = true})
  local graph_parity = context:artifact("technology_graph_parity")
  local input_sanitation = plan.input_sanitation_ledger or {}
  local output_sanitation = context:artifact("output_sanitation_ledger") or {}
  local sanitation_passed = type(input_sanitation.sanitized_target_inventory_fingerprint) == "string"
    and input_sanitation.sanitized_target_inventory_fingerprint
      == output_sanitation.sanitized_target_inventory_fingerprint
  local realized = {}
  for _, entry in ipairs(finalized_journal.entries or {}) do
    table.insert(realized, {
      operation_id = entry.operation_id,
      status = entry.status,
      after_fingerprint = entry.after_fingerprint
    })
  end
  local evidence = {
    journal_fingerprint = finalized_journal.journal_fingerprint,
    executed_operation_count = #(finalized_journal.entries or {}),
    skipped_operation_count = 0,
    failed_operation_count = finalized_journal.terminal_counts.failed or 0,
    missing_operation_count = finalized_journal.missing_operation_count,
    duplicate_operation_count = finalized_journal.duplicate_operation_count,
    undeclared_operation_count = finalized_journal.undeclared_operation_count,
    out_of_plan_operation_count = finalized_journal.out_of_plan_operation_count,
    realized_output_fingerprint = fingerprint.of(realized),
    output_parity_fingerprint = fingerprint.of(output_validation or {}),
    graph_parity_fingerprint = fingerprint.of(graph_parity or {}),
    sanitation_parity_fingerprint = fingerprint.of({
      input = input_sanitation,
      output = output_sanitation,
      passed = sanitation_passed
    }),
    output_parity_passed = type(output_validation) == "table",
    graph_parity_passed = type(graph_parity) == "table" and graph_parity.valid == true,
    sanitation_parity_passed = sanitation_passed
  }
  local final_result = compiler_result_contract.finalize(plan.compiler_result, evidence)
  context:replace_epoch("compiler_result", final_result, context:state_epoch("compiler_result"))
  context:set_state("final_compiler_result", final_result)
  if final_result.dimensions.execution ~= "APPLIED" then
    error("CompilerResult finalization recorded failed execution evidence.", 2)
  end
  return true
end

return M
