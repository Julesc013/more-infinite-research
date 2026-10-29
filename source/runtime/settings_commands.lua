-- User-invoked profile export/check commands. Bootstrap owns registration;
-- this module owns no storage, events, startup application, or periodic work.
local catalogue = require("research.settings")
local codec = require("research.settings_profile")
local profiles = require("runtime.settings_profile")
local M = {}

local function player_for(command)
  if command and command.player_index then return game.get_player(command.player_index) end
end

local function reply(command, message)
  local player = player_for(command)
  if player then player.print(message) else log("[more-infinite-research] " .. message) end
end

local function export_options(parameter)
  local text = tostring(parameter or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local compact = false
  if text == "--compact" or text == "compact" then
    compact, text = true, ""
  elseif text:sub(1, 10) == "--compact " then
    compact, text = true, text:sub(11)
  elseif text:sub(1, 8) == "compact " then
    compact, text = true, text:sub(9)
  end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then text = "mir-settings-profile" end
  text = text:gsub("[^%w%._%-]", "-")
  if not text:match("%.txt$") then text = text .. ".txt" end
  return compact, "more-infinite-research/settings/" .. text
end

function M.export(command)
  command = command or {}
  local compact, filename = export_options(command.parameter)
  local effective = catalogue.effective_values(settings.startup, helpers)
  local player = player_for(command)
  local profile = codec.current_profile({
    names = catalogue.registered_names(),
    value_resolver = function(name) return effective[name] end,
    is_default = catalogue.is_default_value,
    compact = compact,
    metadata = {
      mir_version = script.active_mods["more-infinite-research"],
      factorio_version = helpers and helpers.game_version or nil,
      exported_by = player and player.name or "server",
      import_setting = catalogue.import_setting_name
    }
  })
  local encoded, err = codec.encode(profile, helpers)
  if not encoded then reply(command, "MIR settings export failed: " .. tostring(err)); return end
  if helpers and helpers.write_file then
    helpers.write_file(filename, encoded .. "\n", false, command.player_index)
  else
    -- Older supported engines expose this on game. Newer LuaObjects can
    -- throw on unknown members, so a missing compatibility API is a reply.
    local ok, write_file = pcall(function() return game and game.write_file end)
    if not ok or type(write_file) ~= "function" then
      reply(command, "MIR settings export failed: file export API is not available.")
      return
    end
    write_file(filename, encoded .. "\n", false, command.player_index)
  end
  reply(command, "MIR settings profile exported to script-output/" .. filename
    .. " (" .. tostring(codec.count_settings(profile)) .. " settings, "
    .. (compact and "compact" or "full") .. ").")
end

function M.validate(command)
  command = command or {}
  local result = profiles.validate_string(command.parameter or "")
  if not result.valid then reply(command, "Invalid MIR settings profile: " .. tostring(result.error)); return end
  reply(command, "Valid MIR settings profile: " .. tostring(result.recognized)
    .. " recognized settings, " .. tostring(result.invalid) .. " invalid values, "
    .. tostring(result.unknown) .. " ignored or unavailable settings. Paste it into startup setting "
    .. catalogue.import_setting_name .. " and restart to apply it.")
end

return M
