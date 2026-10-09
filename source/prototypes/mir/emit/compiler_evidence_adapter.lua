local mod_data = require("prototypes.mir.emit.mod_data")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

function M.publish(evidence, internal_evidence)
  if not evidence then return nil end
  if target_line.mod_data_supported() then
    mod_data.emit_compiler_evidence(evidence)
    if internal_evidence then mod_data.emit_internal_compiler_evidence(internal_evidence) end
    return "mod-data"
  end
  if type(log) == "function" then
    log("[MIR-COMPILER-EVIDENCE] schema=" .. tostring(evidence.schema)
      .. " compilation=" .. tostring(evidence.compilation_fingerprint)
      .. " qualification=" .. tostring(evidence.qualification_fingerprint)
      .. " run=" .. tostring(evidence.run_fingerprint)
      .. " evidence=" .. tostring(evidence.evidence_fingerprint))
  end
  return "validation-log"
end

return M
