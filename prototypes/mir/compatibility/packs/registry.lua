local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local schema = require("prototypes.mir.compatibility.packs.schema")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")

local M = {}
local PROTOTYPE_NAME = "more-infinite-research-compatibility-pack"

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function version_matches(constraint, actual)
  if constraint == nil or constraint == "" or constraint == "*" or constraint == "fixture" then return true end
  if actual == nil then return false end
  local exact = string.match(constraint, "^=%s*(.+)$") or constraint
  return tostring(actual) == exact
end

local function applicable(pack, factorio_line, active_mods)
  if not contains(pack.targets.factorio_lines, factorio_line) then return false end
  for _, candidate in ipairs(pack.applicability.mods or {}) do
    local active_version = active_mods and active_mods[candidate.id]
    if active_version and version_matches(candidate.version, active_version) then return true end
  end
  return false
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
  local prototype = data_raw.prototype("mod-data", PROTOTYPE_NAME)
  local packs = prototype and prototype.data and prototype.data.packs or {}
  return M.compile(packs)
end

function M.snapshot()
  return snapshot()
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

return M
