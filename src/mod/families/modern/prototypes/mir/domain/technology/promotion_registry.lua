local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local generated = require("prototypes.mir.domain.technology.generated_promotion_registry")

-- MIR owns this source registry. A compatibility pack may reference an entry,
-- but cannot create or upgrade its trust class at runtime.
local RECORDS = {}
for _, record in ipairs(generated.authorizations or {}) do
  if RECORDS[record.authorization_id] then error("Duplicate generated promotion authorization: " .. record.authorization_id) end
  RECORDS[record.authorization_id] = deepcopy(record)
end

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
  return {
    schema = 1,
    records = out,
    trust_authority = "mir-owned-source",
    governance_authority = generated.authority,
    approvals = deepcopy(generated.approvals),
    promotions = deepcopy(generated.promotions),
    applicability_envelopes = deepcopy(generated.applicability_envelopes),
    migrations = deepcopy(generated.migrations)
  }
end

return M
