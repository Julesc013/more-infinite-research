local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local compilation_plan = require("prototypes.mir.planner.compilation_plan")
local stream_compiler = require("prototypes.mir.planner.stream_compiler")
local base_extensions = require("prototypes.mir.emit.base_extensions")
local stream_executor = require("prototypes.mir.emit.stream_executor")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local compiler_input = require("prototypes.mir.domain.compiler.compiler_input")
local compiler_evidence = require("prototypes.mir.domain.evidence.compiler_evidence")
local environment_adapter = require("prototypes.mir.platform.factorio.environment_identity")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local public_artifacts = require("prototypes.mir.report.public_compiler_artifacts")

local M = {}

function M.compile(context)
  context = context or compiler_context.current()
  compiler_context.activate(context)
  local latest = context:state_view("compilation_plan")
  if latest then return latest end
  telemetry.start_phase("planning")
  local stream_plan = stream_compiler.compile_view(context)
  local base_plan = base_extensions.plan_all()
  local environment = environment_adapter.current()
  local input_sources = deepcopy(stream_plan.source_fingerprints)
  input_sources.base_extension_plan = fingerprint.of(base_plan)
  local input = compiler_input.new({
    source_fingerprints = input_sources,
    environment_identity = environment,
    environment_fingerprint = environment.environment_fingerprint,
    target_profile_fingerprint = stream_plan.source_fingerprints.target_profile,
    generation_plan_fingerprint = stream_plan.plan_fingerprint,
    input_sanitation_fingerprint = fingerprint.of(context:artifact("input_sanitation_ledger") or {})
  })
  latest = compilation_plan.finalize(stream_plan, base_plan, {
    compiler_input = input,
    input_sanitation_ledger = context:artifact("input_sanitation_ledger"),
    stream_plan_trusted = true
  })
  context:set_state("compiler_input", input)
  context:set_state("compilation_plan", latest)
  context:set_state("technology_candidate_catalog", latest.technology_catalog)
  context:set_state("technology_qualifications", latest.technology_catalog.qualifications)
  context:set_state("compiler_result", latest.compiler_result)
  context:record_artifact("technology_candidate_catalog", latest.technology_catalog)
  stream_compiler.accept_artifact(latest.stream_plan, context, {trusted = true})
  telemetry.finish_phase("planning")
  return latest
end

function M.apply_streams(context)
  stream_executor.apply(M.compile(context).stream_plan)
end

function M.apply_base_extensions(context)
  base_extensions.apply_plan(M.compile(context).base_extension_operations)
end

function M.snapshot(context)
  local plan = M.compile(context)
  local snapshot = {
    schema = plan.schema,
    fingerprint = plan.fingerprint,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    semantic_fingerprint = plan.semantic_fingerprint,
    source_fingerprints = plan.source_fingerprints,
    compiler_input = plan.compiler_input,
    compiler_result = plan.compiler_result,
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
  return require("prototypes.mir.planner.output_validator").assert_compilation_artifact(
    M.compile(context),
    {designs_validated = true}
  )
end

function M.publish(context)
  context = context or compiler_context.current()
  local plan = M.compile(context)
  local mod_data = require("prototypes.mir.emit.mod_data")
  local include_internal = diagnostics.enabled()
  local public_plan = public_artifacts.generation_plan(plan.stream_plan)
  telemetry.count("generation_plan_rows", #(plan.stream_plan.rows or {}))
  telemetry.count("generation_plan_public_bytes", #fingerprint.canonical(public_plan))
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
  mod_data.emit_technology_catalog(plan.technology_catalog)
  if include_internal then
    telemetry.count("generation_plan_internal_bytes", #fingerprint.canonical(plan.stream_plan))
    mod_data.emit_internal_generation_plan(plan.stream_plan)
  end
  local evidence_input = {
    compilation_plan_schema = plan.schema,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    compiler_input_fingerprint = plan.compiler_input.input_fingerprint,
    compiler_result_fingerprint = plan.compiler_result.result_fingerprint,
    technology_catalog_fingerprint = plan.technology_catalog_fingerprint,
    input_sanitation_ledger = deepcopy(plan.input_sanitation_ledger),
    output_sanitation_ledger = context:artifact("output_sanitation_ledger")
  }
  if target_line.feature_enabled("productivity_family_adoption") then
    require("prototypes.mir.emit.transactions.productivity_family_adoption").emit_mod_data()
  end
  require("prototypes.mir.report.coverage").publish(context, {include_internal = include_internal})
  telemetry.observe_max("context_state_keys", context:state_key_count())
  evidence_input.telemetry = telemetry.snapshot()
  local public_evidence = public_artifacts.compiler_evidence(evidence_input)
  local internal_evidence = include_internal and compiler_evidence.build(evidence_input) or nil
  require("prototypes.mir.emit.compiler_evidence_adapter").publish(public_evidence, internal_evidence)
  return true
end

return M
