local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local compilation_snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot = require("prototypes.mir.domain.compiler.policy_snapshot")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")
local transformation_plan = require("prototypes.mir.domain.compiler.transformation_plan")

local M = {}

local function gate_disposition(row)
  hard_gate_authority.assert_total(row.gates)
  local unresolved, failed = {}, {}
  for _, gate_name in ipairs(hard_gate_authority.order()) do
    local gate = row.gates[gate_name]
    gate_contract.validate(gate)
    if gate.status == "failed" then table.insert(failed, gate_name) end
    if not gate_contract.is_authoritatively_resolved(gate) then table.insert(unresolved, gate_name) end
  end
  return unresolved, failed
end

local function stream_operation(row, policy)
  local action = row.action == "adopt" and "patch" or "create"
  local subject_id = row.action == "adopt" and row.adoption.owner or row.technology_name
  return operation_contract.new({
    operation_id = "technology/" .. action .. "/" .. tostring(subject_id),
    phase = "technology-materialization",
    action = action,
    subject = {type = "technology", id = tostring(subject_id)},
    precondition_fingerprint = row.action == "adopt" and row.adoption.input_fingerprint
      or fingerprint.of({absent = subject_id}),
    authority_fingerprint = policy.policy_fingerprint,
    payload = {
      kind = "stream",
      stream_key = row.stream_key,
      manifest_id = row.manifest_id,
      technology_design = deepcopy(row.technology_design),
      adoption = deepcopy(row.adoption)
    },
    evidence = {gates = deepcopy(row.gates)}
  })
end

local function base_operation(operation, policy)
  return operation_contract.new({
    operation_id = "technology/create/" .. tostring(operation.technology_name),
    phase = "technology-materialization",
    action = "create",
    subject = {type = "technology", id = tostring(operation.technology_name)},
    precondition_fingerprint = fingerprint.of({absent = operation.technology_name}),
    authority_fingerprint = policy.policy_fingerprint,
    payload = {
      kind = "base-continuation",
      key = operation.key,
      manifest_id = operation.manifest_id,
      technology_design = deepcopy(operation.technology_design)
    },
    evidence = {gates = deepcopy(operation.gates or (operation.technology_design or {}).gates or {})}
  })
end

function M.compile(snapshot, policy)
  compilation_snapshot.validate(snapshot)
  policy_snapshot.validate(policy)
  local stream_plan = snapshot.stream_inputs.plan or snapshot.stream_inputs
  local base_plan = snapshot.base_continuation_inputs.operations or snapshot.base_continuation_inputs
  local operations, dispositions = {}, {accepted = {}, rejected = {}, review_required = {}}
  local provider_claims = {}
  for _, row in ipairs(snapshot.provider_inputs.decisions or {}) do
    if type(row.claim_fingerprint) ~= "string" or row.claim_fingerprint == "" then
      error("Provider decision lacks its exact semantic claim fingerprint.", 2)
    end
    local claim = {
      provider_id = row.provider_id,
      provider_version = row.provider_version,
      subject = {prototype_type = row.prototype_type, prototype_name = row.prototype_name},
      target_stream = row.target_stream,
      final_state = row.final_state,
      claim_fingerprint = row.claim_fingerprint,
      decision_fingerprint = row.decision_fingerprint,
      risk_disposition = row.risk_disposition
    }
    table.insert(provider_claims, claim)
    if row.final_state == "review-required" or row.risk_disposition == "REVIEW_REQUIRED" then
      table.insert(dispositions.review_required, {
        candidate = "provider/" .. tostring(row.provider_id) .. "/" .. tostring(row.prototype_name),
        action = row.final_state,
        unresolved_gates = {"provider-claim-arbitration"},
        failed_gates = {},
        input_fingerprint = row.claim_fingerprint
      })
    end
  end
  for _, row in ipairs(stream_plan.rows or {}) do
    local unresolved, failed = gate_disposition(row)
    local record = {candidate = tostring(row.stream_key), action = row.action,
      unresolved_gates = unresolved, failed_gates = failed, input_fingerprint = fingerprint.of(row)}
    if #failed > 0 or (row.action ~= "emit" and row.action ~= "adopt") then
      table.insert(dispositions.rejected, record)
    elseif #unresolved > 0 then
      table.insert(dispositions.review_required, record)
    else
      table.insert(dispositions.accepted, record)
      table.insert(operations, stream_operation(row, policy))
    end
  end
  for _, operation in ipairs(base_plan or {}) do
    local gates = operation.gates or (operation.technology_design or {}).gates
    local unresolved, failed = gate_disposition({gates = gates})
    local record = {candidate = "base-continuation/" .. tostring(operation.key), action = "create",
      unresolved_gates = unresolved, failed_gates = failed, input_fingerprint = fingerprint.of(operation)}
    if #failed > 0 then table.insert(dispositions.rejected, record)
    elseif #unresolved > 0 then table.insert(dispositions.review_required, record)
    else table.insert(dispositions.accepted, record); table.insert(operations, base_operation(operation, policy)) end
  end
  for _, rows in pairs(dispositions) do
    table.sort(rows, function(left, right) return left.candidate < right.candidate end)
  end
  table.sort(provider_claims, function(left, right)
    if left.claim_fingerprint ~= right.claim_fingerprint then
      return left.claim_fingerprint < right.claim_fingerprint
    end
    return tostring(left.provider_id) < tostring(right.provider_id)
  end)
  local plan = transformation_plan.new({
    phase = "qualified-only",
    compilation_snapshot_fingerprint = snapshot.snapshot_fingerprint,
    policy_fingerprint = policy.policy_fingerprint,
    operations = operations
  })
  local result = {
    schema = 1,
    record_type = "PureCompilation",
    compilation_snapshot_fingerprint = snapshot.snapshot_fingerprint,
    policy_fingerprint = policy.policy_fingerprint,
    transformation_plan = plan,
    provider_claims = provider_claims,
    dispositions = dispositions,
    status = #dispositions.review_required > 0 and "REVIEW_REQUIRED" or "PASS"
  }
  result.compilation_fingerprint = fingerprint.of(result)
  return deepcopy(result)
end

return M
