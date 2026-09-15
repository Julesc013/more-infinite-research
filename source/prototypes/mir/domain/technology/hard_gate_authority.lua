local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local generated = require("prototypes.mir.domain.technology.generated_hard_gate_authority")

local M = {}
local by_id = {}
for _, row in ipairs(generated.gates) do
  if by_id[row.id] then error("Duplicate generated hard gate: " .. tostring(row.id)) end
  by_id[row.id] = row
end

function M.order()
  local out = {}
  for _, row in ipairs(generated.gates) do table.insert(out, row.id) end
  return out
end

function M.contains(id)
  return by_id[id] ~= nil
end

function M.assert_total(gates)
  if type(gates) ~= "table" then error("Technology hard-gate vector is required.", 2) end
  for _, id in ipairs(M.order()) do
    if gates[id] == nil then error("Technology hard-gate vector is missing: " .. id, 2) end
  end
  for id in pairs(gates) do
    if not by_id[id] then error("Technology hard-gate vector contains unknown gate: " .. tostring(id), 2) end
  end
  return true
end

function M.snapshot()
  local out = deepcopy(generated)
  out.authority_fingerprint = fingerprint.of(generated)
  return out
end

return M
