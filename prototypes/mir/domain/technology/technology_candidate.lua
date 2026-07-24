local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}
local SCHEMA = 1
local authority = trusted_record.new("TechnologyCandidate")

local function sorted_unique(values)
  local seen, out = {}, {}
  for _, value in ipairs(values or {}) do
    if type(value) ~= "string" or value == "" then
      error("TechnologyCandidate string collection is invalid.", 3)
    end
    if not seen[value] then
      seen[value] = true
      table.insert(out, value)
    end
  end
  table.sort(out)
  return out
end

local function candidate_material(candidate)
  return {
    schema = candidate.schema,
    candidate_id = candidate.candidate_id,
    semantic_identity = candidate.semantic_identity,
    subjects = candidate.subjects,
    discovery = candidate.discovery
  }
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    required = {"candidate_id", "semantic_identity", "subjects", "discovery", "candidate_fingerprint"},
    discovery_required = {"provider_ids", "family_ids", "source", "evidence", "feature_signature"}
  }
end

local function trust_identity(candidate)
  return {
    schema = candidate.schema,
    candidate_id = candidate.candidate_id,
    candidate_fingerprint = candidate.candidate_fingerprint
  }
end

local function trust_identity_unchanged(candidate, registered)
  return candidate.schema == registered.schema
    and candidate.candidate_id == registered.candidate_id
    and candidate.candidate_fingerprint == registered.candidate_fingerprint
end

local function verify(candidate)
  if type(candidate) ~= "table" or candidate.schema ~= SCHEMA then
    error("TechnologyCandidate schema 1 record is required.", 2)
  end
  if type(candidate.candidate_id) ~= "string" or candidate.candidate_id == "" then
    error("TechnologyCandidate candidate_id is required.", 2)
  end
  local identity = candidate.semantic_identity
  if type(identity) ~= "table"
    or type(identity.capability) ~= "string" or identity.capability == ""
    or type(identity.family) ~= "string" or identity.family == ""
    or type(identity.partition) ~= "string" or identity.partition == "" then
    error("TechnologyCandidate semantic identity is invalid.", 2)
  end
  local design_schema = technology_design.schema_authority()
  if type(candidate.subjects) ~= "table" then
    error("TechnologyCandidate typed subjects are required.", 2)
  end
  for _, category in ipairs(design_schema.subject_categories) do
    if type(candidate.subjects[category]) ~= "table" then
      error("TechnologyCandidate subject category is missing: " .. category, 2)
    end
  end
  local discovery = candidate.discovery
  if type(discovery) ~= "table"
    or type(discovery.provider_ids) ~= "table"
    or type(discovery.family_ids) ~= "table"
    or type(discovery.source) ~= "string" or discovery.source == ""
    or type(discovery.evidence) ~= "table"
    or type(discovery.feature_signature) ~= "string" or discovery.feature_signature == "" then
    error("TechnologyCandidate discovery record is invalid.", 2)
  end
  if candidate.candidate_fingerprint ~= fingerprint.of(candidate_material(candidate)) then
    error("TechnologyCandidate fingerprint is invalid.", 2)
  end
  return true
end

function M.verify_untrusted(candidate)
  authority.verify_untrusted(candidate, verify, trust_identity(candidate or {}))
  return true
end

function M.validate(candidate)
  return M.verify_untrusted(candidate)
end

function M.assert_trusted(candidate)
  return authority.assert_trusted(candidate, trust_identity_unchanged)
end

function M.is_trusted(candidate)
  return authority.is_trusted(candidate)
end

function M.from_design(design, row, options)
  if options and options.validated then technology_design.assert_trusted(design)
  else technology_design.verify_untrusted(design) end
  row = row or {}
  local provider_ids = sorted_unique(row.provider_ids or {})
  local family_ids = sorted_unique(row.family_ids or {})
  local candidate = {
    schema = SCHEMA,
    candidate_id = design.candidate_id,
    semantic_identity = deepcopy(design.semantic_identity),
    subjects = deepcopy(design.subjects),
    discovery = {
      provider_ids = provider_ids,
      family_ids = family_ids,
      source = row.source or "technology-design",
      evidence = {
        manifest_id = row.manifest_id,
        stream_key = row.stream_key,
        action = row.action,
        design_maturity = design.maturity.design_maturity,
        discovery_evidence = design.maturity.discovery_evidence
      },
      feature_signature = fingerprint.of({
        semantic_identity = design.semantic_identity,
        subjects = design.subjects,
        provider_ids = provider_ids,
        family_ids = family_ids,
        source = row.source,
        spec = row.spec
      })
    }
  }
  candidate.candidate_fingerprint = fingerprint.of(candidate_material(candidate))
  verify(candidate)
  return authority.register(candidate, trust_identity(candidate))
end

return M
