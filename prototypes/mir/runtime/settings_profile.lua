local profile_codec = require("prototypes.mir.settings.profile_codec")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

local function player_for(command)
  if command and command.player_index then
    return game.get_player(command.player_index)
  end
  return nil
end

local function reply(command, message)
  local player = player_for(command)
  if player then
    player.print(message)
  else
    log("[more-infinite-research] " .. message)
  end
end

local function sanitized_export_name(parameter)
  local name = tostring(parameter or "")
  name = string.gsub(name, "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then name = "mir-settings-profile" end
  name = string.gsub(name, "[^%w%._%-]", "-")
  if not string.match(name, "%.txt$") then name = name .. ".txt" end
  return name
end

local function write_export_file(filename, data, player_index)
  if helpers and helpers.write_file then
    helpers.write_file(filename, data, false, player_index)
    return true
  end

  if game and game.write_file then
    game.write_file(filename, data, false, player_index)
    return true
  end

  return false
end

local function export_metadata(command)
  local player = player_for(command)
  return {
    mir_version = script.active_mods["more-infinite-research"],
    factorio_version = helpers and helpers.game_version or nil,
    exported_by = player and player.name or "server",
    import_setting = profile_codec.import_setting_name
  }
end

local function export_profile(command)
  local profile = profile_codec.current_profile({
    value_resolver = effective_settings.get,
    metadata = export_metadata(command)
  })
  local encoded, err = profile_codec.encode(profile)
  if not encoded then
    reply(command, "MIR settings export failed: " .. tostring(err))
    return
  end

  local filename = "more-infinite-research/settings/" .. sanitized_export_name(command.parameter)
  if not write_export_file(filename, encoded .. "\n", command.player_index) then
    reply(command, "MIR settings export failed: file export API is not available.")
    return
  end

  reply(command, "MIR settings profile exported to script-output/" .. filename
    .. " (" .. tostring(profile_codec.count_settings(profile)) .. " settings).")
end

local function validate_profile(command)
  local text = command.parameter or ""
  local profile, err = profile_codec.decode(text)
  if not profile then
    reply(command, "Invalid MIR settings profile: " .. tostring(err))
    return
  end

  local recognized, unknown = profile_codec.count_recognized_settings(profile)
  reply(command, "Valid MIR settings profile: "
    .. tostring(recognized)
    .. " recognized settings, "
    .. tostring(unknown)
    .. " ignored or unavailable settings. Paste it into startup setting "
    .. profile_codec.import_setting_name
    .. " and restart to apply it.")
end

function M.register()
  commands.add_command(
    "mir-settings-export",
    "Export the current effective MIR startup settings to script-output/more-infinite-research/settings/<name>.txt.",
    export_profile
  )

  commands.add_command(
    "mir-settings-import-check",
    "Validate a MIR settings profile string before pasting it into the mir-settings-profile-import startup setting.",
    validate_profile
  )

  remote.add_interface("more-infinite-research-settings", {
    export_string = function()
      local profile = profile_codec.current_profile({
        value_resolver = effective_settings.get,
        metadata = {
          mir_version = script.active_mods["more-infinite-research"],
          factorio_version = helpers and helpers.game_version or nil,
          import_setting = profile_codec.import_setting_name
        }
      })
      local encoded, err = profile_codec.encode(profile)
      if not encoded then return nil, err end
      return encoded
    end,
    validate_string = function(text)
      local profile, err = profile_codec.decode(text)
      if not profile then
        return {
          valid = false,
          error = err
        }
      end

      local recognized, unknown = profile_codec.count_recognized_settings(profile)
      return {
        valid = true,
        recognized = recognized,
        unknown = unknown,
        import_setting = profile_codec.import_setting_name
      }
    end
  })
end

return M
