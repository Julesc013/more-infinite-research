local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local serialize = require("prototypes.mir.planner.compilation_plan.serialize")

local M = {}

function M.compilation(artifact)
  return fingerprint.of(serialize.compilation(artifact))
end

function M.qualification(artifact)
  return fingerprint.of(serialize.qualification(artifact))
end

function M.operation_fingerprints(operations)
  local out = {}
  for _, operation in ipairs(operations or {}) do
    table.insert(out, fingerprint.of(serialize.operation(operation)))
  end
  table.sort(out)
  return out
end

function M.attach_run_evidence(artifact)
  artifact.telemetry = telemetry.snapshot()
  artifact.telemetry_fingerprint = fingerprint.of(artifact.telemetry)
  artifact.run_fingerprint = fingerprint.of({
    qualification_fingerprint = artifact.qualification_fingerprint,
    telemetry_fingerprint = artifact.telemetry_fingerprint
  })
  artifact.run = {
    schema = 1,
    telemetry = deepcopy(artifact.telemetry),
    telemetry_fingerprint = artifact.telemetry_fingerprint,
    run_fingerprint = artifact.run_fingerprint
  }
  return artifact
end

return M
