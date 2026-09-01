local policy = require("prototypes.mir.policy.competing_productivity")
local replacement = require("prototypes.mir.emit.technology_replacement")

local M = {}

function M.apply()
  for _, command in ipairs(policy.replacement_plan()) do
    if #command.replacements > 0 then
      local replaced, reason = replacement.replace_technology(command.technology, command.replacements)
      if replaced then
        log("[more-infinite-research] Replaced competing recipe productivity technology: "
          .. command.technology .. " -> " .. table.concat(command.replacements, ","))
      else
        log("[more-infinite-research] Retained competing recipe productivity technology because replacement was unsafe: "
          .. command.technology .. " reason=" .. tostring(reason))
      end
    else
      log("[more-infinite-research] Retained competing recipe productivity technology because MIR did not emit complete replacement coverage: "
        .. command.technology)
    end
  end
end

return M
