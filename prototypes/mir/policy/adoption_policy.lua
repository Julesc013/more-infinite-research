local productivity_family_adoption = require("prototypes.mir.policy.productivity_family_adoption")
local mod_data = require("prototypes.mir.emit.mod_data")

local M = {}

function M.adopt_recipe_productivity_family(key, spec, buckets)
  return productivity_family_adoption.adopt(key, spec, buckets)
end

function M.emit_mod_data()
  mod_data.emit_productivity_family_adoption(productivity_family_adoption.mod_data_payload())
end

return M
