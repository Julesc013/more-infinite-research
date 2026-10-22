-- Explicit control-stage composition for the private MIR5 Library slice.
--
-- Modules are loaded at control parse time. This is deliberately a small,
-- named set of bindings rather than a generic event dispatcher: lifecycle
-- remains the sole cap-policy owner and the Library owns only its own view
-- callbacks.
local lifecycle = require("runtime.lifecycle")
local library = require("runtime.library")
local runtime_api = require("api.v1.runtime")

local M = {}

local API_INTERFACE = "more-infinite-research.api.v1"
local BROWSER_INTERFACE = "more-infinite-research-browser"

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function player_for(index)
  if type(index) ~= "number" or not game or type(game.get_player) ~= "function" then return nil end
  local ok, player = pcall(function() return game.get_player(index) end)
  if not ok or not valid(player) then return nil end
  return player
end

local function browser_options(player, options)
  if type(options) ~= "table" then return nil end
  local result = {}
  if type(options.search) == "string" then result.query = options.search end
  if options.family == "all" or options.family == "mir" then result.family = options.family end

  -- The legacy interface admitted only technologies known to the caller's
  -- native force. Keep that boundary without asking the Library model to
  -- index an arbitrary LuaCustomTable key.
  if type(options.selected) == "string" and options.selected ~= "" and #options.selected <= 160 then
    local ok, technology = pcall(function()
      local force = player.force
      local technologies = force and force.technologies
      return technologies and technologies[options.selected] or nil
    end)
    if ok and valid(technology) then result.selected = options.selected end
  end
  return result
end

local function open_browser(player_index, options)
  local player = player_for(player_index)
  if not player then return false end
  return library.open(player, browser_options(player, options)) ~= nil
end

local function register_interface(name, members, label)
  if not remote or type(remote.add_interface) ~= "function" then
    error("MIR runtime remote interface support is unavailable: " .. name)
  end
  if remote.interfaces and remote.interfaces[name] ~= nil then
    error("MIR " .. label .. " interface collision: " .. name)
  end
  remote.add_interface(name, members)
end

local function add_command()
  -- The guard only accommodates the pure-Lua host controls. Factorio always
  -- supplies commands.add_command to a control-stage mod.
  if not commands or type(commands.add_command) ~= "function" then return end
  commands.add_command("mir-research", {"mir-browser.command"}, function(event)
    local player = player_for(event and event.player_index)
    if player then library.open(player) end
  end)
end

local function on_init()
  lifecycle.on_init()
  library.on_init()
end

local function on_configuration_changed(event)
  lifecycle.on_configuration_changed(event)
  library.on_configuration_changed(event)
end

local function on_load()
  lifecycle.on_load()
  library.on_load()
end

function M.register()
  library.set_cap_provider(lifecycle.cap_limits)

  register_interface(API_INTERFACE, {
    get_version = runtime_api.get_version,
    get_capabilities = runtime_api.get_capabilities,
    get_research = runtime_api.get_research
  }, "API")
  register_interface(BROWSER_INTERFACE, {open = open_browser}, "Research Library")
  add_command()

  if script and type(script.on_init) == "function" then script.on_init(on_init) end
  if script and type(script.on_configuration_changed) == "function" then
    script.on_configuration_changed(on_configuration_changed)
  end
  if script and type(script.on_load) == "function" then script.on_load(on_load) end

  local events = defines and defines.events or {}
  if lifecycle.caps_active() then
    if events.on_force_created then script.on_event(events.on_force_created, lifecycle.on_force_created) end
    if events.on_force_reset then script.on_event(events.on_force_reset, lifecycle.on_force_reset) end
    if events.on_forces_merged then script.on_event(events.on_forces_merged, lifecycle.on_forces_merged) end
    if events.on_research_finished then script.on_event(events.on_research_finished, lifecycle.on_research_finished) end
    if events.on_research_started then script.on_event(events.on_research_started, lifecycle.on_research_started) end
    if events.on_research_cancelled then script.on_event(events.on_research_cancelled, lifecycle.on_research_cancelled) end
  else
    -- A settings/profile transition may reuse the control registration from a
    -- finite save. Remove those exact native callbacks when all cap families
    -- are unlimited; otherwise their previous closures remain active.
    if events.on_force_created then script.on_event(events.on_force_created, nil) end
    if events.on_force_reset then script.on_event(events.on_force_reset, nil) end
    if events.on_forces_merged then script.on_event(events.on_forces_merged, nil) end
    if events.on_research_finished then script.on_event(events.on_research_finished, nil) end
    if events.on_research_started then script.on_event(events.on_research_started, nil) end
    if events.on_research_cancelled then script.on_event(events.on_research_cancelled, nil) end
  end
  if events.on_lua_shortcut then script.on_event(events.on_lua_shortcut, library.on_lua_shortcut) end
  if events.on_gui_text_changed then script.on_event(events.on_gui_text_changed, library.on_gui_text_changed) end
  if events.on_gui_selection_state_changed then script.on_event(events.on_gui_selection_state_changed, library.on_gui_selection_state_changed) end
  if events.on_gui_click then script.on_event(events.on_gui_click, library.on_gui_click) end
  if events.on_gui_location_changed then script.on_event(events.on_gui_location_changed, library.on_gui_location_changed) end
  if events.on_gui_closed then script.on_event(events.on_gui_closed, library.on_gui_closed) end
  if events.on_player_removed then script.on_event(events.on_player_removed, library.on_player_removed) end
end

return M
