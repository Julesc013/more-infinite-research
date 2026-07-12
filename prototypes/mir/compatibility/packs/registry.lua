local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local schema = require("prototypes.mir.compatibility.packs.schema")

local M = {}
local PROTOTYPE_NAME = "more-infinite-research-compatibility-pack"

local function snapshot()
  local prototype = data_raw.prototype("mod-data", PROTOTYPE_NAME)
  local packs = prototype and prototype.data and prototype.data.packs or {}
  local ids, out = {}, {}
  for id, _ in pairs(packs) do table.insert(ids, id) end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local pack = schema.validate(packs[id])
    if pack.id ~= id then
      error("CompatibilityPack transport key must match pack id: " .. tostring(id), 2)
    end
    table.insert(out, pack)
  end
  return out
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
