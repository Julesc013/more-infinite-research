local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local schema = require("prototypes.mir.compatibility.packs.schema")

local M = {}
local PROTOTYPE_NAME = "more-infinite-research-compatibility-pack"

function M.active_known_competing_productivity_profiles()
  local out = {}
  local prototype = data_raw.prototype("mod-data", PROTOTYPE_NAME)
  local packs = prototype and prototype.data and prototype.data.packs or {}
  local ids = {}
  for id, _ in pairs(packs) do table.insert(ids, id) end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local pack = schema.validate(packs[id])
    if pack.known_competing_productivity then
      table.insert(out, {
        mod = "compatibility-pack:" .. pack.id,
        policy = pack.known_competing_productivity
      })
    end
  end
  return out
end

return M

