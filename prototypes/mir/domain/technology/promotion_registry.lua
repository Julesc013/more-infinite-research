local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

-- MIR owns this source registry. A compatibility pack may reference an entry,
-- but cannot create or upgrade its trust class at runtime.
local RECORDS = {
  ["mir.reviewed.semantic-family-fixture-v1"] = {
    authorization_id = "mir.reviewed.semantic-family-fixture-v1",
    trust_class = "mir-reviewed",
    pack = "semantic-family-fixture",
    family = "assembling-machine-manufacturing",
    stream = "research_auto_assembling_machine",
    provider_version = "family-rule-v3",
    applicability_envelope = {mod = "mir-fixture-semantic-family-attach", version = "0.1.0"}
  },
  ["mir.reviewed.compiler-contract-fixture-v1"] = {
    authorization_id = "mir.reviewed.compiler-contract-fixture-v1",
    trust_class = "mir-reviewed",
    pack = "pack-operational",
    family = "assembling-machine-manufacturing",
    stream = "research_auto_assembling_machine",
    provider_version = "family-rule-v3",
    applicability_envelope = {fixture = "assert-compiler-contracts"}
  },
  ["mir.reviewed.upgrade-automatic-family-v1"] = {
    authorization_id = "mir.reviewed.upgrade-automatic-family-v1",
    trust_class = "mir-reviewed",
    pack = "mir-upgrade-automatic-family",
    family = "assembling-machine-manufacturing",
    stream = "research_auto_assembling_machine",
    provider_version = "family-rule-v3",
    applicability_envelope = {mod = "mir-fixture-assert-upgrade-3-1-9-to-3-2-0", version = "0.1.0"}
  }
}

local function material(record)
  local out = deepcopy(record)
  out.registry_fingerprint = nil
  return out
end

function M.resolve_reference(reference)
  if type(reference) ~= "table" or type(reference.promotion_authorization_id) ~= "string" then return nil end
  local authoritative = RECORDS[reference.promotion_authorization_id]
  if not authoritative then return nil end
  for _, field in ipairs({"trust_class", "pack", "family", "stream", "provider_version"}) do
    if reference[field] ~= nil and reference[field] ~= authoritative[field] then return nil end
  end
  local out = deepcopy(authoritative)
  out.promotion_verified = true
  out.registry_fingerprint = fingerprint.of(material(out))
  return out
end

function M.snapshot()
  local out = {}
  for _, record in pairs(RECORDS) do
    local copied = deepcopy(record)
    copied.registry_fingerprint = fingerprint.of(copied)
    table.insert(out, copied)
  end
  table.sort(out, function(left, right) return left.authorization_id < right.authorization_id end)
  return {schema = 1, records = out, trust_authority = "mir-owned-source"}
end

return M
