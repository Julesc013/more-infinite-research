local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

function M.candidate(raw, rule)
  local out = deepcopy(raw)
  out.schema = 1
  out.provider_id = rule.provider_id
  out.family = rule.id
  out.partition_key = rule.id .. ":" .. tostring((rule.operators.partitioner or {}).operator or "unpartitioned")
  out.identity = rule.provider_id .. "\0" .. out.recipe .. "\0" .. out.item
  out.candidate_fingerprint = fingerprint.of(out)
  return out
end

return M
