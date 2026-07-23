local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

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

function M.pending(evaluator)
  return {
    passed = false,
    status = "pending",
    evaluator = evaluator,
    evidence = {}
  }
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
  return {
    passed = true,
    status = "not-applicable",
    evaluator = evaluator,
    evidence = copied,
    applicability = applicability,
    evidence_fingerprint = evidence_fingerprint(evaluator, copied, applicability)
  }
end

function M.passed(evaluator, evidence)
  local copied = deepcopy(evidence or {})
  return {
    passed = true,
    status = "passed",
    evaluator = evaluator,
    evidence = copied,
    evidence_fingerprint = evidence_fingerprint(evaluator, copied, nil)
  }
end

function M.failed(evaluator, reason, evidence)
  local copied = deepcopy(evidence or {})
  return {
    passed = false,
    status = "failed",
    evaluator = evaluator,
    reason = reason,
    evidence = copied,
    evidence_fingerprint = evidence_fingerprint(evaluator, copied, nil)
  }
end

function M.supersede(previous, evaluator, replacement)
  M.validate(previous)
  M.validate(replacement)
  local result = deepcopy(previous)
  result.passed = false
  result.status = "superseded"
  result.superseded_by = {
    evaluator = evaluator,
    status = replacement.status,
    evidence_fingerprint = replacement.evidence_fingerprint
  }
  return result
end

function M.validate(record)
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

function M.is_authoritatively_resolved(record)
  M.validate(record)
  return record.status == "passed" or record.status == "failed" or record.status == "not-applicable"
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
