local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local TRUST_CLASSES = {
  ["fixture-only"] = true,
  ["local-user"] = true,
  ["external-mod-author"] = true,
  ["mir-reviewed"] = true,
  ["protected-release"] = true
}
local REVIEWED_TRUST = { ["mir-reviewed"] = true, ["protected-release"] = true }

local function material(record)
  local out = {}
  for key, value in pairs(record) do if key ~= "promotion_fingerprint" then out[key] = value end end
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= 1 then
    error("PromotionAuthorization schema 1 record is required.", 2)
  end
  for _, field in ipairs({
    "authorization_id", "candidate_id", "design_fingerprint", "safety_qualification_fingerprint",
    "provider_id", "provider_version", "quality_policy_version", "trust_class"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("PromotionAuthorization field is required: " .. field, 2)
    end
  end
  if not TRUST_CLASSES[record.trust_class] or type(record.applicability_envelope) ~= "table"
    or type(record.profile_fingerprints) ~= "table" or type(record.quality_assessment_fingerprints) ~= "table"
    or type(record.upgrade_evidence_sha256) ~= "table" or type(record.performance_evidence_sha256) ~= "table"
    or type(record.human_review) ~= "table" or record.human_review.decision ~= "approved" then
    error("PromotionAuthorization evidence or trust material is invalid.", 2)
  end
  if record.promotion_fingerprint ~= fingerprint.of(material(record)) then
    error("PromotionAuthorization fingerprint is invalid.", 2)
  end
  return true
end

function M.new(record)
  local out = deepcopy(record or {})
  out.schema = 1
  out.profile_fingerprints = deepcopy(out.profile_fingerprints or {})
  out.quality_assessment_fingerprints = deepcopy(out.quality_assessment_fingerprints or {})
  out.upgrade_evidence_sha256 = deepcopy(out.upgrade_evidence_sha256 or {})
  out.performance_evidence_sha256 = deepcopy(out.performance_evidence_sha256 or {})
  out.promotion_fingerprint = fingerprint.of(material(out))
  M.validate(out)
  return out
end

function M.is_reviewed_trust(record)
  M.validate(record)
  return REVIEWED_TRUST[record.trust_class] == true
end

function M.schema_authority()
  return {
    schema = 1,
    trust_classes = {"fixture-only", "local-user", "external-mod-author", "mir-reviewed", "protected-release"},
    reviewed_mode_trust_classes = {"mir-reviewed", "protected-release"}
  }
end

return M
