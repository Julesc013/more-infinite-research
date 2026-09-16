local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1
local STATES = {
  unassigned = true, provisional = true, reserved = true,
  ["stable-unreleased"] = true, released = true, retired = true
}
local TRANSITIONS = {
  unassigned = {provisional = true},
  provisional = {reserved = true},
  reserved = {["stable-unreleased"] = true},
  ["stable-unreleased"] = {released = true},
  released = {retired = true},
  retired = {}
}

local function material(record)
  return {
    schema = record.schema,
    promotion_id = record.promotion_id,
    technology_id = record.technology_id,
    candidate_id = record.candidate_id,
    approval_id = record.approval_id,
    approved_design_fingerprint = record.approved_design_fingerprint,
    prior_identity_state = record.prior_identity_state,
    identity_state = record.identity_state,
    migration_policy = record.migration_policy,
    introduced_in = record.introduced_in,
    evidence = record.evidence
  }
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    identity_states = {"unassigned", "provisional", "reserved", "stable-unreleased", "released", "retired"},
    transitions = deepcopy(TRANSITIONS)
  }
end

function M.assert_transition(before, after)
  if not STATES[before] or not STATES[after] or not (TRANSITIONS[before] and TRANSITIONS[before][after]) then
    error("TechnologyPromotion identity transition is not permitted: " .. tostring(before) .. " -> " .. tostring(after), 2)
  end
  return true
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA then
    error("TechnologyPromotion schema 1 record is required.", 2)
  end
  for _, field in ipairs({
    "promotion_id", "technology_id", "candidate_id", "approval_id", "approved_design_fingerprint",
    "prior_identity_state", "identity_state", "migration_policy", "introduced_in"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TechnologyPromotion field is required: " .. field, 2)
    end
  end
  if type(record.evidence) ~= "table" then error("TechnologyPromotion evidence is required.", 2) end
  M.assert_transition(record.prior_identity_state, record.identity_state)
  if record.promotion_fingerprint ~= fingerprint.of(material(record)) then
    error("TechnologyPromotion fingerprint is invalid.", 2)
  end
  return true
end

function M.new(record)
  local out = deepcopy(record or {})
  out.schema = SCHEMA
  out.evidence = deepcopy(out.evidence or {})
  out.promotion_fingerprint = fingerprint.of(material(out))
  M.validate(out)
  return out
end

return M
