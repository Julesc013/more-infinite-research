-- This fixture requires the runner's hash-bound historical input save. It
-- deliberately does not create a player or inspect another mod's storage.
-- The public browser interface and documented native Lua GUI objects are the
-- only MIR-facing surface exercised here.
local KEY = "mir5_native_library_object"
local SAVE = "mir5-native-complete"
local CASE = "library-native"
local BROWSER_INTERFACE = "more-infinite-research-browser"
local GEAR = "recipe-prod-research_gears-1"
local GEAR_RECIPE = "iron-gear-wheel"
local ROOT = "mir_research_browser"
local FILTERS = "mir_library_filters"
local QUERY = "mir_library_query"
local CONTENT = "mir_library_content"
local RESULTS = "mir_library_results"
local DETAIL = "mir_library_detail"
local DETAIL_TITLE = "mir_library_detail_title"
local DETAIL_EMPTY = "mir_library_detail_empty"
local MISSING_QUERY = "mir5 library fixture no matching research"

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-library-native] " .. message)
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function technology_name(value)
  if type(value) == "string" then return value end
  return valid(value) and value.name or nil
end

local function copy_queue(force)
  local result = {}
  for index, entry in ipairs(force.research_queue) do
    local name = technology_name(entry)
    if not name then fail("native research queue contained an unnamed entry") end
    result[index] = name
  end
  return result
end

local function native_snapshot(player)
  local force = player.force
  local technology = force and force.technologies[GEAR]
  local recipe = force and force.recipes[GEAR_RECIPE]
  if not valid(technology) then fail("selected gear technology is absent") end
  if not valid(recipe) then fail("selected gear recipe is absent") end
  return {
    level = technology.level,
    researched = technology.researched,
    enabled = technology.enabled,
    visible_when_disabled = technology.visible_when_disabled,
    productivity_bonus = recipe.productivity_bonus,
    current_research = technology_name(force.current_research),
    research_progress = force.research_progress,
    queue = copy_queue(force)
  }
end

local function copy_snapshot(value)
  local result = {
    level = value.level,
    researched = value.researched,
    enabled = value.enabled,
    visible_when_disabled = value.visible_when_disabled,
    productivity_bonus = value.productivity_bonus,
    current_research = value.current_research,
    research_progress = value.research_progress,
    queue = {}
  }
  for index, name in ipairs(value.queue) do result.queue[index] = name end
  return result
end

local function same_snapshot(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  for _, key in ipairs({
    "level", "researched", "enabled", "visible_when_disabled", "productivity_bonus",
    "current_research", "research_progress"
  }) do
    if left[key] ~= right[key] then return false end
  end
  if #left.queue ~= #right.queue then return false end
  for index, name in ipairs(left.queue) do
    if name ~= right.queue[index] then return false end
  end
  return true
end

-- LuaGameScript.players is a LuaCustomTable: the pinned runtime API requires
-- pairs(), not ipairs(). Selecting an existing valid player is intentionally
-- the only player acquisition this fixture performs.
local function saved_player()
  local count, selected, selected_index = 0, nil, nil
  for index, player in pairs(game.players) do
    count = count + 1
    if valid(player) and (selected_index == nil or index < selected_index) then
      selected, selected_index = player, index
    end
  end
  if not selected then fail("hash-bound input save has no valid existing player") end
  return selected, count
end

local function frame_parts(player)
  local screen = player.gui and player.gui.screen
  local root = screen and screen[ROOT]
  if not valid(root) or root.type ~= "frame" then fail("public browser did not create its screen frame") end
  local filters = root[FILTERS]
  local query = valid(filters) and filters[QUERY] or nil
  local content = root[CONTENT]
  local results = valid(content) and content[RESULTS] or nil
  local detail = valid(content) and content[DETAIL] or nil
  if not valid(query) or query.type ~= "textfield" then fail("browser query field is absent") end
  if not valid(results) or results.type ~= "list-box" then fail("browser results list is absent") end
  if not valid(detail) then fail("browser detail panel is absent") end
  return root, query, results, detail
end

local function open(player, options)
  if not (remote.interfaces and remote.interfaces[BROWSER_INTERFACE]) then
    fail("shipped public browser interface is absent")
  end
  local opened = remote.call(BROWSER_INTERFACE, "open", player.index, options)
  if opened ~= true then fail("public browser interface did not open for saved player") end
end

local function assert_selected_gear(player, root, query)
  local current_root, current_query, results, detail = frame_parts(player)
  if current_root ~= root or current_query ~= query then
    fail("public browser replaced the root or query during an options update")
  end
  if query.text ~= GEAR or results.selected_index ~= 1 or #results.items ~= 1 then
    fail("public browser did not retain the selected gear query/options")
  end
  local title = detail[DETAIL_TITLE]
  if not valid(title) or title.caption ~= GEAR then
    fail("selected gear detail is absent from the native GUI")
  end
end

local function assert_no_results(player, root, query)
  local current_root, current_query, results, detail = frame_parts(player)
  if current_root ~= root or current_query ~= query then
    fail("no-result search replaced the root or query")
  end
  if query.text ~= MISSING_QUERY or #results.items ~= 0 or results.selected_index ~= 0 then
    fail("no-result query did not produce the expected native GUI state")
  end
  if not valid(detail[DETAIL_EMPTY]) then fail("no-result detail is absent from the native GUI") end
end

local function assert_runtime_versions()
  if script.active_mods.base ~= "2.1.23" then
    fail("fixture requires the pinned 2.1.23 runtime, got " .. tostring(script.active_mods.base))
  end
  if script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("fixture requires the selected MIR 5 package")
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = CASE,
    status = "passed",
    witnesses = {
      fixture_requires_hash_bound_input_save = true,
      historical_input_save_engine_version = "2.1.21",
      historical_input_save_engine_sha256 = "703D176F00CCAEB5F8FEB797E3299F637B12E48AA3C091919D668DD2BA4589C1",
      runtime_base_version = script.active_mods.base,
      runtime_mir_version = script.active_mods["more-infinite-research"],
      player_count = state.player_count,
      selected_player_index = state.player_index,
      selected_player_connected = state.player_connected,
      root_query_identity_preserved = true,
      selected_gear = GEAR,
      selected_result_count = 1,
      no_result_count = 0,
      native_research_snapshot_unchanged = true,
      headless_lua_gui_object_construction = true,
      rendered_ui_qualified = false,
      multiplayer_qualified = false,
      full_product_migration_qualified = false,
      on_load_read_only = stage == "reload"
    }
  }))
end

script.on_init(function()
  fail("fixture requires a hash-bound InputSave and never creates a player")
end)

script.on_configuration_changed(function()
  assert_runtime_versions()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  local player, player_count = saved_player()
  if player.connected then fail("selected historical player is unexpectedly connected") end
  storage[KEY] = {
    phase = "initial",
    player_index = player.index,
    player_count = player_count,
    player_connected = player.connected
  }
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "completed" and type(state.native) == "table" then
    loaded_snapshot = {
      player_index = state.player_index,
      native = copy_snapshot(state.native)
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("input-save configuration state is absent") end
  local player = game.get_player(state.player_index)
  if not valid(player) then fail("saved player disappeared") end

  if state.phase == "initial" then
    local before = native_snapshot(player)
    open(player, {search = GEAR, family = "mir", selected = GEAR})
    local root, query = frame_parts(player)
    assert_selected_gear(player, root, query)

    open(player, {search = MISSING_QUERY, family = "mir", selected = GEAR})
    assert_no_results(player, root, query)

    open(player, {search = GEAR, family = "mir", selected = GEAR})
    assert_selected_gear(player, root, query)
    local after = native_snapshot(player)
    if not same_snapshot(before, after) then
      fail("public Library browsing mutated native research, bonus, or queue state")
    end
    state.native = after
    state.phase = "completed"
    marker("initial", state)
    game.server_save(SAVE)
    return
  end

  if state.phase == "completed" and loaded_snapshot and not reload_logged then
    if loaded_snapshot.player_index ~= state.player_index
        or not same_snapshot(loaded_snapshot.native, state.native) then
      fail("on_load changed the saved native witness")
    end
    if not same_snapshot(native_snapshot(player), state.native) then
      fail("cold reload changed native research, bonus, or queue state")
    end
    marker("reload", state)
    reload_logged = true
  end
end)
