local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}

function M.emit_productivity_family_adoption(payload)
  if not payload then return end

  data_raw.extend({
    {
      type = "mod-data",
      name = payload.name,
      data_type = payload.data_type,
      data = payload.data
    }
  })
end

return M
