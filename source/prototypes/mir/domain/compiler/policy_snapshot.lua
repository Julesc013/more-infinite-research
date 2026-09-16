local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local execution_mode = require("prototypes.mir.domain.compiler.execution_mode")

local M = {}
local authority = trusted_record.new("PolicySnapshot")
local SCHEMA = 1
local REQUIRED_TABLES = {
  "effective_settings", "compatibility_policy", "stream_policy", "promotion_authority",
  "hard_gate_authority", "effect_contract_authority", "quality_profiles", "transformation_policy"
}

local function material(record)
  local out = {}
  for key, value in pairs(record or {}) do
    if key ~= "policy_fingerprint" then out[key] = value end
  end
  return out
end

local function trust_identity(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    policy_fingerprint = record.policy_fingerprint,
    execution_mode = record.execution_mode,
    weapon_overlap_mode = record.weapon_overlap_mode
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.record_type == registered.record_type
    and record.policy_fingerprint == registered.policy_fingerprint
    and record.execution_mode == registered.execution_mode
    and record.weapon_overlap_mode == registered.weapon_overlap_mode
end

local function verify(record, options)
  options = options or {}
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
  if options.verify_fingerprints ~= false and
    (record.settings_fingerprint ~= fingerprint.of(record.effective_settings)
    or record.compatibility_policy_fingerprint ~= fingerprint.of(record.compatibility_policy)
    or record.promotion_authority_fingerprint ~= fingerprint.of(record.promotion_authority)
    or record.hard_gate_authority_fingerprint ~= fingerprint.of(record.hard_gate_authority)
    or record.effect_contract_authority_fingerprint ~= fingerprint.of(record.effect_contract_authority)
    or record.quality_profile_fingerprint ~= fingerprint.of(record.quality_profiles)) then
    error("PolicySnapshot authority fingerprint is invalid.", 2)
  end
  if options.verify_fingerprints ~= false
    and record.policy_fingerprint ~= fingerprint.of(material(record)) then
    error("PolicySnapshot fingerprint is invalid.", 2)
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
  verify(record, {verify_fingerprints = false})
  return authority.register(record, trust_identity(record))
end

function M.snapshot(record)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  authority.count_snapshot()
  authority.count_full_copy()
  return deepcopy(record)
end

return M
