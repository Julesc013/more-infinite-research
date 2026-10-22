local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")

local M = {}
local authority = trusted_record.new("TechnologyGate")


-- Initial-skip diagnostic deferment is a same-compilation private transport.
-- Its receipts are opaque and retain no public/exported contract. A snapshot
-- captures every raw field so a trusted record's scalar identity alone cannot
-- hide a later mutation to evidence, rejection reason, applicability, or an
-- added field.
local initial_skip_vector_sessions = setmetatable({}, {__mode = "k"})

local function plain_snapshot(value, copies, visiting)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then return value, true end
  if kind ~= "table" or getmetatable(value) ~= nil or visiting[value] then return nil, false end
  local existing = copies[value]
  if existing then return existing, true end
  local out = {}
  copies[value] = out
  visiting[value] = true
  for key, child in next, value do
    if type(key) ~= "string" and type(key) ~= "number" then return nil, false end
    local copied, ok = plain_snapshot(child, copies, visiting)
    if not ok then return nil, false end
    out[key] = copied
  end
  visiting[value] = nil
  return out, true
end

-- Ordinary numeric equality is enough except where the canonical writer
-- distinguishes signed zero or represents NaN textually. Keep those exact
-- exceptional bytes without reserializing any enclosing gate vector.
local function same_number(actual, expected)
  if actual == 0 or expected == 0 or actual ~= actual or expected ~= expected then
    return string.format("%.17g", actual) == string.format("%.17g", expected)
  end
  return actual == expected
end

local function same_plain(actual, expected, pairs_seen)
  local actual_kind, expected_kind = type(actual), type(expected)
  if actual_kind ~= expected_kind then return false end
  if actual_kind == "number" then return same_number(actual, expected) end
  if actual_kind ~= "table" then return actual == expected end
  if getmetatable(actual) ~= nil or getmetatable(expected) ~= nil then return false end
  if rawequal(actual, expected) then return true end
  pairs_seen = pairs_seen or {}
  local compared = pairs_seen[actual]
  if compared and compared[expected] then return true end
  compared = compared or {}
  pairs_seen[actual] = compared
  compared[expected] = true
  local expected_zero_key_text = nil
  for key, expected_value in next, expected do
    if type(key) == "number" and key == 0 then expected_zero_key_text = string.format("%.17g", key) end
    local actual_value = rawget(actual, key)
    if actual_value == nil or not same_plain(actual_value, expected_value, pairs_seen) then return false end
  end
  local actual_zero_key_text = nil
  for key in next, actual do
    if rawget(expected, key) == nil then return false end
    if type(key) == "number" and key == 0 then actual_zero_key_text = string.format("%.17g", key) end
  end
  return expected_zero_key_text == actual_zero_key_text
end

local STATUSES = {
  ["not-applicable"] = true,
  pending = true,
  passed = true,
  failed = true,
  superseded = true
}

local function evidence_fingerprint(evaluator, evidence, applicability)
  return fingerprint.of({evaluator = evaluator, evidence = evidence or {}, applicability = applicability})
end

local function identity(record)
  return {
    status = record.status,
    passed = record.passed,
    evaluator = record.evaluator,
    evidence_fingerprint = record.evidence_fingerprint
  }
end

local function identity_unchanged(record, registered)
  return record.status == registered.status
    and record.passed == registered.passed
    and record.evaluator == registered.evaluator
    and record.evidence_fingerprint == registered.evidence_fingerprint
end

local function trust(record)
  return authority.register(record, identity(record))
end

function M.pending(evaluator)
  return trust({
    passed = false,
    status = "pending",
    evaluator = evaluator,
    evidence = {}
  })
end

function M.not_applicable(evaluator, applicability_predicate, input_fingerprint, evidence)
  if type(evaluator) ~= "string" or evaluator == ""
    or type(applicability_predicate) ~= "string" or applicability_predicate == ""
    or type(input_fingerprint) ~= "string" or input_fingerprint == "" then
    error("Not-applicable technology gate requires evaluator, predicate, and input fingerprint.", 2)
  end
  local copied = deepcopy(evidence or {})
  local applicability = {
    predicate = applicability_predicate,
    input_fingerprint = input_fingerprint,
    result = false
  }
  return trust({
    passed = true,
    status = "not-applicable",
    evaluator = evaluator,
    evidence = copied,
    applicability = applicability,
    evidence_fingerprint = evidence_fingerprint(evaluator, copied, applicability)
  })
end

function M.passed(evaluator, evidence)
  local copied = deepcopy(evidence or {})
  return trust({
    passed = true,
    status = "passed",
    evaluator = evaluator,
    evidence = copied,
    evidence_fingerprint = evidence_fingerprint(evaluator, copied, nil)
  })
end

function M.failed(evaluator, reason, evidence)
  local copied = deepcopy(evidence or {})
  return trust({
    passed = false,
    status = "failed",
    evaluator = evaluator,
    reason = reason,
    evidence = copied,
    evidence_fingerprint = evidence_fingerprint(evaluator, copied, nil)
  })
end

function M.supersede(previous, evaluator, replacement)
  M.assert_trusted(previous)
  M.assert_trusted(replacement)
  local result = deepcopy(previous)
  result.passed = false
  result.status = "superseded"
  result.superseded_by = {
    evaluator = evaluator,
    status = replacement.status,
    evidence_fingerprint = replacement.evidence_fingerprint
  }
  return trust(result)
end

local function verify(record)
  if type(record) ~= "table" or not STATUSES[record.status]
    or type(record.passed) ~= "boolean" or type(record.evidence) ~= "table" then
    error("Technology gate must be a valid lifecycle record.", 2)
  end
  if record.status == "passed" or record.status == "failed" or record.status == "not-applicable" then
    if type(record.evaluator) ~= "string" or record.evaluator == "" then
      error("Authoritative technology gate requires an evaluator.", 2)
    end
    local applicability = record.status == "not-applicable" and record.applicability or nil
    if record.status == "not-applicable" and (type(applicability) ~= "table"
      or type(applicability.predicate) ~= "string" or applicability.predicate == ""
      or type(applicability.input_fingerprint) ~= "string" or applicability.input_fingerprint == ""
      or applicability.result ~= false) then
      error("Not-applicable technology gate requires a false applicability proof.", 2)
    end
    if record.evidence_fingerprint ~= evidence_fingerprint(record.evaluator, record.evidence, applicability) then
      error("Authoritative technology gate evidence fingerprint is invalid.", 2)
    end
  elseif record.evidence_fingerprint ~= nil then
    error("Provisional technology gate cannot claim an evidence fingerprint.", 2)
  end
  if record.status == "passed" and not record.passed then
    error("Passed technology gate must set passed=true.", 2)
  end
  if (record.status == "pending" or record.status == "failed" or record.status == "superseded") and record.passed then
    error("Unresolved technology gate cannot set passed=true.", 2)
  end
  if record.status == "failed" and (type(record.reason) ~= "string" or record.reason == "") then
    error("Failed technology gate requires a reason.", 2)
  end
  if record.status == "superseded" and type(record.superseded_by) ~= "table" then
    error("Superseded technology gate requires a replacement record.", 2)
  end
  return true
end

function M.verify_untrusted(record)
  authority.verify_untrusted(record, verify, identity(record or {}))
  return true
end

function M.validate(record)
  return M.verify_untrusted(record)
end

function M.assert_trusted(record)
  return authority.assert_trusted(record, identity_unchanged)
end

function M.is_trusted(record)
  return authority.is_trusted(record)
end

function M.is_authoritatively_resolved(record)
  M.assert_trusted(record)
  return record.status == "passed" or record.status == "failed" or record.status == "not-applicable"
end

function M.authority_projection(record)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  return identity(record)
end

-- Internal constructors use this only after the exact gate instance has
-- crossed its private trust boundary. The returned scalar projection grants
-- no trust and cannot authorize an unregistered record.
function M.trusted_authority_projection_view(record)
  return identity(record)
end


function M.new_initial_skip_gate_vector_session()
  local session = {}
  initial_skip_vector_sessions[session] = {
    snapshots_by_gate = setmetatable({}, {__mode = "k"}),
    receipts = setmetatable({}, {__mode = "k"})
  }
  return session
end

function M.capture_initial_skip_gate_vector(session, gates)
  local state = initial_skip_vector_sessions[session]
  if not state or type(gates) ~= "table" or getmetatable(gates) ~= nil then
    error("Initial-skip gate-vector capture requires an owned session and plain gate map.", 2)
  end
  local vector = {}
  for gate_name, record in next, gates do
    if type(gate_name) ~= "string" then
      error("Initial-skip gate-vector capture requires string gate keys.", 2)
    end
    M.assert_trusted(record)
    local snapshot = state.snapshots_by_gate[record]
    if not snapshot then
      snapshot = select(1, plain_snapshot(record, {}, {}))
      if not snapshot then error("Initial-skip gate-vector capture refuses non-plain, cyclic, or metatable records.", 2) end
      state.snapshots_by_gate[record] = snapshot
    end
    vector[gate_name] = snapshot
  end
  local receipt = {}
  state.receipts[receipt] = vector
  return receipt
end

function M.matches_initial_skip_gate_vector(session, receipt, gates)
  local state = initial_skip_vector_sessions[session]
  if not state or type(receipt) ~= "table" or type(gates) ~= "table" then return false end
  local snapshot = state.receipts[receipt]
  return snapshot ~= nil and same_plain(gates, snapshot)
end

function M.schema_authority()
  return {
    schema = 1,
    statuses = {"not-applicable", "pending", "passed", "failed", "superseded"},
    authoritative_statuses = {"not-applicable", "passed", "failed"},
    evidence_fingerprint = "sha256(evaluator+evidence+applicability)",
    not_applicable_requires = {"evaluator", "predicate", "input_fingerprint", "false-result", "evidence"}
  }
end

return M
