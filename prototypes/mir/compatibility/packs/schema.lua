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

local REVIEWABLE_RISKS = {
  hidden_recipe = true,
  name_based_recovery_or_voiding_heuristic = true,
  cleaning_or_recovery_loop = true,
  voiding_or_destruction = true,
  matter_or_transmutation = true,
  barrel_or_container_return = true,
  multi_output_resource_loop = true,
  family_ambiguity = true,
  tier_ambiguity = true,
  soft_science_role_refinement = true,
  reviewed_exact_exception = true
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
  local mods = pack.applicability.mods_any or pack.applicability.mods
  if type(mods) ~= "table" or #mods == 0 then fail(pack, "applicability.mods or mods_any must not be empty") end
  local seen = {}
  for _, group in ipairs({mods, pack.applicability.mods_all or {}, pack.applicability.mods_none or {}}) do
    for _, candidate in ipairs(group) do
      if type(candidate) == "string" then candidate = {id = candidate} end
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
end

local function has_exact_applicable_version(pack)
  local candidates = pack.applicability.mods_any or pack.applicability.mods or {}
  for _, candidate in ipairs(candidates) do
    if type(candidate) == "table" and type(candidate.version) == "string"
      and (candidate.version == "fixture" or candidate.version:match("^%s*=%s*%d")) then
      return true
    end
  end
  return false
end

local function evidence_index(pack)
  local out = {}
  for _, id in ipairs(pack.evidence.fixtures or {}) do out[id] = "fixture" end
  for _, id in ipairs(pack.evidence.real_mod or {}) do out[id] = "real_mod" end
  return out
end

local function validate_evidence_references(pack, references, context, require_fixture)
  if type(references) ~= "table" or #references == 0 then
    fail(pack, context .. " requires named evidence")
  end
  local known = evidence_index(pack)
  local fixture_found = false
  for _, id in ipairs(references) do
    if type(id) ~= "string" or id == "" or not known[id] then
      fail(pack, context .. " references unknown evidence " .. tostring(id))
    end
    if known[id] == "fixture" then fixture_found = true end
  end
  if require_fixture and not fixture_found then
    fail(pack, context .. " requires a dedicated fixture evidence id")
  end
end

local function validate_refinement_rows(pack, field, rows)
  for _, row in ipairs(rows or {}) do
    if type(row) ~= "string" and type(row) ~= "table" then
      fail(pack, field .. " rows must be strings or selector tables")
    end
    if type(row) == "table" and row.recipe == nil and row.item == nil and row.family == nil and row.stream == nil then
      fail(pack, field .. " selector requires recipe, item, family, or stream")
    end
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
    if override.action == "allow-reviewed" then
      if not REVIEWABLE_RISKS[override.risk] then
        fail(pack, "allow-reviewed cannot override hard risk " .. override.risk)
      end
      if type(override.recipe) ~= "string" or override.recipe == "" then
        fail(pack, "allow-reviewed risk overrides require an exact recipe selector")
      end
      if not has_exact_applicable_version(pack) then
        fail(pack, "allow-reviewed risk overrides require an exact applicable mod version")
      end
      validate_evidence_references(pack, override.evidence, "allow-reviewed risk override", true)
    end
  end
end

local function validate_family_authorizations(pack)
  for _, row in ipairs(pack.family_authorizations) do
    if type(row) ~= "table" or row.action ~= "generate" then
      fail(pack, "family authorization action must be generate")
    end
    if (type(row.family) ~= "string" or row.family == "")
      and (type(row.stream) ~= "string" or row.stream == "") then
      fail(pack, "family authorization requires a family or stream")
    end
    if type(row.claim_boundary) ~= "string" or row.claim_boundary == "" then
      fail(pack, "family authorization requires a claim boundary")
    end
    if not has_exact_applicable_version(pack) then
      fail(pack, "family authorization requires an exact applicable mod version")
    end
    validate_evidence_references(pack, row.evidence, "family authorization", true)
  end
end

local function validate_candidate_seeds(pack)
  for _, row in ipairs(pack.candidate_seeds) do
    if type(row) ~= "table" or type(row.recipe) ~= "string" or row.recipe == "" then
      fail(pack, "candidate seed requires an exact recipe")
    end
    if type(row.family) ~= "string" or row.family == "" or type(row.stream) ~= "string" or row.stream == "" then
      fail(pack, "candidate seed requires an existing family and stable stream")
    end
    if row.item ~= nil and (type(row.item) ~= "string" or row.item == "") then
      fail(pack, "candidate seed item must be an exact item id")
    end
    if row.tier ~= nil and type(row.tier) ~= "number" then
      fail(pack, "candidate seed tier must be numeric")
    end
    if type(row.change) ~= "number" or row.change <= 0 then
      fail(pack, "candidate seed requires a positive change")
    end
    if not has_exact_applicable_version(pack) then
      fail(pack, "candidate seed requires an exact applicable mod version")
    end
    validate_evidence_references(pack, row.evidence, "candidate seed", true)
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
    "family_authorizations",
    "candidate_seeds",
    "targets",
    "evidence",
    "claim"
  }) do
    require_table(pack, field)
  end
  if type(pack.exact.includes) ~= "table" or type(pack.exact.excludes) ~= "table" then
    fail(pack, "exact includes and excludes are required")
  end
  validate_refinement_rows(pack, "exact.includes", pack.exact.includes)
  validate_refinement_rows(pack, "exact.excludes", pack.exact.excludes)
  validate_refinement_rows(pack, "family_hints", pack.family_hints)
  validate_refinement_rows(pack, "science_roles", pack.science_roles)
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
  validate_family_authorizations(pack)
  validate_candidate_seeds(pack)
  return deepcopy(pack)
end

function M.is_reviewable_risk(risk)
  return REVIEWABLE_RISKS[risk] == true
end

return M
