-- Private two-client Library scenario.  It only uses the shipped public
-- browser interface and native Lua objects; it neither imports MIR modules nor
-- reads MIR storage.
local KEY = "mir5_library_multiplayer"
local CASE = "library-multiplayer"
local RESTART_SAVE = "mir5-library-multiplayer-restart"
local FINAL_SAVE = "mir5-native-complete"
local BROWSER = "more-infinite-research-browser"

local ROOT = "mir_research_browser"
local FILTERS = "mir_library_filters"
local QUERY = "mir_library_query"
local SORT = "mir_library_sort"
local TABS = "mir_library_tabs"
local RESEARCH_CONTENT = "mir_library_research_content"
local RESULTS = "mir_library_results"
local DETAIL = "mir_library_detail"
local DETAIL_TITLE = "mir_library_detail_title"

local GEAR = "recipe-prod-research_gears-1"
local MINING = "recipe-prod-research_mining_drill-1"
local TECHNOLOGIES = {GEAR, MINING}
local RECIPES = {"iron-gear-wheel", "burner-mining-drill", "electric-mining-drill"}
local VIEWS = {
  en = {query=GEAR, selected=GEAR, sort="progression", sort_index=1},
  de = {query=MINING, selected=MINING, sort="native", sort_index=2},
}

local loaded_restart = false
local ready_logged = false

local function fail(message) error("[mir5-library-multiplayer] " .. message) end
local function valid(value) return value ~= nil and value.valid ~= false end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001
end

local function named(value)
  if type(value) == "string" then return value end
  return valid(value) and value.name or nil
end

local function copy_queue(force)
  local result = {}
  for index, technology in ipairs(force.research_queue or {}) do
    local name = named(technology)
    if not name then fail("native research queue contains an unnamed entry") end
    result[index] = name
  end
  return result
end

local function native_snapshot(force)
  if not valid(force) then fail("default player force is absent") end
  local technologies, recipes = {}, {}
  for _, name in ipairs(TECHNOLOGIES) do
    local technology = force.technologies[name]
    if not valid(technology) then fail("required native technology is absent: " .. name) end
    technologies[name] = {
      level=technology.level, researched=technology.researched, enabled=technology.enabled,
      visible_when_disabled=technology.visible_when_disabled,
    }
  end
  for _, name in ipairs(RECIPES) do
    local recipe = force.recipes[name]
    if not valid(recipe) then fail("required native recipe is absent: " .. name) end
    recipes[name] = recipe.productivity_bonus
  end
  return {
    force_index=force.index, technologies=technologies, recipes=recipes,
    queue=copy_queue(force), current=named(force.current_research), progress=force.research_progress,
  }
end

local function copy_snapshot(source)
  local result = {force_index=source.force_index, technologies={}, recipes={}, queue={}, current=source.current, progress=source.progress}
  for name, technology in pairs(source.technologies) do
    result.technologies[name] = {
      level=technology.level, researched=technology.researched, enabled=technology.enabled,
      visible_when_disabled=technology.visible_when_disabled,
    }
  end
  for name, bonus in pairs(source.recipes) do result.recipes[name] = bonus end
  for index, name in ipairs(source.queue) do result.queue[index] = name end
  return result
end

local function same_snapshot(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or left.force_index ~= right.force_index
      or left.current ~= right.current or not close(left.progress, right.progress) then return false end
  for _, name in ipairs(TECHNOLOGIES) do
    local a, b = left.technologies[name], right.technologies[name]
    if type(a) ~= "table" or type(b) ~= "table" or a.level ~= b.level or a.researched ~= b.researched
        or a.enabled ~= b.enabled or a.visible_when_disabled ~= b.visible_when_disabled then return false end
  end
  for _, name in ipairs(RECIPES) do if not close(left.recipes[name], right.recipes[name]) then return false end end
  if #left.queue ~= #right.queue then return false end
  for index, name in ipairs(left.queue) do if right.queue[index] ~= name then return false end end
  return true
end

local function assert_native(state, force)
  if not same_snapshot(state.native_initial, state.native) then fail("stored native witness was overwritten") end
  if force.index ~= state.force_index then fail("client force differs from disposable world force") end
  if not same_snapshot(native_snapshot(force), state.native) then
    fail("public Library browsing mutated native research, queue, or recipe effects")
  end
end

local function open(player, view)
  if not (remote.interfaces and remote.interfaces[BROWSER]) then fail("shipped public browser interface is absent") end
  if remote.call(BROWSER, "open", player.index, {
    search=view.query, family="mir", selected=view.selected, sort=view.sort, tab="research"
  }) ~= true then
    fail("public browser interface did not open for connected client")
  end
end

local function frame_parts(player)
  local screen = player.gui and player.gui.screen
  local root = screen and screen[ROOT]
  if not valid(root) or root.type ~= "frame" then fail("native browser root is absent") end
  local filters = root[FILTERS]
  local query, sort = valid(filters) and filters[QUERY] or nil, valid(filters) and filters[SORT] or nil
  local tabs = root[TABS]
  local content = valid(tabs) and tabs[RESEARCH_CONTENT] or nil
  local results = valid(content) and content[RESULTS] or nil
  local detail = valid(content) and content[DETAIL] or nil
  if not valid(query) or query.type ~= "textfield" or not valid(sort) or sort.type ~= "drop-down"
      or not valid(tabs) or tabs.type ~= "tabbed-pane" or not valid(results) or results.type ~= "list-box"
      or not valid(detail) or not valid(detail[DETAIL_TITLE]) then
    fail("native public browser GUI tree is incomplete")
  end
  return root, query, sort, results
end

local function assert_view(player, locale)
  local expected = VIEWS[locale]
  local root, query, sort, results = frame_parts(player)
  if query.text ~= expected.query or sort.selected_index ~= expected.sort_index
      or results.selected_index ~= 1 or #results.items ~= 1 then
    fail("personal browser query or selected view differs for locale " .. locale)
  end
  return root, query
end

local function assert_personal_views(english, german)
  local en_root, en_query = assert_view(english, "en")
  local de_root, de_query = assert_view(german, "de")
  if en_root == de_root or en_query == de_query or en_query.text == de_query.text then
    fail("two clients share a browser root or query")
  end
end

local function measure(state, label, callback)
  local profiler = game.create_profiler(true)
  profiler.restart()
  callback()
  profiler.stop()
  -- LuaProfiler exposes only a rendered string.  The value is observational
  -- evidence and does not select gameplay or state-machine behavior.
  state.measurements[label] = tostring(profiler)
end

local function screenshot(state, stage, player)
  game.take_screenshot{
    by_player=player.index, player=player, show_gui=true, force_render=true,
    path="mir5-library-multiplayer/" .. stage .. "-" .. player.index .. ".png",
    resolution={1280,720}
  }
  state.screenshot_calls = state.screenshot_calls + 1
end

local function marker(stage, state)
  log("[MIR5_LIBRARY_MULTIPLAYER] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed",
    witnesses={
      base_version=script.active_mods.base,
      mir_version=script.active_mods["more-infinite-research"],
      actual_join_events=state.join_events,
      screenshot_calls=state.screenshot_calls,
      first_open=state.measurements.first_open,
      search=state.measurements.search,
      refresh=state.measurements.refresh,
      reopen=state.measurements.reopen,
      two_connected_clients_required=true,
      locales_required={"en", "de"},
      distinct_personal_query_and_selection=true,
      native_research_queue_and_effects_unchanged=true,
      host_restart_observed=stage == "completed",
      on_load_read_only=stage == "completed",
      rendering_pending_external_png_readback=true,
      screenshot_requests_are_not_headless_rendering_proof=true,
    }
  }))
end

local function client_count(state)
  local count = 0
  for _ in pairs(state.clients) do count = count + 1 end
  return count
end

local function pair(state, expected_joins)
  local by_locale, connected = {}, 0
  if client_count(state) > 2 then fail("fixture accepts exactly two unique clients") end
  for index, record in pairs(state.clients) do
    if record.joins > expected_joins then fail("client joined more than the required lifecycle count") end
    if record.joins == expected_joins then
      local player = game.get_player(index)
      if valid(player) and player.connected == true then
        connected = connected + 1
        -- A client's initial locale need not change after joining. Read the
        -- actual native value; locale-change events are supplementary rather
        -- than a fabricated prerequisite for an unchanged English locale.
        if player.locale ~= record.locale then
          record.locale = player.locale
          log("[MIR5_LIBRARY_MULTIPLAYER_LOCALE] " .. player.name .. " " .. tostring(record.locale))
        end
        if record.locale ~= "en" and record.locale ~= "de" then
          fail("two connected clients must have actual en/de locales: " .. player.name .. "=" .. tostring(record.locale))
        end
        if record.locale ~= nil then
          if by_locale[record.locale] ~= nil then
            if game.tick - record.join_tick <= 180 then return nil end
            fail("client locales are not distinct: " .. player.name .. "=" .. record.locale)
          end
          by_locale[record.locale] = player
        end
      end
    end
  end
  if connected < 2 then return nil end
  if connected ~= 2 or by_locale.en == nil or by_locale.de == nil then
    fail("two connected clients must have actual en/de locales")
  end
  if by_locale.en.index == by_locale.de.index or by_locale.en.force.index ~= state.force_index
      or by_locale.de.force.index ~= state.force_index then
    fail("connected clients do not share the prepared disposable force")
  end
  return by_locale.en, by_locale.de
end

local function run_initial(state, english, german)
  measure(state, "first_open", function() open(english, VIEWS.en) end)
  measure(state, "search", function() open(german, VIEWS.de) end)
  measure(state, "refresh", function() open(english, VIEWS.en) end)
  assert_personal_views(english, german)
  assert_native(state, english.force)
  screenshot(state, "initial", english)
  screenshot(state, "initial", german)
  state.phase = "awaiting-rejoin"
  marker("rejoin-ready", state)
end

local function run_rejoin(state, english, german)
  measure(state, "reopen", function()
    open(english, VIEWS.en)
    open(german, VIEWS.de)
  end)
  assert_personal_views(english, german)
  assert_native(state, english.force)
  screenshot(state, "rejoin", english)
  screenshot(state, "rejoin", german)
  -- Screenshots render asynchronously on each client. Saving in this tick
  -- can replace the GUI with the native save overlay before rendering it.
  state.phase = "capturing-rejoin"
  state.capture_after_tick = game.tick + 60
end

local function run_restart(state, english, german)
  if not loaded_restart then return end
  -- The post-restart join handler in the shipped Library must rebuild this
  -- already-open GUI before this fixture observes it; no new open call masks it.
  assert_personal_views(english, german)
  assert_native(state, english.force)
  screenshot(state, "restart", english)
  screenshot(state, "restart", german)
  state.phase = "capturing-restart"
  state.capture_after_tick = game.tick + 60
end

local function closure()
  local allowed = {base="2.0.77", ["more-infinite-research"]="5.0.20000",
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
    ["mir-fixture-mir5-library-multiplayer"]="0.1.0"}
  for name, version in pairs(script.active_mods) do
    if allowed[name] ~= version then fail("unexpected non-base F200 multiplayer closure: " .. tostring(name)) end
  end
  for name, version in pairs(allowed) do
    if script.active_mods[name] ~= version then fail("required multiplayer closure member is absent: " .. name) end
  end
end

script.on_init(function()
  closure()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  local force, surface = game.forces.player, game.surfaces[1]
  if not valid(force) or not valid(surface) then fail("fresh disposable base world is absent") end
  local native = native_snapshot(force)
  storage[KEY] = {
    phase="waiting-initial-clients", world={force_index=force.index, surface_index=surface.index}, force_index=force.index,
    native=native, native_initial=copy_snapshot(native), clients={}, join_events=0,
    screenshot_calls=0, measurements={}
  }
  marker("ready", storage[KEY])
  ready_logged = true
end)

script.on_load(function()
  local state = storage[KEY]
  -- on_load cannot access game and must not modify durable fixture state.
  loaded_restart = type(state) == "table" and state.phase == "awaiting-host-restart"
  ready_logged = false
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local state = storage[KEY]
  local player = state and event and game.get_player(event.player_index)
  if not valid(player) or player.connected ~= true then fail("join event did not expose an actually connected client") end
  local record = state.clients[player.index]
  if record == nil then
    if client_count(state) >= 2 then fail("fixture accepts exactly two unique clients") end
    record = {joins=0, locale=nil, locale_events=0}
    state.clients[player.index] = record
  end
  record.joins = record.joins + 1
  record.join_tick = game.tick
  record.locale = player.locale
  state.join_events = state.join_events + 1
  log("[MIR5_LIBRARY_MULTIPLAYER_JOIN] " .. player.name .. " " .. tostring(record.joins))
  log("[MIR5_LIBRARY_MULTIPLAYER_LOCALE] " .. player.name .. " " .. tostring(record.locale))
end)

script.on_event(defines.events.on_player_locale_changed, function(event)
  local state = storage[KEY]
  local player = state and event and game.get_player(event.player_index)
  local record = player and state.clients[player.index]
  if not valid(player) or player.connected ~= true or type(record) ~= "table" then
    fail("locale event did not follow an actual connected client join")
  end
  record.locale = player.locale
  record.locale_events = record.locale_events + 1
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("multiplayer fixture state is absent") end
  if state.phase == "waiting-initial-clients" then
    -- --create already initialized the world. The subsequent headless host
    -- loads it, so expose readiness again without changing durable state.
    if not ready_logged then marker("ready", state);ready_logged = true end
    local english, german = pair(state, 1)
    if english and german then run_initial(state, english, german) end
  elseif state.phase == "awaiting-rejoin" then
    local english, german = pair(state, 2)
    if english and german then run_rejoin(state, english, german) end
  elseif state.phase == "awaiting-host-restart" then
    local english, german = pair(state, 3)
    if english and german then run_restart(state, english, german) end
  elseif state.phase == "capturing-rejoin" and game.tick >= state.capture_after_tick then
    state.phase = "awaiting-host-restart"
    state.capture_after_tick = nil
    game.server_save(RESTART_SAVE)
    marker("restart-ready", state)
  elseif state.phase == "capturing-restart" and game.tick >= state.capture_after_tick then
    state.phase = "completed"
    state.capture_after_tick = nil
    marker("completed", state)
    game.server_save(FINAL_SAVE)
  end
end)
