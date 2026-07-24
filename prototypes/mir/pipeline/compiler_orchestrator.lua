local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local compilation_plan = require("prototypes.mir.planner.compilation_plan")
local stream_compiler = require("prototypes.mir.planner.stream_compiler")
local base_continuations = require("prototypes.mir.planner.base_continuations")
local base_continuation_executor = require("prototypes.mir.emit.base_continuation_executor")
local stream_executor = require("prototypes.mir.emit.stream_executor")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local compiler_input = require("prototypes.mir.domain.compiler.compiler_input")
local compiler_evidence = require("prototypes.mir.domain.evidence.compiler_evidence")
local environment_adapter = require("prototypes.mir.platform.factorio.environment_identity")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local public_artifacts = require("prototypes.mir.report.public_compiler_artifacts")
local effect_target_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory")
local compilation_snapshot_adapter = require("prototypes.mir.pipeline.compilation_snapshot_adapter")
local policy_snapshot_adapter = require("prototypes.mir.pipeline.policy_snapshot_adapter")
local compilation_snapshot_contract = require("prototypes.mir.domain.compiler.compilation_snapshot")
local pure_compiler = require("prototypes.mir.planner.compiler")
local mutation_journal = require("prototypes.mir.domain.compiler.mutation_journal")
local family_resolver = require("prototypes.mir.families.resolver")
local execution_mode = require("prototypes.mir.domain.compiler.execution_mode")
local compiler_result_contract = require("prototypes.mir.domain.compiler.compiler_result")

local M = {}

local function now()
  return os and type(os.clock) == "function" and os.clock() or 0
end

local function memory_bytes()
  return collectgarbage and collectgarbage("count") * 1024 or 0
end

local function record_work_volume()
  local fingerprint_metrics = fingerprint.metrics()
  for counter, value in pairs({
    fingerprint_calls = fingerprint_metrics.fingerprint_calls,
    canonicalization_calls = fingerprint_metrics.canonical_calls,
    canonical_bytes_total = fingerprint_metrics.canonical_bytes,
    canonical_serializations_over_one_mib = fingerprint_metrics.serializations_over_one_mib,
    maximum_canonical_bytes = fingerprint_metrics.maximum_canonical_bytes
  }) do telemetry.observe_max(counter, value) end

  local trust_metrics = trusted_record.metrics()
  local registrations, untrusted, assertions, rejected, full_copies = 0, 0, 0, 0, 0
  for _, values in pairs(trust_metrics) do
    registrations = registrations + (values.registrations or 0)
    untrusted = untrusted + (values.untrusted_verifications or 0)
    assertions = assertions + (values.trusted_assertions or 0)
    rejected = rejected + (values.rejected_assertions or 0)
    full_copies = full_copies + (values.full_copies or 0)
  end
  for counter, value in pairs({
    trusted_record_registrations = registrations,
    trusted_untrusted_verifications = untrusted,
    trusted_assertions = assertions,
    trusted_rejected_assertions = rejected,
    trusted_assertion_canonicalizations = 0,
    catalog_snapshot_count = ((trust_metrics.TechnologyCatalog or {}).explicit_snapshots or 0),
    full_record_copy_count = full_copies,
    technology_design_full_copies = ((trust_metrics.TechnologyDesign or {}).full_copies or 0),
    gate_deep_verifications = ((trust_metrics.TechnologyGate or {}).untrusted_verifications or 0),
    technology_design_deep_verifications = ((trust_metrics.TechnologyDesign or {}).untrusted_verifications or 0),
    safety_qualification_deep_verifications = ((trust_metrics.SafetyQualification or {}).untrusted_verifications or 0),
    technology_candidate_deep_verifications = ((trust_metrics.TechnologyCandidate or {}).untrusted_verifications or 0),
    technology_catalog_deep_verifications = ((trust_metrics.TechnologyCatalog or {}).untrusted_verifications or 0),
    transformation_operation_deep_verifications = ((trust_metrics.TransformationOperation or {}).untrusted_verifications or 0),
    transformation_plan_deep_verifications = ((trust_metrics.TransformationPlan or {}).untrusted_verifications or 0)
  }) do telemetry.observe_max(counter, value) end
end

local function compile_active(context)
  local latest = context:state_view("compilation_plan")
  if latest then return latest end
  local compile_started = now()
  telemetry.start_phase("planning")
  local stream_plan = stream_compiler.compile_view(context)
  local base_plan, base_candidates = base_continuations.plan_all()
  local provider_inputs = family_resolver.snapshot()
  local policy_snapshot = policy_snapshot_adapter.capture(context)
  local input_snapshot = compilation_snapshot_adapter.capture({
    stream_inputs = {plan = stream_plan},
    base_continuation_inputs = {operations = base_plan, candidates = base_candidates},
    provider_inputs = provider_inputs,
    source_fingerprints = stream_plan.source_fingerprints
  })
  local environment = environment_adapter.current({
    effective_settings = policy_snapshot.effective_settings,
    policy_snapshot = policy_snapshot
  })
  local input_sources = deepcopy(stream_plan.source_fingerprints)
  input_sources.base_extension_plan = fingerprint.of(base_plan)
  local input = compiler_input.new({
    source_fingerprints = input_sources,
    compilation_snapshot = input_snapshot,
    policy_snapshot = policy_snapshot,
    runtime_environment = environment,
    input_sanitation_fingerprint = fingerprint.of(context:artifact("input_sanitation_ledger") or {})
  })
  latest = compilation_plan.finalize(stream_plan, base_plan, {
    compiler_input = input,
    base_candidates = base_candidates,
    input_sanitation_ledger = context:artifact("input_sanitation_ledger"),
    stream_plan_trusted = true,
    effect_target_inventory = effect_target_inventory.capture()
  })
  local qualification_started = now()
  local final_snapshot = compilation_snapshot_contract.qualify(input_snapshot, {
    stream_inputs = {plan = latest.stream_plan},
    base_continuation_inputs = {operations = latest.base_extension_operations,
      candidates = latest.technology_catalog.base_candidates},
    source_fingerprints = input_snapshot.source_fingerprints
  })
  for name, value in pairs({
    snapshot_prototype_bytes = input_snapshot.metrics.prototype_bytes_captured,
    snapshot_deep_copies = input_snapshot.metrics.deep_copy_count,
    snapshot_canonicalization_passes = input_snapshot.metrics.canonicalization_passes,
    snapshot_construction_milliseconds = (input_snapshot.metrics.construction_seconds or 0) * 1000,
    snapshot_peak_memory_bytes = input_snapshot.metrics.peak_memory_bytes,
    input_snapshot_bytes = input_snapshot.metrics.snapshot_bytes,
    qualification_snapshot_bytes = #fingerprint.canonical(compilation_snapshot_contract.snapshot(final_snapshot)),
    snapshot_reused_domains = final_snapshot.metrics.reused_domain_count,
    snapshot_copied_domains = final_snapshot.metrics.copied_domain_count,
    qualification_snapshot_construction_milliseconds = math.max(0, now() - qualification_started) * 1000,
    qualification_peak_memory_bytes = memory_bytes()
  }) do telemetry.observe_max(name, value or 0) end
  local pure_compilation = pure_compiler.compile(final_snapshot, policy_snapshot)
  if pure_compilation.status == "REVIEW_REQUIRED"
    and execution_mode.review_is_fatal(policy_snapshot.execution_mode, policy_snapshot.review_policy) then
    error("Pure compiler did not produce a fully qualified transformation plan: "
      .. tostring(pure_compilation.status), 2)
  end
  latest.compilation_snapshot_fingerprint = input_snapshot.snapshot_fingerprint
  latest.qualification_snapshot_fingerprint = final_snapshot.snapshot_fingerprint
  latest.policy_fingerprint = policy_snapshot.policy_fingerprint
  latest.pure_compilation = pure_compilation
  latest.transformation_plan = pure_compilation.transformation_plan
  latest.transformation_plan_fingerprint = pure_compilation.transformation_plan.plan_fingerprint
  context:set_state("compiler_input", input)
  context:set_state("compilation_snapshot", input_snapshot)
  context:set_state("qualification_snapshot", final_snapshot)
  context:set_state("policy_snapshot", policy_snapshot)
  context:set_state("pure_compilation", pure_compilation)
  context:set_state("compilation_plan", latest)
  context:set_state("technology_candidate_catalog", latest.technology_catalog)
  context:set_state("technology_qualifications", latest.technology_catalog.qualifications)
  context:set_state("compiler_result", latest.compiler_result)
  context:record_artifact("technology_candidate_catalog", latest.technology_catalog)
  stream_compiler.accept_artifact(latest.stream_plan, context, {trusted = true})
  record_work_volume()
  telemetry.finish_phase("planning")
  telemetry.observe_max("compiler_total_milliseconds", math.max(0, now() - compile_started) * 1000)
  return latest
end

function M.compile(context)
  context = context or compiler_context.current()
  return compiler_context.with_active(context, compile_active, context)
end

function M.apply_streams(context)
  context = context or compiler_context.current()
  local plan = M.compile(context)
  local journal = context:state_view("mutation_journal", function()
    return mutation_journal.new(plan.transformation_plan)
  end)
  stream_executor.apply(plan.stream_plan, plan.transformation_plan, journal)
end

function M.apply_base_extensions(context)
  context = context or compiler_context.current()
  local plan = M.compile(context)
  local journal = context:state_view("mutation_journal", function()
    return mutation_journal.new(plan.transformation_plan)
  end)
  base_continuation_executor.apply_plan(
    plan.base_extension_operations, plan.transformation_plan, journal)
end

function M.snapshot(context)
  local plan = M.compile(context)
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
  local plan = M.compile(context)
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

function M.publish(context)
  context = context or compiler_context.current()
  local plan = M.compile(context)
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
  telemetry.observe_max("context_state_keys", context:state_key_count())
  local public_evidence
  for _ = 1, 4 do
    record_work_volume()
    evidence_input.telemetry = telemetry.snapshot()
    public_evidence = public_artifacts.compiler_evidence(evidence_input)
    local evidence_bytes = public_artifacts.assert_byte_budget(public_evidence)
    telemetry.observe_max("compiler_evidence_public_bytes", evidence_bytes)
    local counters = telemetry.snapshot().counters
    telemetry.observe_max("public_artifact_total_bytes",
      (counters.generation_plan_public_bytes or 0)
      + (counters.technology_catalog_public_bytes or 0)
      + (counters.coverage_public_bytes or 0)
      + evidence_bytes)
  end
  record_work_volume()
  evidence_input.telemetry = telemetry.snapshot()
  public_evidence = public_artifacts.compiler_evidence(evidence_input)
  public_artifacts.assert_byte_budget(public_evidence)
  local internal_evidence = include_internal and compiler_evidence.build(evidence_input) or nil
  require("prototypes.mir.emit.compiler_evidence_adapter").publish(public_evidence, internal_evidence)
  return true
end

return M
