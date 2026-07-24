local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local compilation_snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot = require("prototypes.mir.domain.compiler.policy_snapshot")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")
local transformation_plan = require("prototypes.mir.domain.compiler.transformation_plan")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}

local function gate_identity_map(gates)
  local out = {}
  for name, gate in pairs(gates or {}) do
    out[name] = {
      status = gate.status,
      passed = gate.passed,
      evaluator = gate.evaluator,
      evidence_fingerprint = gate.evidence_fingerprint
    }
  end
  return out
end

local function input_identity(row)
  local design = row.technology_design or {}
  return {
    schema = row.schema,
    stream_key = row.stream_key,
    key = row.key,
    manifest_id = row.manifest_id,
    action = row.action,
    reason = row.reason,
    technology_name = row.technology_name,
    candidate_id = design.candidate_id,
    design_fingerprint = design.design_fingerprint,
    prototype_fingerprint = design.prototype_fingerprint,
    qualification_fingerprint = design.qualification_fingerprint,
    gates = gate_identity_map(row.gates or design.gates)
  }
end

local function compilation_material(result)
  return {
    schema = result.schema,
    record_type = result.record_type,
    compilation_snapshot_fingerprint = result.compilation_snapshot_fingerprint,
    policy_fingerprint = result.policy_fingerprint,
    transformation_plan_fingerprint = result.transformation_plan.plan_fingerprint,
    provider_claims = result.provider_claims,
    dispositions = result.dispositions,
    status = result.status
  }
end

local function gate_disposition(row)
  hard_gate_authority.assert_total(row.gates)
  local unresolved, failed = {}, {}
  for _, gate_name in ipairs(hard_gate_authority.order()) do
    local gate = row.gates[gate_name]
    if gate_contract.is_trusted(gate) then gate_contract.assert_trusted(gate)
    else gate_contract.verify_untrusted(gate) end
    if gate.status == "failed" then table.insert(failed, gate_name) end
    if not gate_contract.is_authoritatively_resolved(gate) then table.insert(unresolved, gate_name) end
  end
  return unresolved, failed
end

local function stream_operation(row, policy)
  local action = row.action == "adopt" and "patch" or "create"
  local subject_id = row.action == "adopt" and row.adoption.owner or row.technology_name
  local design = row.technology_design
  if technology_design.is_trusted(design) then technology_design.assert_trusted(design)
  else technology_design.verify_untrusted(design) end
  local expected_before = row.action == "adopt" and deepcopy(row.adoption.input_snapshot)
    or {presence = "absent", prototype_type = "technology", id = tostring(subject_id)}
  local expected_after = row.action == "adopt" and deepcopy(row.adoption.expected_snapshot)
    or technology_design.prototype_projection(design, {validated = true})
  if action == "create" then expected_after.type = "technology" end
  return operation_contract.new({
    operation_id = "technology/" .. action .. "/" .. tostring(subject_id),
    phase = "technology-materialization",
    action = action,
    subject = {type = "technology", id = tostring(subject_id)},
    expected_before_snapshot = expected_before,
    expected_after_projection = expected_after,
    allowed_delta = action == "create"
      and {engine_default_fields = true}
      or {configured_fields = deepcopy(row.adoption.configured_fields or {})},
    authority_fingerprint = policy.policy_fingerprint,
    qualification_fingerprint = design.qualification_fingerprint,
    source = {
      candidate_id = design.candidate_id or tostring(row.stream_key),
      alternative_id = action .. ":" .. tostring(subject_id)
    },
    payload = {
      kind = "stream",
      stream_key = row.stream_key,
      manifest_id = row.manifest_id,
      technology_design = design,
      adoption = deepcopy(row.adoption)
    },
    evidence = {gates = row.gates}
  })
end

local function base_operation(operation, policy)
  local design = operation.technology_design
  if technology_design.is_trusted(design) then technology_design.assert_trusted(design)
  else technology_design.verify_untrusted(design) end
  local expected_after = technology_design.prototype_projection(design, {validated = true})
  expected_after.type = "technology"
  return operation_contract.new({
    operation_id = "technology/create/" .. tostring(operation.technology_name),
    phase = "technology-materialization",
    action = "create",
    subject = {type = "technology", id = tostring(operation.technology_name)},
    expected_before_snapshot = {
      presence = "absent", prototype_type = "technology", id = tostring(operation.technology_name)
    },
    expected_after_projection = expected_after,
    allowed_delta = {engine_default_fields = true},
    authority_fingerprint = policy.policy_fingerprint,
    qualification_fingerprint = design.qualification_fingerprint,
    source = {
      candidate_id = design.candidate_id or ("base-continuation/" .. tostring(operation.key)),
      alternative_id = "create:" .. tostring(operation.technology_name)
    },
    payload = {
      kind = "base-continuation",
      key = operation.key,
      manifest_id = operation.manifest_id,
      technology_design = design
    },
    evidence = {gates = operation.gates or design.gates or {}}
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
      unresolved_gates = unresolved, failed_gates = failed, input_fingerprint = fingerprint.of(input_identity(row))}
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
      unresolved_gates = unresolved, failed_gates = failed, input_fingerprint = fingerprint.of(input_identity(operation))}
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
    execution_mode = policy.execution_mode,
    compilation_snapshot_fingerprint = snapshot.snapshot_fingerprint,
    policy_fingerprint = policy.policy_fingerprint,
    execution_mode = policy.execution_mode,
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
  result.compilation_fingerprint = fingerprint.of(compilation_material(result))
  return result
end

return M
