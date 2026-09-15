local policy_authority = require("prototypes.mir.compatibility.policy_authority")

local M = {}

function M.resolve(rule, stream, candidate, blocker)
  return policy_authority.resolve_candidate({
    recipe = candidate.recipe,
    item = candidate.item,
    family = rule.id,
    stream = stream,
    blocker = blocker
  })
end

return M
