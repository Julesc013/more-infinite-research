local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local schema = require("prototypes.mir.compatibility.packs.schema")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local precedence = require("prototypes.mir.compatibility.packs.precedence")
local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}
local PROTOTYPE_NAME = "more-infinite-research-compatibility-pack"
local canonical_snapshot = nil

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function version_matches(constraint, actual)
  if constraint == nil or constraint == "" or constraint == "*" or constraint == "fixture" then return true end
  if actual == nil then return false end
  local function version_parts(value)
    local out = {}
    for part in tostring(value):gmatch("%d+") do table.insert(out, tonumber(part)) end
    return out
  end
  local function compare(left, right)
    local a, b = version_parts(left), version_parts(right)
    for index = 1, math.max(#a, #b) do
      local av, bv = a[index] or 0, b[index] or 0
      if av < bv then return -1 end
      if av > bv then return 1 end
    end
    return 0
  end
  for clause in tostring(constraint):gmatch("[^,]+") do
    local operator, expected
    for _, candidate_operator in ipairs({">=", "<=", ">", "<", "="}) do
      local escaped = candidate_operator:gsub("([^%w])", "%%%1")
      expected = clause:match("^%s*" .. escaped .. "%s*(.-)%s*$")
      if expected then operator = candidate_operator; break end
    end
    if not operator then operator, expected = "=", clause:match("^%s*(.-)%s*$") end
    local result = compare(actual, expected)
    if (operator == "=" and result ~= 0) or (operator == ">" and result <= 0)
      or (operator == "<" and result >= 0) or (operator == ">=" and result < 0)
      or (operator == "<=" and result > 0) then return false end
  end
  return true
end

local function candidate_record(candidate)
  if type(candidate) == "string" then return {id = candidate} end
  return candidate
end

local function matches_candidate(candidate, active_mods)
  candidate = candidate_record(candidate)
  local active_version = candidate and active_mods and active_mods[candidate.id]
  return active_version ~= nil and version_matches(candidate.version, active_version)
end

local function applicable(pack, factorio_line, active_mods)
  if not contains(pack.targets.factorio_lines, factorio_line) then return false end
  local any = pack.applicability.mods_any or pack.applicability.mods or {}
  local any_match = false
  for _, candidate in ipairs(any) do
    if matches_candidate(candidate, active_mods) then any_match = true; break end
  end
  if not any_match then return false end
  for _, candidate in ipairs(pack.applicability.mods_all or {}) do
    if not matches_candidate(candidate, active_mods) then return false end
  end
  for _, candidate in ipairs(pack.applicability.mods_none or {}) do
    if matches_candidate(candidate, active_mods) then return false end
  end
  return true
end

function M.compile(packs, context)
  context = context or {}
  packs = packs or {}
  local factorio_line = context.factorio_line or target_profiles.current().factorio_version
  local active_mods = context.active_mods or mods or {}
  local ids, out = {}, {}
  for id, _ in pairs(packs) do table.insert(ids, id) end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local pack = schema.validate(packs[id])
    if pack.id ~= id then
      error("CompatibilityPack transport key must match pack id: " .. tostring(id), 2)
    end
    if applicable(pack, factorio_line, active_mods) then table.insert(out, pack) end
  end
  return out
end

local function snapshot()
  if canonical_snapshot then return canonical_snapshot end
  local prototype = data_raw.prototype("mod-data", PROTOTYPE_NAME)
  local packs = prototype and prototype.data and prototype.data.packs or {}
  canonical_snapshot = M.compile(packs)
  return canonical_snapshot
end

function M.snapshot()
  return deepcopy(snapshot())
end

function M.active_count()
  return #snapshot()
end

function M.blocker_is_reviewable(blocker)
  return schema.is_reviewable_risk(blocker)
end

function M.authorizes_family_stream(stream_key, family, active_packs)
  for _, pack in ipairs(active_packs or snapshot()) do
    for _, row in ipairs(pack.family_authorizations or {}) do
      if row.action == "generate"
        and (row.stream == nil or row.stream == stream_key)
        and (family == nil or row.family == nil or row.family == family) then
        local out = deepcopy(row)
        out.pack = pack.id
        return out
      end
    end
  end
  return nil
end

function M.candidate_seeds(active_packs)
  local out = {}
  for _, pack in ipairs(active_packs or snapshot()) do
    for _, row in ipairs(pack.candidate_seeds or {}) do
      local seed = deepcopy(row)
      seed.pack = pack.id
      table.insert(out, seed)
    end
  end
  table.sort(out, function(a, b)
    if a.family ~= b.family then return a.family < b.family end
    if a.stream ~= b.stream then return a.stream < b.stream end
    if a.recipe ~= b.recipe then return a.recipe < b.recipe end
    return a.pack < b.pack
  end)
  return out
end

function M.active_known_competing_productivity_profiles()
  local out = {}
  for _, pack in ipairs(snapshot()) do
    local policy = pack.owner_claims.known_competing_productivity
    if policy then
      table.insert(out, {
        mod = "compatibility-pack:" .. pack.id,
        policy = policy
      })
    end
  end
  return out
end

local function selector_matches(row, context)
  if type(row) == "string" then return row == context.recipe end
  if row.recipe and row.recipe ~= context.recipe then return false end
  if row.item and row.item ~= context.item then return false end
  if row.family and row.family ~= context.family then return false end
  if row.stream and row.stream ~= context.stream then return false end
  return true
end

function M.resolve_candidate(context, active_packs)
  local signals = {}
  if context.blocker then
    table.insert(signals, {
      kind = "exact-deny", id = "safety:" .. context.blocker,
      action = "diagnose", reason = context.blocker
    })
  else
    table.insert(signals, {kind = "generic-structural", id = "generic:" .. context.family, action = "attach"})
  end
  for _, pack in ipairs(active_packs or snapshot()) do
    for _, row in ipairs(pack.exact.excludes or {}) do
      if selector_matches(row, context) then
        table.insert(signals, {kind = "exact-deny", id = pack.id .. ":exclude", action = "diagnose", reason = (type(row) == "table" and row.reason) or "compatibility_pack_exact_exclude"})
      end
    end
    for _, row in ipairs(pack.exact.includes or {}) do
      if selector_matches(row, context) then
        table.insert(signals, {kind = "exact-reviewed", id = pack.id .. ":include", action = "attach", change = type(row) == "table" and row.change or nil})
      end
    end
    for alias, value in pairs(pack.aliases or {}) do
      local family = type(value) == "table" and value.family or value
      if (alias == context.recipe or alias == context.item) and (family == nil or family == context.family) then
        table.insert(signals, {kind = "compatibility-pack-hint", id = pack.id .. ":alias:" .. alias, action = "attach", change = type(value) == "table" and value.change or nil})
      end
    end
    for _, row in ipairs(pack.family_hints or {}) do
      if selector_matches(row, context) then
        table.insert(signals, {kind = "compatibility-pack-hint", id = pack.id .. ":family-hint", action = "attach", change = type(row) == "table" and row.change or nil})
      end
    end
    for _, override in ipairs(pack.risk_overrides or {}) do
      if schema.is_reviewable_risk(context.blocker)
        and context.blocker == override.risk and selector_matches(override, context) then
        local kind = override.action == "allow-reviewed" and "exact-reviewed" or "exact-deny"
        table.insert(signals, {
          kind = kind, id = pack.id .. ":risk:" .. override.risk,
          action = override.action == "allow-reviewed" and "attach" or "diagnose",
          reason = override.risk, overrides_reason = override.action == "allow-reviewed" and override.risk or nil,
          change = override.change, pack = pack.id, evidence = deepcopy(override.evidence)
        })
      end
    end
  end
  return precedence.resolve(signals)
end

function M.science_roles_for_stream(stream_key, active_packs)
  local out = {}
  for _, pack in ipairs(active_packs or snapshot()) do
    for _, row in ipairs(pack.science_roles or {}) do
      if type(row) == "table" and (row.stream == nil or row.stream == stream_key) and row.pack then
        table.insert(out, {pack = row.pack, role = row.role or "include", source = pack.id})
      end
    end
  end
  table.sort(out, function(a, b)
    if a.pack ~= b.pack then return a.pack < b.pack end
    return a.source < b.source
  end)
  return out
end

return M
