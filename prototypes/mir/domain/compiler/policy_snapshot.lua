local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local execution_mode = require("prototypes.mir.domain.compiler.execution_mode")

local M = {}
local SCHEMA = 1
local REQUIRED_TABLES = {
  "effective_settings", "compatibility_policy", "stream_policy", "promotion_authority",
  "hard_gate_authority", "effect_contract_authority", "quality_profiles", "transformation_policy"
}

local function material(record)
  local out = deepcopy(record)
  out.policy_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "PolicySnapshot" then
    error("PolicySnapshot schema 1 record is required.", 2)
  end
  for _, field in ipairs(REQUIRED_TABLES) do
    if type(record[field]) ~= "table" then error("PolicySnapshot table field is required: " .. field, 2) end
  end
  if type(record.weapon_overlap_mode) ~= "string" or record.weapon_overlap_mode == "" then
    error("PolicySnapshot weapon overlap mode is required.", 2)
  end
  if execution_mode.normalize(record.execution_mode) ~= record.execution_mode
    or type(record.review_policy) ~= "table" then
    error("PolicySnapshot execution mode and review policy are required.", 2)
  end
  if record.settings_fingerprint ~= fingerprint.of(record.effective_settings)
    or record.compatibility_policy_fingerprint ~= fingerprint.of(record.compatibility_policy)
    or record.promotion_authority_fingerprint ~= fingerprint.of(record.promotion_authority)
    or record.hard_gate_authority_fingerprint ~= fingerprint.of(record.hard_gate_authority)
    or record.effect_contract_authority_fingerprint ~= fingerprint.of(record.effect_contract_authority)
    or record.quality_profile_fingerprint ~= fingerprint.of(record.quality_profiles) then
    error("PolicySnapshot authority fingerprint is invalid.", 2)
  end
  if record.policy_fingerprint ~= fingerprint.of(material(record)) then
    error("PolicySnapshot fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = SCHEMA
  record.record_type = "PolicySnapshot"
  for _, field in ipairs(REQUIRED_TABLES) do record[field] = record[field] or {} end
  record.weapon_overlap_mode = record.weapon_overlap_mode or "reject-overlap"
  record.execution_mode = execution_mode.normalize(record.execution_mode)
  record.review_policy = record.review_policy or {
    allow_unbudgeted_review = false,
    allow_release_review = false,
    fail_reviewed_mode = false
  }
  record.settings_fingerprint = fingerprint.of(record.effective_settings)
  record.compatibility_policy_fingerprint = fingerprint.of(record.compatibility_policy)
  record.promotion_authority_fingerprint = fingerprint.of(record.promotion_authority)
  record.hard_gate_authority_fingerprint = fingerprint.of(record.hard_gate_authority)
  record.effect_contract_authority_fingerprint = fingerprint.of(record.effect_contract_authority)
  record.quality_profile_fingerprint = fingerprint.of(record.quality_profiles)
  record.policy_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.snapshot(record)
  M.validate(record)
  return deepcopy(record)
end

return M
