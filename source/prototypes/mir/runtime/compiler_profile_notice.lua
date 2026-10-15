-- The saved `classic` value is a compatibility alias for the one Full
-- compiler.  Keep this lifecycle participant for coordinator compatibility,
-- but never subscribe an event that was not already active in the saved game.
local compiler_profile = require("prototypes.mir.settings.compiler_profile")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}
M.requires_features = {"scripted_techs"}

local function classic_selected()
  return compiler_profile.get(target_line.factorio_version) == "classic"
end

local function old_mir_version(event)
  local changes = event and event.mod_changes
  local change = type(changes) == "table" and changes["more-infinite-research"] or nil
  local version = change and change.old_version
  if type(version) == "string" and version ~= "" then return version end
  return nil
end

local function caption_for_initial_classic()
  return {"mir-message.classic-profile-initial-scope"}
end

local function caption_for_existing_classic()
  return {"mir-message.classic-profile-existing-save-scope"}
end

local function caption_for_upgrade(event)
  local old_version = old_mir_version(event)
  if old_version then
    return {"mir-message.classic-profile-upgrade-warning", old_version}
  end
  return caption_for_existing_classic()
end

local function notify_connected_players(caption)
  local players = game and game.connected_players
  if type(players) ~= "table" then return 0 end
  local delivered = 0
  for _, player in pairs(players) do
    if player and player.valid and type(player.print) == "function" then
      player.print(caption)
      delivered = delivered + 1
    end
  end
  return delivered
end

function M.on_init()
  if classic_selected() then notify_connected_players(caption_for_initial_classic()) end
end

function M.on_load()
  -- on_load cannot read game/settings or write persistent state.  The former
  -- deferred on_tick notice is retired: Full is the only active compiler, so
  -- loading a client must preserve the saved server's handler set exactly.
end

function M.on_configuration_changed(event)
  if classic_selected() then notify_connected_players(caption_for_upgrade(event)) end
end

return M
