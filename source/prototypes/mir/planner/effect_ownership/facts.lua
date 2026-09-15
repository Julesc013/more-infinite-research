local deepcopy = require("prototypes.mir.core.deepcopy")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

function M.copy_rows_preserving_gates(raw_rows)
  local rows = {}
  for index, source in ipairs(raw_rows or {}) do
    local row = {}
    for key, value in pairs(source) do
      if key == "gates" then
        row.gates = {}
        for gate_name, gate in pairs(value or {}) do row.gates[gate_name] = gate end
      else
        row[key] = deepcopy(value)
      end
    end
    rows[index] = row
  end
  return rows
end

function M.effects_for(row)
  if row.action == "emit" then return row.fields and row.fields.effects or {} end
  if row.action == "adopt" then return row.adoption and row.adoption.effects or {} end
  return {}
end

function M.owner_name(row)
  if row.action == "adopt" then return row.adoption and row.adoption.owner or row.stream_key end
  return row.technology_name or row.stream_key
end

local function action_rank(row)
  if row.action == "adopt" then return 0 end
  return 1
end

local function source_rank(row)
  if row.source == "fixed-stream" then return 0 end
  if row.source == "family-rule" then return 2 end
  return 1
end

function M.claim_less(a, b)
  local a_explicit = tonumber(a.row.spec and a.row.spec.effect_claim_priority) or 100
  local b_explicit = tonumber(b.row.spec and b.row.spec.effect_claim_priority) or 100
  if a_explicit ~= b_explicit then return a_explicit < b_explicit end
  if action_rank(a.row) ~= action_rank(b.row) then return action_rank(a.row) < action_rank(b.row) end
  if source_rank(a.row) ~= source_rank(b.row) then return source_rank(a.row) < source_rank(b.row) end
  if a.row.stream_key ~= b.row.stream_key then return a.row.stream_key < b.row.stream_key end
  if tostring(a.row.manifest_id) ~= tostring(b.row.manifest_id) then
    return tostring(a.row.manifest_id) < tostring(b.row.manifest_id)
  end
  return a.position < b.position
end

function M.non_materializing_gates(identity)
  local names = {
    "target_supported", "effect_valid", "owner_conflict_free", "science_compatible",
    "lab_compatible", "prerequisites_acyclic", "loop_safe", "progression_safe",
    "migration_safe", "output_identity_safe"
  }
  local out = {}
  for _, name in ipairs(names) do
    out[name] = gate_contract.not_applicable(
      "effect-ownership",
      "candidate-retains-materializing-effect",
      fingerprint.of({effect_identity = identity, gate = name}),
      {"effect-ownership:" .. tostring(identity)}
    )
  end
  return out
end

function M.copy_operation_preserving_authority(source)
  local operation = {}
  for key, value in pairs(source or {}) do
    if key == "gates" then
      operation.gates = {}
      for gate_name, gate in pairs(value or {}) do operation.gates[gate_name] = gate end
    elseif key == "technology_design" then
      operation.technology_design = value
    else
      operation[key] = deepcopy(value)
    end
  end
  return operation
end

function M.operation_effects(operation)
  if operation.operation == "native_owner_binding" then return operation.effects or {} end
  return (operation.technology and operation.technology.effects) or {}
end

function M.operation_owner(operation)
  return operation.technology_name or operation.stream_key or operation.manifest_id
end

local function operation_rank(operation)
  if operation.operation == "native_owner_binding" then return 0 end
  if operation.operation == "emit_stream" then return 1 end
  if operation.operation == "emit_base_extension" then return 2 end
  return 3
end

function M.operation_claim_less(left, right)
  local left_rank, right_rank = operation_rank(left.operation), operation_rank(right.operation)
  if left_rank ~= right_rank then return left_rank < right_rank end
  if tostring(left.operation.stream_key) ~= tostring(right.operation.stream_key) then
    return tostring(left.operation.stream_key) < tostring(right.operation.stream_key)
  end
  if tostring(left.operation.manifest_id) ~= tostring(right.operation.manifest_id) then
    return tostring(left.operation.manifest_id) < tostring(right.operation.manifest_id)
  end
  if tostring(left.operation.technology_name) ~= tostring(right.operation.technology_name) then
    return tostring(left.operation.technology_name) < tostring(right.operation.technology_name)
  end
  return left.operation_index < right.operation_index
end

function M.retained_overlap(operation, identity)
  return type(operation.planned_overlap_identities) == "table"
    and operation.planned_overlap_identities[identity] == true
end

function M.effect_identity(effect)
  return generation_plan.effect_identity(effect)
end

return M
