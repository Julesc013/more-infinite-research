local policy = require("prototypes.mir.policy.competing_base_extensions")
local replacement = require("prototypes.mir.emit.technology_replacement")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

local function replacement_survives_cap(command)
  local technology = command.replacement and data_raw.technology(command.replacement)
  if not technology then return false end
  local cap = tonumber(effective_settings.get("mir-max-level-" .. tostring(command.key)))
  local first_level = tonumber(technology.level)
  return not (cap and cap > 0 and first_level and cap < first_level)
end

function M.apply(context)
  local journal = context:state_view("technology_replacement_journal", replacement.new_journal)
  for _, command in ipairs(policy.replacement_plan()) do
    if command.replacement and replacement_survives_cap(command) then
      local replaced, reason = replacement.replace_technology(command.technology, command.replacement, {
        journal = journal,
        source = "competing-base-extension",
        metadata = {mod = command.mod, key = command.key}
      })
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
