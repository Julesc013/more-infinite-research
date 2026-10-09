local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

function M.build(input)
  if type(input) ~= "table"
    or type(input.compilation_fingerprint) ~= "string"
    or type(input.qualification_fingerprint) ~= "string"
    or type(input.telemetry) ~= "table" then
    error("CompilerEvidence requires compilation, qualification, and telemetry inputs.", 2)
  end
  local telemetry_fingerprint = fingerprint.of(input.telemetry)
  local evidence = {
    schema = 2,
    compilation_plan_schema = input.compilation_plan_schema,
    compilation_fingerprint = input.compilation_fingerprint,
    qualification_fingerprint = input.qualification_fingerprint,
    semantic_fingerprint = input.qualification_fingerprint,
    telemetry_fingerprint = telemetry_fingerprint,
    run_fingerprint = fingerprint.of({
      qualification_fingerprint = input.qualification_fingerprint,
      telemetry_fingerprint = telemetry_fingerprint
    }),
    compiler_input_fingerprint = input.compiler_input_fingerprint,
    compiler_result_fingerprint = input.compiler_result_fingerprint,
    compiler_result = deepcopy(input.compiler_result),
    mutation_journal = deepcopy(input.mutation_journal),
    technology_catalog_fingerprint = input.technology_catalog_fingerprint,
    technology_graph_parity = deepcopy(input.technology_graph_parity),
    provider_resolution = deepcopy(input.provider_resolution or {}),
    provider_decision_diagnostics = deepcopy(input.provider_decision_diagnostics or {}),
    input_sanitation_ledger = deepcopy(input.input_sanitation_ledger),
    input_sanitation_fingerprint = fingerprint.of(input.input_sanitation_ledger or {}),
    output_sanitation_ledger = deepcopy(input.output_sanitation_ledger),
    output_sanitation_fingerprint = fingerprint.of(input.output_sanitation_ledger or {})
  }
  evidence.evidence_fingerprint = fingerprint.of(evidence)
  return evidence
end

return M
