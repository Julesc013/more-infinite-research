local productivity_family_adoption = require("prototypes.mir.policy.productivity_family_adoption")

local M = {}

function M.plan_recipe_productivity_family(key, spec, buckets)
  return productivity_family_adoption.plan(key, spec, buckets)
end

return M
