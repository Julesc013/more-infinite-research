local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local compilation_plan = require("prototypes.mir.planner.compilation_plan")
local stream_compiler = require("prototypes.mir.planner.stream_compiler")
local base_continuations = require("prototypes.mir.planner.base_continuations")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local compiler_input = require("prototypes.mir.domain.compiler.compiler_input")
local environment_adapter = require("prototypes.mir.platform.factorio.environment_identity")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local effect_target_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory")
local compilation_snapshot_adapter = require("prototypes.mir.pipeline.compilation_snapshot_adapter")
local policy_snapshot_adapter = require("prototypes.mir.pipeline.policy_snapshot_adapter")
local compilation_snapshot_contract = require("prototypes.mir.domain.compiler.compilation_snapshot")
local pure_compiler = require("prototypes.mir.planner.compiler")
local family_resolver = require("prototypes.mir.families.resolver")
local execution_mode = require("prototypes.mir.domain.compiler.execution_mode")
local technology_catalog_contract = require("prototypes.mir.planner.technology_catalog")

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
    compilation_snapshot_deep_verifications = ((trust_metrics.CompilationSnapshot or {}).untrusted_verifications or 0),
    policy_snapshot_deep_verifications = ((trust_metrics.PolicySnapshot or {}).untrusted_verifications or 0),
    compiler_input_deep_verifications = ((trust_metrics.CompilerInput or {}).untrusted_verifications or 0),
    runtime_environment_deep_verifications = ((trust_metrics.RuntimeEnvironmentIdentity or {}).untrusted_verifications or 0),
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
  local provider_inputs = family_resolver.view()
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
  local input_sanitation_ledger = context:artifact_view("input_sanitation_ledger") or {}
  local input = compiler_input.new({
    source_fingerprints = input_sources,
    compilation_snapshot = input_snapshot,
    policy_snapshot = policy_snapshot,
    runtime_environment = environment,
    input_sanitation_fingerprint = fingerprint.of(input_sanitation_ledger)
  })
  latest = compilation_plan.finalize(stream_plan, base_plan, {
    compiler_input = input,
    base_candidates = base_candidates,
    input_sanitation_ledger = input_sanitation_ledger,
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
  context:record_immutable_artifact(
    "technology_candidate_catalog", latest.technology_catalog, technology_catalog_contract)
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

M.record_work_volume = record_work_volume

return M
