local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

local CLAIM_LEVELS = {
  ["fixture-only"] = true,
  ["loads"] = true,
  ["observed"] = true,
  ["cooperates"] = true,
  ["diagnostic-only"] = true,
  ["partial-support"] = true,
  ["full-family-support"] = true,
  ["full-pack-support"] = true
}

local function fail(pack, message)
  error("CompatibilityPack " .. tostring(pack and pack.id or "<unknown>") .. ": " .. message, 3)
end

local function data_only(value, path)
  if type(value) == "function" then error("CompatibilityPack must be data-only: " .. path, 3) end
  if type(value) ~= "table" then return end
  for key, child in pairs(value) do data_only(child, path .. "." .. tostring(key)) end
end

local function require_table(pack, field)
  if type(pack[field]) ~= "table" then fail(pack, field .. " table is required") end
end

local function validate_applicability(pack)
  require_table(pack, "applicability")
  local mods = pack.applicability.mods
  if type(mods) ~= "table" or #mods == 0 then fail(pack, "applicability.mods must not be empty") end
  local seen = {}
  for _, candidate in ipairs(mods) do
    if type(candidate) ~= "table" or type(candidate.id) ~= "string" or candidate.id == "" then
      fail(pack, "each applicable mod requires an id")
    end
    if seen[candidate.id] then fail(pack, "duplicate applicable mod " .. candidate.id) end
    if candidate.version ~= nil and type(candidate.version) ~= "string" then
      fail(pack, "mod version constraint must be a string for " .. candidate.id)
    end
    seen[candidate.id] = true
  end
end

local function validate_owner_claims(pack)
  local policy = pack.owner_claims.known_competing_productivity
  if policy == nil then return end
  if type(policy) ~= "table" or type(policy.tech_patterns) ~= "table" or #policy.tech_patterns == 0 then
    fail(pack, "known competing productivity owner claim requires tech_patterns")
  end
  for _, pattern in ipairs(policy.tech_patterns) do
    if type(pattern) ~= "string" or pattern == "" then fail(pack, "technology patterns must be strings") end
  end
end

local function validate_risk_overrides(pack)
  for _, override in ipairs(pack.risk_overrides) do
    if type(override) ~= "table" or type(override.risk) ~= "string" then
      fail(pack, "risk override requires a risk id")
    end
    if override.action ~= "deny" and override.action ~= "allow-reviewed" then
      fail(pack, "risk override action must be deny or allow-reviewed")
    end
    if override.action == "allow-reviewed" and (type(override.evidence) ~= "table" or #override.evidence == 0) then
      fail(pack, "allow-reviewed risk overrides require named evidence")
    end
  end
end

function M.validate(pack)
  if type(pack) ~= "table" or pack.schema ~= 2 then
    error("CompatibilityPack schema must be 2", 2)
  end
  if type(pack.id) ~= "string" or pack.id == "" then
    error("CompatibilityPack id is required", 2)
  end
  data_only(pack, "compatibility_pack:" .. pack.id)
  validate_applicability(pack)
  for _, field in ipairs({
    "aliases",
    "exact",
    "family_hints",
    "science_roles",
    "owner_claims",
    "risk_overrides",
    "targets",
    "evidence",
    "claim"
  }) do
    require_table(pack, field)
  end
  if type(pack.exact.includes) ~= "table" or type(pack.exact.excludes) ~= "table" then
    fail(pack, "exact includes and excludes are required")
  end
  if type(pack.targets.factorio_lines) ~= "table" or #pack.targets.factorio_lines == 0 then
    fail(pack, "targets.factorio_lines must not be empty")
  end
  if type(pack.evidence.fixtures) ~= "table" or type(pack.evidence.real_mod) ~= "table" then
    fail(pack, "evidence.fixtures and evidence.real_mod are required")
  end
  if not CLAIM_LEVELS[pack.claim.level] then fail(pack, "unsupported claim level") end
  if type(pack.claim.public) ~= "boolean" then fail(pack, "claim.public boolean is required") end
  if pack.claim.level == "fixture-only" and pack.claim.public then
    fail(pack, "fixture-only packs cannot publish a claim")
  end
  validate_owner_claims(pack)
  validate_risk_overrides(pack)
  return deepcopy(pack)
end

return M
