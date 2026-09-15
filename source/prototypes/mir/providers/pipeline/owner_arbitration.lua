local competing_productivity = require("prototypes.mir.policy.competing_productivity")
local productivity_owners = require("prototypes.mir.index.productivity_owners")

local M = {}

function M.blocker(recipe_name)
  local owners = productivity_owners.blocking_recipe_productivity_owner_records(recipe_name, {
    ignore_owner = competing_productivity.ignores_existing_owner,
    snapshot_phase = "input"
  })
  if #owners > 0 then return "existing_recipe_productivity_owner" end
  return nil
end

return M
