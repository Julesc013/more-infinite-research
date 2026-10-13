-- Classic deliberately trades broad automatic inference for bounded startup
-- work.  This module makes that selected contract visible before a player
-- re-saves an older factory under the reduced profile.
--
-- `on_load` cannot access LuaGameScript or persistent state.  It only
-- installs this module's one-shot first-tick callback; that callback reads
-- the current startup selection, notifies connected players, and removes
-- itself before doing any player work.
local compiler_profile = require("prototypes.mir.settings.compiler_profile")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}
M.requires_features = {"scripted_techs"}

local load_notice_scheduled = false

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

local function clear_load_notice_subscription()
  if load_notice_scheduled then
    script.on_event(defines.events.on_tick, nil)
    load_notice_scheduled = false
  end
end

local function deliver_deferred_load_notice()
  clear_load_notice_subscription()
  if classic_selected() then notify_connected_players(caption_for_existing_classic()) end
end

function M.on_init()
  if classic_selected() then notify_connected_players(caption_for_initial_classic()) end
end

function M.on_load()
  -- Factorio allows conditional event registration here, but not access to
  -- game/settings or writes to storage/global.  Do not move profile choice
  -- into this callback.
  if not load_notice_scheduled then
    load_notice_scheduled = true
    script.on_event(defines.events.on_tick, deliver_deferred_load_notice)
  end
end

function M.on_configuration_changed(event)
  clear_load_notice_subscription()
  if classic_selected() then notify_connected_players(caption_for_upgrade(event)) end
end

return M
