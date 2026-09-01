local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1
local STRATEGIES = {
  ["retain-hidden-alias"] = true,
  ["retain-visible-alias"] = true,
  ["in-place-compatible"] = true,
  ["retire-with-replacement"] = true
}

local function material(record)
  return {
    schema = record.schema,
    migration_id = record.migration_id,
    from_technology_id = record.from_technology_id,
    to_technology_id = record.to_technology_id,
    strategy = record.strategy,
    save_behavior = record.save_behavior,
    approval_id = record.approval_id,
    evidence = record.evidence
  }
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    strategies = {
      "retain-hidden-alias", "retain-visible-alias", "in-place-compatible", "retire-with-replacement"
    }
  }
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA then
    error("TechnologyMigration schema 1 record is required.", 2)
  end
  for _, field in ipairs({
    "migration_id", "from_technology_id", "to_technology_id", "strategy", "save_behavior", "approval_id"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TechnologyMigration field is required: " .. field, 2)
    end
  end
  if not STRATEGIES[record.strategy] or type(record.evidence) ~= "table" then
    error("TechnologyMigration strategy or evidence is invalid.", 2)
  end
  if record.from_technology_id == record.to_technology_id and record.strategy ~= "in-place-compatible" then
    error("TechnologyMigration identity-preserving changes require in-place-compatible strategy.", 2)
  end
  if record.migration_fingerprint ~= fingerprint.of(material(record)) then
    error("TechnologyMigration fingerprint is invalid.", 2)
  end
  return true
end

function M.new(record)
  local out = deepcopy(record or {})
  out.schema = SCHEMA
  out.evidence = deepcopy(out.evidence or {})
  out.migration_fingerprint = fingerprint.of(material(out))
  M.validate(out)
  return out
end

return M
