local compatibility_slice = require("prototypes.mir.domain.research_cost.compatibility_slice")
local mod_data = require("prototypes.mir.emit.mod_data")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

function M.publish(artifact)
  if not artifact then return nil end
  compatibility_slice.verify_untrusted(artifact)
  if target_line.mod_data_supported() then
    mod_data.emit_research_cost_compatibility(artifact)
    return "mod-data"
  end
  if type(log) == "function" then
    log("[MIR-RESEARCH-COST-SUPPORT] schema=" .. tostring(artifact.schema)
      .. " proposition=" .. tostring(artifact.proposition.id)
      .. " status=" .. tostring(artifact.disposition.status)
      .. " reason=" .. tostring(artifact.disposition.reason_code)
      .. " assertion=" .. tostring(artifact.proof_assertion.assertion_fingerprint)
      .. " support=" .. tostring(artifact.support_fingerprint))
  end
  return "validation-log"
end

return M
