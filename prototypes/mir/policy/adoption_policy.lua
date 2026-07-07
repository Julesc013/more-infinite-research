local productivity_family_adoption = require("prototypes.mir.policy.productivity_family_adoption")

local M = {}

function M.adopt_recipe_productivity_family(key, spec, buckets)
  return productivity_family_adoption.adopt(key, spec, buckets)
end

function M.emit_mod_data()
  productivity_family_adoption.emit_mod_data()
end

return M
