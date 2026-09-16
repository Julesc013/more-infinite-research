local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local compiler_input = require("prototypes.mir.domain.compiler.compiler_input")
local compiler_result = require("prototypes.mir.domain.compiler.compiler_result")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")

local M = {}

local SCHEMA = 1
local ABI = "mir-research-cost-compatibility-slice-v1"
local PROPOSITION_ID = "mir-research-cost-neutral-default-parity-v1"
local ASSERTION_TYPE = "mir-research-cost-proof-assertion-v1"
local SAMPLE_LIMIT = 1

local TARGET_DISPOSITIONS = {
  factorio_2_1 = {
    classification = "target-native-equivalent",
    semantic_contract = "technology-count-formula",
    transport = "mod-data",
    qualification = "exact-current-environment"
  },
  factorio_2_0 = {
    classification = "portable-with-adapter",
    semantic_contract = "technology-count-formula",
    transport = "validation-log",
    qualification = "requires-exact-target-proof"
  }
}

local DISPOSITIONS = {
  SUPPORTED = {
    proof_status = "PASSED",
    reason_code = "neutral-default-semantic-parity-proven",
    remediation_code = "no-remediation-required"
  },
  NOT_APPLICABLE = {
    proof_status = "NOT_APPLICABLE",
    reason_code = "neutral-default-not-active",
    remediation_code = "restore-neutral-defaults-to-evaluate-parity"
  },
  UNSUPPORTED = {
    proof_status = "FAILED",
    reason_code = "no-research-cost-models-realized",
    remediation_code = "review-compiler-inputs"
  }
}

local function nonempty(value)
  return type(value) == "string" and value ~= ""
end

local function exact_target_dispositions(value)
  return type(value) == "table"
    and fingerprint.of(value) == fingerprint.of(TARGET_DISPOSITIONS)
end

local function assertion_material(assertion)
  local out = deepcopy(assertion)
  out.assertion_fingerprint = nil
  return out
end

local function support_material(record)
  local out = deepcopy(record)
  out.support_fingerprint = nil
  return out
end

local function expected_disposition(model_count, override_count)
  if model_count == 0 then return "UNSUPPORTED" end
  if override_count > 0 then return "NOT_APPLICABLE" end
  return "SUPPORTED"
end

local function assert_integer(value, field)
  if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
    error("Research-cost compatibility support count is invalid: " .. field, 3)
  end
end

local function verify(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA
    or record.kind ~= "mir-research-cost-support-public" or record.abi ~= ABI then
    error("Research-cost compatibility support schema 1 is required.", 3)
  end
  if type(record.proposition) ~= "table" or record.proposition.id ~= PROPOSITION_ID
    or record.proposition.formula_abi ~= research_cost_model.formula_abi
    or record.proposition.required_linear_increment ~= 0
    or record.proposition.statement_code ~= "neutral-default-preserves-prior-cost-semantics" then
    error("Research-cost compatibility proposition is invalid.", 3)
  end
  if record.current_target ~= "2.1" and record.current_target ~= "2.0" then
    error("Research-cost compatibility current target is unsupported.", 3)
  end
  if not exact_target_dispositions(record.target_dispositions) then
    error("Research-cost compatibility target dispositions are invalid.", 3)
  end
  if type(record.summary) ~= "table" then
    error("Research-cost compatibility summary is required.", 3)
  end
  for _, field in ipairs({"model_count", "neutral_model_count", "override_model_count"}) do
    assert_integer(record.summary[field], field)
  end
  if record.summary.neutral_model_count + record.summary.override_model_count
      ~= record.summary.model_count then
    error("Research-cost compatibility summary counts do not close.", 3)
  end
  local disposition_status = expected_disposition(
    record.summary.model_count, record.summary.override_model_count)
  local disposition_contract = DISPOSITIONS[disposition_status]
  if type(record.disposition) ~= "table" or record.disposition.terminal ~= true
    or record.disposition.status ~= disposition_status
    or record.disposition.reason_code ~= disposition_contract.reason_code
    or record.disposition.remediation_code ~= disposition_contract.remediation_code then
    error("Research-cost compatibility terminal disposition is invalid.", 3)
  end
  if not nonempty(record.semantic_set_fingerprint) or type(record.model_sample) ~= "table"
    or type(record.truncation) ~= "table" then
    error("Research-cost compatibility semantic projection is incomplete.", 3)
  end
  local included = math.min(record.summary.model_count, SAMPLE_LIMIT)
  if #record.model_sample ~= included or record.truncation.sample_limit ~= SAMPLE_LIMIT
    or record.truncation.included_model_rows ~= included
    or record.truncation.omitted_model_rows ~= record.summary.model_count - included
    or record.truncation.truncated ~= (record.summary.model_count > included) then
    error("Research-cost compatibility truncation accounting is invalid.", 3)
  end
  for _, sample in ipairs(record.model_sample) do
    if type(sample) ~= "table" or not nonempty(sample.subject_id)
      or not nonempty(sample.semantic_digest) or not nonempty(sample.qualification_digest)
      or type(sample.neutral_linear_increment) ~= "boolean" then
      error("Research-cost compatibility model sample is invalid.", 3)
    end
  end
  if type(record.privacy) ~= "table" or record.privacy.profile ~= "mir-public-support-allowlist-v1"
    or record.privacy.contains_paths ~= false or record.privacy.contains_mod_names ~= false
    or record.privacy.redacted_field_count ~= 0 then
    error("Research-cost compatibility privacy projection is invalid.", 3)
  end
  if type(record.linkage) ~= "table" then
    error("Research-cost compatibility compiler linkage is required.", 3)
  end
  for _, field in ipairs({
    "compiler_input_fingerprint", "compilation_fingerprint", "qualification_fingerprint",
    "compilation_plan_fingerprint", "planned_result_fingerprint", "compiler_result_fingerprint",
    "journal_fingerprint", "realized_output_fingerprint"
  }) do
    if not nonempty(record.linkage[field]) then
      error("Research-cost compatibility compiler linkage is missing: " .. field, 3)
    end
  end
  local assertion = record.proof_assertion
  if type(assertion) ~= "table" or assertion.schema ~= 1
    or assertion.assertion_type ~= ASSERTION_TYPE or assertion.proposition_id ~= PROPOSITION_ID
    or assertion.dimension ~= "SEMANTIC" or assertion.status ~= disposition_contract.proof_status
    or assertion.semantic_set_fingerprint ~= record.semantic_set_fingerprint
    or type(assertion.environment) ~= "table"
    or assertion.environment.factorio_line ~= record.current_target
    or not nonempty(assertion.environment.target_profile_fingerprint)
    or not nonempty(assertion.environment.environment_fingerprint)
    or type(assertion.evidence) ~= "table"
    or assertion.evidence.compiler_input_fingerprint ~= record.linkage.compiler_input_fingerprint
    or assertion.evidence.compilation_plan_fingerprint ~= record.linkage.compilation_plan_fingerprint
    or assertion.evidence.compiler_result_fingerprint ~= record.linkage.compiler_result_fingerprint
    or assertion.evidence.realized_output_fingerprint ~= record.linkage.realized_output_fingerprint
    or not nonempty(assertion.assertion_fingerprint)
    or assertion.assertion_fingerprint ~= fingerprint.of(assertion_material(assertion)) then
    error("Research-cost compatibility proof assertion is invalid.", 3)
  end
  if not nonempty(record.support_fingerprint)
    or record.support_fingerprint ~= fingerprint.of(support_material(record)) then
    error("Research-cost compatibility support fingerprint is invalid.", 3)
  end
  return true
end

local function add_model(rows, seen, subject_id, subject_kind, model)
  if model == nil then return end
  research_cost_model.assert_valid(model)
  if seen[subject_id] then
    error("Research-cost compatibility slice has a duplicate subject: " .. subject_id, 3)
  end
  seen[subject_id] = true
  table.insert(rows, {
    subject_id = subject_id,
    subject_kind = subject_kind,
    semantic_digest = model.semantic_digest,
    qualification_digest = model.qualification_digest,
    kind = model.derived_kind,
    anchor_level = model.anchor_level,
    neutral_linear_increment = model.linear_increment == 0
  })
end

local function collect_models(stream_plan, base_extension_operations)
  local rows, seen = {}, {}
  for _, row in ipairs((stream_plan and stream_plan.rows) or {}) do
    local model = row.fields and row.fields.cost_model
    if not model and row.adoption then model = row.adoption.research_cost_model end
    add_model(rows, seen, "stream/" .. tostring(row.stream_key), "stream", model)
  end
  for _, operation in ipairs(base_extension_operations or {}) do
    add_model(rows, seen, "base-continuation/" .. tostring(operation.key),
      "base-continuation", operation.research_cost_model)
  end
  table.sort(rows, function(left, right) return left.subject_id < right.subject_id end)
  return rows
end

function M.verify_untrusted(record)
  return verify(record)
end

function M.build(values)
  values = values or {}
  compiler_input.assert_trusted(values.compiler_input)
  compiler_result.assert_trusted(values.compiler_result)
  if values.compiler_result.result_phase ~= "final"
    or values.compiler_result.dimensions.execution ~= "APPLIED" then
    error("Research-cost compatibility support requires final APPLIED CompilerResult authority.", 2)
  end
  local environment = values.compiler_input.runtime_environment
  if type(environment) ~= "table" or environment.factorio_line ~= values.current_target then
    error("Research-cost compatibility support target differs from CompilerInput environment.", 2)
  end
  for _, field in ipairs({"compilation_fingerprint", "qualification_fingerprint"}) do
    if not nonempty(values[field]) then
      error("Research-cost compatibility build input is missing: " .. field, 2)
    end
  end
  local execution = values.compiler_result.execution_evidence
  if type(execution) ~= "table" then
    error("Research-cost compatibility support requires realized execution evidence.", 2)
  end
  local models = collect_models(values.stream_plan, values.base_extension_operations)
  local neutral_count = 0
  for _, row in ipairs(models) do
    if row.neutral_linear_increment then neutral_count = neutral_count + 1 end
  end
  local override_count = #models - neutral_count
  local disposition_status = expected_disposition(#models, override_count)
  local disposition_contract = DISPOSITIONS[disposition_status]
  local semantic_set_fingerprint = fingerprint.of(models)
  local linkage = {
    compiler_input_fingerprint = values.compiler_input.input_fingerprint,
    compilation_fingerprint = values.compilation_fingerprint,
    qualification_fingerprint = values.qualification_fingerprint,
    compilation_plan_fingerprint = values.compiler_result.compilation_plan_fingerprint,
    planned_result_fingerprint = values.compiler_result.planned_result_fingerprint,
    compiler_result_fingerprint = values.compiler_result.result_fingerprint,
    journal_fingerprint = execution.journal_fingerprint,
    realized_output_fingerprint = execution.realized_output_fingerprint
  }
  local assertion = {
    schema = 1,
    assertion_type = ASSERTION_TYPE,
    proposition_id = PROPOSITION_ID,
    dimension = "SEMANTIC",
    status = disposition_contract.proof_status,
    semantic_set_fingerprint = semantic_set_fingerprint,
    environment = {
      factorio_line = environment.factorio_line,
      target_profile_fingerprint = environment.target_profile_fingerprint,
      environment_fingerprint = environment.environment_fingerprint
    },
    evidence = {
      compiler_input_fingerprint = linkage.compiler_input_fingerprint,
      compilation_plan_fingerprint = linkage.compilation_plan_fingerprint,
      compiler_result_fingerprint = linkage.compiler_result_fingerprint,
      realized_output_fingerprint = linkage.realized_output_fingerprint
    }
  }
  assertion.assertion_fingerprint = fingerprint.of(assertion_material(assertion))
  local record = {
    schema = SCHEMA,
    kind = "mir-research-cost-support-public",
    abi = ABI,
    current_target = values.current_target,
    proposition = {
      id = PROPOSITION_ID,
      statement_code = "neutral-default-preserves-prior-cost-semantics",
      formula_abi = research_cost_model.formula_abi,
      required_linear_increment = 0
    },
    semantic_set_fingerprint = semantic_set_fingerprint,
    linkage = linkage,
    disposition = {
      terminal = true,
      status = disposition_status,
      reason_code = disposition_contract.reason_code,
      remediation_code = disposition_contract.remediation_code
    },
    proof_assertion = assertion,
    summary = {
      model_count = #models,
      neutral_model_count = neutral_count,
      override_model_count = override_count
    },
    model_sample = {},
    truncation = {
      sample_limit = SAMPLE_LIMIT,
      included_model_rows = math.min(#models, SAMPLE_LIMIT),
      omitted_model_rows = math.max(0, #models - SAMPLE_LIMIT),
      truncated = #models > SAMPLE_LIMIT
    },
    privacy = {
      profile = "mir-public-support-allowlist-v1",
      contains_paths = false,
      contains_mod_names = false,
      redacted_field_count = 0
    },
    target_dispositions = deepcopy(TARGET_DISPOSITIONS)
  }
  for index = 1, math.min(#models, SAMPLE_LIMIT) do
    record.model_sample[index] = deepcopy(models[index])
  end
  record.support_fingerprint = fingerprint.of(support_material(record))
  verify(record)
  return record
end

function M.target_dispositions()
  return deepcopy(TARGET_DISPOSITIONS)
end

return M
