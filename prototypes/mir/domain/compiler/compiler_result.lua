local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")

local M = {}
local authority = trusted_record.new("CompilerResult")
local SCHEMA = 3

local DIMENSION_VALUES = {
  execution = {NOT_EXECUTED = true, PLANNED = true, APPLIED = true, FAILED = true},
  safety = {QUALIFIED = true, REVIEW_REQUIRED = true, FAILED = true},
  review = {NOT_REQUIRED = true, REQUIRED = true, COMPLETE = true},
  promotion = {NOT_APPLICABLE = true, PROVISIONAL = true, PROMOTED = true, BLOCKED = true},
  release = {ELIGIBLE = true, REVIEW_REQUIRED = true, BLOCKED = true}
}

local PROJECTION_CLASSES = {
  "accepted_candidates", "rejected_candidates", "review_required_candidates", "provider_claims",
  "base_continuations", "quality_dispositions", "promotion_dispositions", "sanitation_dispositions"
}

local FINAL_EVIDENCE_FIELDS = {
  "journal_fingerprint", "realized_output_fingerprint", "output_parity_fingerprint",
  "graph_parity_fingerprint", "sanitation_parity_fingerprint"
}

local function material(record)
  local out = {}
  for key, value in pairs(record or {}) do
    if key ~= "result_fingerprint" then out[key] = value end
  end
  return out
end

local function trust_identity(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    result_phase = record.result_phase,
    input_fingerprint = record.input_fingerprint,
    compilation_plan_fingerprint = record.compilation_plan_fingerprint,
    qualification_fingerprint = record.qualification_fingerprint,
    planned_result_fingerprint = record.planned_result_fingerprint,
    result_fingerprint = record.result_fingerprint,
    status = record.status
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.record_type == registered.record_type
    and record.result_phase == registered.result_phase
    and record.input_fingerprint == registered.input_fingerprint
    and record.compilation_plan_fingerprint == registered.compilation_plan_fingerprint
    and record.qualification_fingerprint == registered.qualification_fingerprint
    and record.planned_result_fingerprint == registered.planned_result_fingerprint
    and record.result_fingerprint == registered.result_fingerprint
    and record.status == registered.status
end

local function trust(record)
  return authority.register(record, trust_identity(record))
end

local function derived_status(dimensions)
  if dimensions.execution == "FAILED" or dimensions.safety == "FAILED"
    or dimensions.promotion == "BLOCKED" or dimensions.release == "BLOCKED" then
    return "FAIL"
  end
  if dimensions.safety == "REVIEW_REQUIRED" or dimensions.review == "REQUIRED"
    or dimensions.release == "REVIEW_REQUIRED" or dimensions.promotion == "PROVISIONAL" then
    return "REVIEW_REQUIRED"
  end
  return "PASS"
end

local function verify(record, options)
  options = options or {}
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "CompilerResult"
    or (record.result_phase ~= "planned" and record.result_phase ~= "final") then
    error("CompilerResult schema 3 planned or final record is required.", 2)
  end
  for _, field in ipairs({
    "input_fingerprint", "technology_catalog_fingerprint", "generation_plan_fingerprint",
    "compilation_plan_fingerprint", "qualification_fingerprint", "status"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("CompilerResult field is required: " .. field, 2)
    end
  end
  if type(record.dimensions) ~= "table" or type(record.operation_fingerprints) ~= "table"
    or type(record.disposition_counts) ~= "table" or type(record.disposition_fingerprints) ~= "table" then
    error("CompilerResult multidimensional disposition material is required.", 2)
  end
  for name, values in pairs(DIMENSION_VALUES) do
    if not values[record.dimensions[name]] then
      error("CompilerResult dimension is invalid: " .. name, 2)
    end
  end
  for _, class in ipairs(PROJECTION_CLASSES) do
    if type(record[class]) ~= "table" then error("CompilerResult projection is required: " .. class, 2) end
    if record.disposition_counts[class] ~= #record[class] then
      error("CompilerResult disposition summary differs: " .. class, 2)
    end
    if options.verify_fingerprints ~= false
      and record.disposition_fingerprints[class] ~= fingerprint.of(record[class]) then
      error("CompilerResult disposition summary differs: " .. class, 2)
    end
  end
  if record.result_phase == "planned" then
    if record.dimensions.execution ~= "PLANNED" or record.execution_evidence ~= nil then
      error("Planned CompilerResult must be immutable pre-execution material.", 2)
    end
  else
    if type(record.planned_result_fingerprint) ~= "string" or record.planned_result_fingerprint == ""
      or type(record.execution_evidence) ~= "table" then
      error("Final CompilerResult requires its planned result and execution evidence.", 2)
    end
    for _, field in ipairs(FINAL_EVIDENCE_FIELDS) do
      if type(record.execution_evidence[field]) ~= "string" or record.execution_evidence[field] == "" then
        error("Final CompilerResult execution evidence is required: " .. field, 2)
      end
    end
    for _, field in ipairs({
      "planned_operation_count", "executed_operation_count", "skipped_operation_count",
      "failed_operation_count", "missing_operation_count",
      "duplicate_operation_count", "undeclared_operation_count", "out_of_plan_operation_count"
    }) do
      if type(record.execution_evidence[field]) ~= "number" or record.execution_evidence[field] < 0 then
        error("Final CompilerResult operation count is invalid: " .. field, 2)
      end
    end
    if record.dimensions.execution ~= "APPLIED" and record.dimensions.execution ~= "FAILED" then
      error("Final CompilerResult execution must be APPLIED or FAILED.", 2)
    end
  end
  if record.status ~= derived_status(record.dimensions) then
    error("CompilerResult scalar status differs from its dimensions.", 2)
  end
  if options.verify_fingerprints ~= false
    and record.result_fingerprint ~= fingerprint.of(material(record)) then
    error("CompilerResult fingerprint is invalid.", 2)
  end
  return true
end

function M.verify_untrusted(record)
  authority.verify_untrusted(record, verify, trust_identity(record or {}))
  return true
end

function M.validate(record)
  return M.verify_untrusted(record)
end

function M.assert_trusted(record)
  return authority.assert_trusted(record, trust_identity_unchanged)
end

function M.is_trusted(record)
  return authority.is_trusted(record)
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = SCHEMA
  record.record_type = "CompilerResult"
  record.result_phase = "planned"
  record.operation_fingerprints = record.operation_fingerprints or {}
  record.dimensions = record.dimensions or {
    execution = "PLANNED",
    safety = "QUALIFIED",
    review = "NOT_REQUIRED",
    promotion = "NOT_APPLICABLE",
    release = "ELIGIBLE"
  }
  record.dimensions.execution = "PLANNED"
  record.execution_evidence = nil
  record.planned_result_fingerprint = nil
  record.disposition_counts = {}
  record.disposition_fingerprints = {}
  for _, class in ipairs(PROJECTION_CLASSES) do
    record[class] = record[class] or {}
    record.disposition_counts[class] = #record[class]
    record.disposition_fingerprints[class] = fingerprint.of(record[class])
  end
  record.status = derived_status(record.dimensions)
  record.result_fingerprint = fingerprint.of(material(record))
  verify(record, {verify_fingerprints = false})
  return trust(record)
end

function M.finalize(planned, evidence)
  if M.is_trusted(planned) then M.assert_trusted(planned) else M.verify_untrusted(planned) end
  if planned.result_phase ~= "planned" then error("CompilerResult finalizer requires a planned result.", 2) end
  evidence = deepcopy(evidence or {})
  evidence.planned_operation_count = #planned.operation_fingerprints
  local failed = evidence.executed_operation_count ~= evidence.planned_operation_count
    or evidence.skipped_operation_count > 0
    or evidence.failed_operation_count > 0
    or evidence.missing_operation_count > 0
    or evidence.duplicate_operation_count > 0
    or evidence.undeclared_operation_count > 0
    or evidence.out_of_plan_operation_count > 0
    or evidence.output_parity_passed ~= true
    or evidence.graph_parity_passed ~= true
    or evidence.sanitation_parity_passed ~= true
  local record = deepcopy(planned)
  record.result_phase = "final"
  record.planned_result_fingerprint = planned.result_fingerprint
  record.execution_evidence = evidence
  record.dimensions.execution = failed and "FAILED" or "APPLIED"
  if failed then
    record.dimensions.safety = "FAILED"
    record.dimensions.promotion = "BLOCKED"
    record.dimensions.release = "BLOCKED"
  end
  record.status = derived_status(record.dimensions)
  record.result_fingerprint = nil
  record.result_fingerprint = fingerprint.of(material(record))
  verify(record, {verify_fingerprints = false})
  return trust(record)
end

function M.schema_authority()
  local out = {schema = SCHEMA, dimensions = {}, projection_classes = deepcopy(PROJECTION_CLASSES)}
  for name, values in pairs(DIMENSION_VALUES) do
    out.dimensions[name] = {}
    for value in pairs(values) do table.insert(out.dimensions[name], value) end
    table.sort(out.dimensions[name])
  end
  return out
end

function M.compatibility_projection(record)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  local out = {
    schema = 2,
    record_type = "CompilerResult",
    result_phase = record.result_phase,
    input_fingerprint = record.input_fingerprint,
    technology_catalog_fingerprint = record.technology_catalog_fingerprint,
    generation_plan_fingerprint = record.generation_plan_fingerprint,
    compilation_plan_fingerprint = record.compilation_plan_fingerprint,
    qualification_fingerprint = record.qualification_fingerprint,
    operation_fingerprints = deepcopy(record.operation_fingerprints),
    rejected_candidates = deepcopy(record.rejected_candidates),
    dimensions = deepcopy(record.dimensions),
    status = record.status,
    authoritative_result_fingerprint = record.result_fingerprint
  }
  local projection_material = deepcopy(out)
  projection_material.result_fingerprint = nil
  out.result_fingerprint = fingerprint.of(projection_material)
  return out
end

function M.snapshot(record)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  authority.count_snapshot()
  authority.count_full_copy()
  return deepcopy(record)
end

return M
