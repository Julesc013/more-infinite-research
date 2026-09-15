-- Permission predicates only. The caller remains the native queue actor.
local M = {}

local function available(technology)
  if not technology.enabled or technology.researched or technology.prototype.research_trigger then return false end
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched then return false end
  end
  return true
end

function M.can_enqueue(player, technology, action)
  if not (player and player.valid and technology and technology.valid) then return false end
  if technology.force.index ~= player.force.index or not player.force.research_enabled then return false end
  if player.permission_group and not player.permission_group.allows_action(action) then return false end
  if not available(technology) then return false end
  for _, queued in ipairs(player.force.research_queue or {}) do
    if queued.name == technology.name then return false end
  end
  return true
end

return M
