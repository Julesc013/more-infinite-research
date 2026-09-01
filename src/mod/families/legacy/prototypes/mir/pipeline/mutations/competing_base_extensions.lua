local policy = require("prototypes.mir.policy.competing_base_extensions")
local replacement = require("prototypes.mir.emit.technology_replacement")

local M = {}

function M.apply()
  for _, command in ipairs(policy.replacement_plan()) do
    if command.replacement then
      local replaced, reason = replacement.replace_technology(command.technology, command.replacement)
      if replaced then
        log("[more-infinite-research] Replaced competing base extension technology from "
          .. command.mod .. " for " .. command.key .. ": " .. command.technology .. " -> " .. command.replacement)
      else
        log("[more-infinite-research] Retained competing base extension technology because replacement was unsafe: "
          .. command.technology .. " reason=" .. tostring(reason))
      end
    else
      log("[more-infinite-research] Retained competing base extension technology because MIR emitted no replacement: "
        .. command.technology)
    end
  end
end

return M
