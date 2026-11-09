-- Test-only: render the public Library. No synthetic input or player-code import.
local BROWSER = "more-infinite-research-browser"
local ROOT = "mir_research_browser"
local CASES = {
  {id = "01-research", tab = "research", search = "", visibility = 1},
  {id = "02-queue", tab = "queue"},
  {id = "03-settings-research", tab = "settings", settings_scope = "research", settings_search = ""},
  {id = "04-settings-options", tab = "settings", settings_scope = "options", settings_search = ""},
  {id = "05-help", tab = "help"},
  {id = "06-availability", tab = "availability", search = ""},
  {id = "07-research-filtered", tab = "research", search = "robot", visibility = 1}
}
local function require_that(value, message)
  if not value then error("[MIR_LIBRARY_RENDER] " .. message, 2) end
end
local function equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end
local function snapshot(force)
  local names, technologies, recipes, queue = {}, {}, {}, {}
  for name in pairs(force.technologies) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local t = force.technologies[name]
    technologies[#technologies + 1] = {name, t.level, t.researched, t.enabled}
  end
  names = {}
  for name in pairs(force.recipes) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do recipes[#recipes + 1] = {name, force.recipes[name].enabled} end
  for _, t in ipairs(force.research_queue or {}) do queue[#queue + 1] = t.name end
  return {technologies = technologies, recipes = recipes, queue = queue,
    current = force.current_research and force.current_research.name or false,
    progress = force.research_progress, worker_storage_bonus = force.worker_robots_storage_bonus}
end
local function player_for(state)
  require_that(#game.connected_players == 1, "exactly one connected player required")
  local player = game.connected_players[1]
  require_that(player.valid and player.connected, "player disconnected")
  if state.player then require_that(player.index == state.player, "player identity changed") end
  require_that(player.locale == "en" or player.locale == "de", "only declared en/de locales admitted")
  require_that(type(player.display_scale) == "number" and player.display_scale > 0, "numeric GUI scale absent")
  require_that(player.display_resolution.width > 0 and player.display_resolution.height > 0, "display absent")
  return player
end
local function unchanged(state, player)
  require_that(equal(state.native, snapshot(player.force)), "named native research/recipe state changed")
end
local function shape(player, view)
  local root = player.gui.screen[ROOT]
  require_that(root and root.valid and root.get_mod() == "more-infinite-research", "owned Library root absent")
  local tabs = root.mir_library_tabs
  require_that(tabs and tabs.valid, "Library tabs absent")
  local expected = {research = 1, queue = 2, settings = 3, help = 4, availability = 1}
  require_that(tabs.selected_tab_index == expected[view.tab], "requested public page not selected")
  return {location = root.location, minimal_width = root.style.minimal_width,
    maximal_width = root.style.maximal_width, maximal_height = root.style.maximal_height,
    display_scale = player.display_scale, display_resolution = player.display_resolution,
    tab_index = tabs.selected_tab_index}
end
local function write(player, name, value)
  helpers.write_file("mir-library-render/" .. player.locale .. "/" .. name,
    helpers.table_to_json(value), false, player.index)
end
local function prepare_intro()
  -- The protected freeplay save creates its first player on this client.
  -- Its normal750-tick cutscene would open a modal introduction and pause
  -- on_tick before the third capture. Use the scenario's public setup hook;
  -- let the cutscene finish normally and leave the original save untouched.
  require_that(remote.interfaces.freeplay and remote.interfaces.freeplay.get_skip_intro
    and remote.interfaces.freeplay.set_skip_intro, "declared Base freeplay setup interface absent")
  local previous = remote.call("freeplay", "get_skip_intro")
  if not storage.mir_render_setup then
    storage.mir_render_setup = {kind = "public-freeplay-intro-only", original_skip_intro = previous == true,
      original_flag_unset = previous == nil, saved_to_original = false}
  end
  remote.call("freeplay", "set_skip_intro", true)
  require_that(remote.call("freeplay", "get_skip_intro") == true, "freeplay intro suppression failed")
end
script.on_init(prepare_intro)
script.on_configuration_changed(prepare_intro)
script.on_nth_tick(30, function()
  local state = storage.mir_render_capture
  if not state then
    if #game.connected_players == 0 then return end
    if game.connected_players[1].controller_type == defines.controllers.cutscene then return end
    require_that(script.active_mods.base == "2.1.23" and script.active_mods["more-infinite-research"] == "5.0.21012",
      "exact engine/package tuple differs")
    state = {index = 1, phase = "initial", after = game.tick + 180, observations = {}}
    storage.mir_render_capture = state
    local player = player_for(state)
    state.player, state.native = player.index, snapshot(player.force)
  end
  if state.phase == "complete" or game.tick < state.after then return end
  local player = player_for(state)
  state.locale = state.locale or player.locale -- Bind after the initial connection/locale settlement.
  require_that(player.locale == state.locale, "locale changed during capture")
  unchanged(state, player)
  if state.phase == "initial" or state.phase == "next" then
    local view = CASES[state.index]
    require_that(remote.interfaces[BROWSER] and remote.interfaces[BROWSER].open, "public Browser.open absent")
    log("[MIR_LIBRARY_RENDER] open-begin " .. view.id)
    require_that(remote.call(BROWSER, "open", player.index, view) == true, "public Library did not open")
    shape(player, view)
    unchanged(state, player)
    log("[MIR_LIBRARY_RENDER] open-complete " .. view.id)
    state.phase, state.after = "settle", game.tick + 180
  elseif state.phase == "settle" then
    local view = CASES[state.index]
    local observation = shape(player, view)
    observation.id, observation.tick, observation.locale = view.id, game.tick, player.locale
    state.observations[#state.observations + 1] = observation
    game.take_screenshot{player = player, by_player = player.index,
      show_gui = true, force_render = true, anti_alias = false,
      path = "mir-library-render/" .. player.locale .. "/" .. view.id .. ".png"}
    write(player, view.id .. ".json", observation)
    log("[MIR_LIBRARY_RENDER] capture-requested " .. view.id)
    -- Leave the same real GUI in place through screenshot/render processing.
    state.phase, state.after = "capture", game.tick + 60
  elseif state.phase == "capture" then
    shape(player, CASES[state.index])
    state.index = state.index + 1
    if state.index <= #CASES then
      state.phase, state.after = "next", game.tick + 30
    else
      game.set_wait_for_screenshots_to_finish()
      state.phase, state.after = "flush", game.tick + 60
    end
  elseif state.phase == "flush" then
    require_that(#state.observations == #CASES, "capture count differs")
    write(player, "complete.json", {schema = 1, status = "render-requests-complete",
      locale = state.locale, player = state.player, observations = state.observations,
      scenario_setup = storage.mir_render_setup,
      native_snapshot_unchanged = true, input_acceptance = false, settings_menu_acceptance = false,
      export_acceptance = false, lifecycle_acceptance = false, release_qualification = false})
    log("[MIR_LIBRARY_RENDER] render-requests-complete " .. state.locale)
    state.phase = "complete"
  else
    error("[MIR_LIBRARY_RENDER] unexpected phase")
  end
end)
