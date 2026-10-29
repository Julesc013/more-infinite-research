-- Shared F200 paired public-browser fixture. It has no MIR imports and only
-- drives the stable remote interface plus documented native GUI objects.
local KEY = "mir5_library_paired_browser"
local CASE = "library-paired-browser"
local FIXTURE = "mir-fixture-mir5-library-paired-browser"
local OBSERVER = "mir-fixture-mir5-active-mods-observer"
local ARM_SETTING = "mir5-library-paired-browser-arm"
local BROWSER = "more-infinite-research-browser"
local ROOT = "mir_research_browser"
local RESTART_SAVE = "mir5-library-paired-browser-restart"
local FINAL_SAVE = "mir5-native-complete"
local CAPTURE_DELAY = 60
local CLIENT_SETTLE_TICKS = 120
local MAX_QUEUE = 8
local MAP_SEED = 424242
local settled_roots

local GEAR = "recipe-prod-research_gears-1"
local MINING = "recipe-prod-research_mining_drill-1"
local TECHNOLOGIES = {GEAR, MINING}
local RECIPES = {"iron-gear-wheel", "electric-mining-drill"}

local ARMS = {
  published = {
    key = "published",
    mir_version = "4.7.20002",
    selector = "mir-fixture-mir5-library-paired-browser-arm-published",
    shape = {
      tabs = "mir_browser_tabs",
      content = "mir_browser_research_content",
      query = "mir_browser_search",
      body = "mir_browser_body",
      results = "mir_browser_research_results",
      family_filters = "mir_browser_filters",
      list_column = "mir_browser_research_list",
      list = "mir_browser_research_entries",
      detail = "mir_browser_research_detail"
    }
  },
  mir5 = {
    key = "mir5",
    mir_version = "5.0.20000",
    selector = "mir-fixture-mir5-library-paired-browser-arm-mir5",
    shape = {
      filters = "mir_library_filters",
      tabs = "mir_library_tabs",
      content = "mir_library_research_content",
      query = "mir_library_query",
      family = "mir_library_family",
      results = "mir_library_results",
      detail = "mir_library_detail"
    }
  }
}

local VIEWS = {
  ["first-open"] = {
    en = {query = "gears", selected = GEAR},
    de = {query = "mining", selected = MINING}
  },
  search = {
    en = {query = "recipe prod research gears", selected = GEAR},
    de = {query = "recipe prod research mining drill", selected = MINING}
  },
  refresh = {
    en = {query = "recipe prod research gears", selected = GEAR},
    de = {query = "recipe prod research mining drill", selected = MINING}
  },
  reopen = {
    en = {query = "gears", selected = GEAR},
    de = {query = "mining", selected = MINING}
  }
}

local function fail(message)
  error("[mir5-library-paired-browser] " .. message)
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function named(value)
  if type(value) == "string" then return value end
  return valid(value) and value.name or nil
end

local function selected_arm()
  local setting = settings.startup[ARM_SETTING]
  local key = setting and setting.value
  local arm = ARMS[key]
  if arm == nil then fail("fixture arm selector is absent or invalid") end
  return arm
end

local function assert_closure(arm)
  local expected = {
    base = "2.0.77",
    ["more-infinite-research"] = arm.mir_version,
    [FIXTURE] = "0.1.0",
    [arm.selector] = "0.1.0",
    [OBSERVER] = "0.1.0"
  }
  local count = 0
  for name, version in pairs(script.active_mods) do
    count = count + 1
    if expected[name] ~= version then fail("fixture active-mod closure differs at " .. tostring(name)) end
  end
  if count ~= 5 then fail("fixture active-mod closure has an unexpected member count") end
  for name, version in pairs(expected) do
    if script.active_mods[name] ~= version then fail("fixture active-mod closure omits " .. name) end
  end
  if settings.startup[ARM_SETTING].value ~= arm.key then fail("fixture selector does not match active arm") end
end

local function connected_players()
  local result, seen = {}, {}
  for _, player in pairs(game.players) do
    if valid(player) and player.connected == true then
      if type(player.index) ~= "number" or seen[player.index] then fail("connected player identity is invalid") end
      seen[player.index] = true
      result[#result + 1] = player
    end
  end
  if #result ~= 2 then return nil end
  table.sort(result, function(left, right) return left.index < right.index end)
  local by_locale = {}
  for _, player in ipairs(result) do
    if player.locale ~= "en" and player.locale ~= "de" then fail("fixture requires exact en and de clients") end
    if by_locale[player.locale] ~= nil then fail("fixture clients have duplicate locales") end
    by_locale[player.locale] = player
  end
  if by_locale.en == nil or by_locale.de == nil then fail("fixture did not receive both required client locales") end
  if by_locale.en.force ~= by_locale.de.force then fail("fixture clients do not share one native force") end
  return by_locale
end

local function queue_snapshot(force)
  local queue = force and force.research_queue
  if queue == nil then fail("native research queue is absent") end
  local count = #queue
  if type(count) ~= "number" or count < 0 or count > MAX_QUEUE then
    fail("native research queue exceeds the fixture snapshot bound")
  end
  local result = {}
  for index, entry in ipairs(queue) do
    local name = named(entry)
    if name == nil then fail("native research queue contains an unnamed entry") end
    result[index] = name
  end
  if #result ~= count then fail("native research queue has a non-contiguous entry") end
  return result
end

local function native_snapshot(force)
  if not valid(force) then fail("shared native force is absent") end
  if force.current_research ~= nil then
    fail("fresh paired Browser seed unexpectedly has active research")
  end
  local result = {
    force_index = force.index,
    current_research = named(force.current_research),
    research_progress = force.research_progress,
    queue = queue_snapshot(force),
    technologies = {},
    recipes = {}
  }
  if #result.queue ~= 0 then fail("fresh paired Browser seed research queue is not empty") end
  for _, name in ipairs(TECHNOLOGIES) do
    local technology = force.technologies and force.technologies[name]
    if not valid(technology) then fail("named native technology is absent: " .. name) end
    result.technologies[name] = {
      level = technology.level,
      researched = technology.researched,
      enabled = technology.enabled,
      visible_when_disabled = technology.visible_when_disabled,
      research_unit_count = technology.research_unit_count,
      research_unit_energy = technology.research_unit_energy
    }
  end
  for _, name in ipairs(RECIPES) do
    local recipe = force.recipes and force.recipes[name]
    if not valid(recipe) or type(recipe.productivity_bonus) ~= "number" then
      fail("named native recipe is absent or invalid: " .. name)
    end
    result.recipes[name] = {productivity_bonus = recipe.productivity_bonus}
  end
  return result
end

local function same_snapshot(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  for _, field in ipairs({"force_index", "current_research", "research_progress"}) do
    if left[field] ~= right[field] then return false end
  end
  if #left.queue ~= #right.queue then return false end
  for index, name in ipairs(left.queue) do if name ~= right.queue[index] then return false end end
  for _, name in ipairs(TECHNOLOGIES) do
    local before, after = left.technologies[name], right.technologies[name]
    if type(before) ~= "table" or type(after) ~= "table" then return false end
    for _, field in ipairs({"level", "researched", "enabled", "visible_when_disabled", "research_unit_count", "research_unit_energy"}) do
      if before[field] ~= after[field] then return false end
    end
  end
  for _, name in ipairs(RECIPES) do
    if left.recipes[name].productivity_bonus ~= right.recipes[name].productivity_bonus then return false end
  end
  return true
end

local function child(parent, name)
  return valid(parent) and parent[name] or nil
end

local function published_family_picker(filters)
  if not valid(filters) then return nil end
  local fields = filters.children
  if type(fields) ~= "table" or #fields > 8 then fail("public browser family selector layout differs") end
  local found
  for _, field in ipairs(fields) do
    local elements = valid(field) and field.children or nil
    if type(elements) ~= "table" or #elements > 3 then fail("public browser family selector layout differs") end
    for _, element in ipairs(elements) do
      local tags = valid(element) and element.tags or nil
      if valid(element) and element.type == "drop-down" and type(tags) == "table"
          and tags.mir_browser == "family" then
        if found ~= nil then fail("public browser family selector is duplicated") end
        found = element
      end
    end
  end
  return found
end

local function assert_all_family(picker)
  local items = valid(picker) and picker.items or nil
  local index = valid(picker) and picker.selected_index or nil
  if not valid(picker) or picker.type ~= "drop-down" or type(items) ~= "table" or #items > 512
      or type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > #items then
    fail("public browser family scope differs from declared all research")
  end
  local selected = items[index]
  if type(selected) ~= "table" or #selected ~= 1 or selected[1] ~= "mir-browser.scope-all" then
    fail("public browser family scope differs from declared all research")
  end
end

local function assert_shape(player, arm, view)
  local root = player.gui and player.gui.screen and player.gui.screen[ROOT]
  if not valid(root) or root.type ~= "frame" or root.visible ~= true then
    fail("public browser root is absent or hidden")
  end
  local shape, query, results, detail, family
  shape = arm.shape
  if shape.filters then
    local filters = child(root, shape.filters)
    query = child(filters, shape.query)
    family = child(filters, shape.family)
    local tabs = child(root, shape.tabs)
    local content = child(tabs, shape.content)
    results, detail = child(content, shape.results), child(content, shape.detail)
  else
    local tabs = child(root, shape.tabs)
    local content = child(tabs, shape.content)
    query = child(content, shape.query)
    local body = child(content, shape.body)
    family = published_family_picker(child(body, shape.family_filters))
    local panes = child(body, shape.results)
    results = child(child(panes, shape.list_column), shape.list)
    detail = child(panes, shape.detail)
  end
  assert_all_family(family)
  if not valid(query) or query.type ~= "textfield" or query.text ~= view.query then
    fail("public browser query differs from the submitted public search")
  end
  if not valid(results) or results.type ~= "list-box" or #results.items < 1 or results.selected_index < 1 then
    fail("public browser selected results differ")
  end
  if not valid(detail) or detail.type ~= "flow" then fail("public browser detail differs") end
end

local function open(player, view)
  if not (remote.interfaces and remote.interfaces[BROWSER]) then fail("shipped public browser interface is absent") end
  local opened = remote.call(BROWSER, "open", player.index, {
    tab = "research", search = view.query, selected = view.selected, sort = "progression", family = "all"
  })
  if opened ~= true then fail("public browser interface did not open") end
end

local function marker(stage, state, status)
  local map_gen_settings
  if stage == "ready" then
    local surface = game.surfaces[1]
    if not valid(surface) then fail("fixed map surface is absent") end
    map_gen_settings = surface.map_gen_settings
    if type(map_gen_settings) ~= "table" or map_gen_settings.seed ~= MAP_SEED then
      fail("fixed map seed differs from the declared paired workload")
    end
  end
  log("[MIR5_LIBRARY_PAIRED_BROWSER] " .. helpers.table_to_json({
    schema = 1,
    case = CASE,
    stage = stage,
    status = status,
    arm = state.arm,
    action_call_count = state.action_call_count or 0,
    screenshot_calls = state.screenshot_calls or 0,
    join_events = state.join_events or 0,
    native_snapshot_unchanged = true,
    profiler_observation_only = true,
    requested_family = "all",
    native_family_verified = VIEWS[stage] ~= nil,
    map_gen_settings = map_gen_settings,
    performance_acceptance = false
  }))
end

local function screenshot(state, stage, player)
  game.take_screenshot{
    by_player = player.index,
    player = player,
    show_gui = true,
    force_render = true,
    path = "mir5-library-paired-browser/" .. stage .. "-" .. player.index .. ".png",
    resolution = {1280, 720}
  }
  state.screenshot_calls = state.screenshot_calls + 1
end

local function assert_snapshot(state, force)
  if not same_snapshot(state.native, native_snapshot(force)) then
    fail("public Browser actions mutated named native research, queue, or recipes")
  end
end

local function run_action(state, label, players)
  local views = VIEWS[label]
  if views == nil then fail("unrecognized paired Browser action") end
  local profiler = helpers.create_profiler(true)
  profiler.restart()
  open(players.en, views.en)
  open(players.de, views.de)
  profiler.stop()
  local profiler_action = label == "first-open" and "first_open" or label
  log({"", "[MIR5_LIBRARY_PROFILE] ", profiler_action, " ", profiler})
  state.action_call_count = 2
  assert_shape(players.en, ARMS[state.arm], views.en)
  assert_shape(players.de, ARMS[state.arm], views.de)
  assert_snapshot(state, players.en.force)
  settled_roots = {en = players.en.gui.screen[ROOT], de = players.de.gui.screen[ROOT]}
  screenshot(state, label, players.en)
  screenshot(state, label, players.de)
  state.capture_after_tick = game.tick + CAPTURE_DELAY
  state.phase = label .. "-capture"
  marker(label, state, "observed")
end

local function capture_settled(state, label, players)
  local views = VIEWS[label]
  for _, locale in ipairs({"en", "de"}) do
    local root = players[locale].gui.screen[ROOT]
    if settled_roots == nil or not valid(root) or root ~= settled_roots[locale] then
      fail("settled capture lost the original public Browser root")
    end
    assert_shape(players[locale], ARMS[state.arm], views[locale])
    screenshot(state, label .. "-settled", players[locale])
  end
end

local function start_initial(state)
  local players = connected_players()
  if players == nil then return end
  state.force_index = players.en.force.index
  state.native = native_snapshot(players.en.force)
  run_action(state, "first-open", players)
end

local function restart_ready(state)
  state.capture_after_tick = nil
  state.phase = "awaiting-cold-restart"
  marker("restart-ready", state, "ready")
  game.server_save(RESTART_SAVE)
end

local function complete(state)
  state.capture_after_tick = nil
  state.phase = "completed"
  marker("completed", state, "passed")
  game.server_save(FINAL_SAVE)
end

local loaded_for_restart = false
local pending_ready = false
local ready_emitted = false

local function emit_ready(state)
  if ready_emitted then return end
  marker("ready", state, "ready")
  ready_emitted = true
end

local function emit_pending_ready(state)
  if pending_ready then
    pending_ready = false
    emit_ready(state)
  end
end

local function record_join(state, event)
  local player = game.players[event.player_index]
  local ordinal = (state.join_events or 0) + 1
  local expected_names = {"MIR5English", "MIR5Deutsch", "MIR5English", "MIR5Deutsch"}
  if ordinal > #expected_names or not valid(player) or player.name ~= expected_names[ordinal] then
    fail("fixture join identity or ordinal differs")
  end
  state.join_events = ordinal
  -- The native locale can still be the default during the join event.
  -- Wait outside the profiled actions, then validate both actual locales.
  state.clients_ready_tick = game.tick + CLIENT_SETTLE_TICKS
  log("[MIR5_LIBRARY_PAIRED_BROWSER_JOIN] " .. player.name .. " " .. ordinal)
end

script.on_init(function()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  local arm = selected_arm()
  assert_closure(arm)
  storage[KEY] = {
    schema = 1,
    arm = arm.key,
    phase = "awaiting-clients",
    screenshot_calls = 0,
    action_call_count = 0,
    join_events = 0
  }
  emit_ready(storage[KEY])
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.schema == 1 then
    if state.phase == "awaiting-clients" then
      pending_ready = true
    elseif state.phase == "awaiting-cold-restart" then
      loaded_for_restart = true
      pending_ready = true
    end
  end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.schema ~= 1 then fail("fixture state is absent") end
  emit_pending_ready(state)
  record_join(state, event)
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" or state.schema ~= 1 then return end
  emit_pending_ready(state)
  if state.phase == "awaiting-clients" or state.phase == "awaiting-cold-restart" then
    -- The original server keeps ticking while the controller observes the
    -- save marker. Only the two new client joins can attempt a reopen.
    if state.phase == "awaiting-cold-restart" and (state.join_events or 0) < 4 then return end
    if state.clients_ready_tick == nil or game.tick < state.clients_ready_tick then return end
    if state.phase == "awaiting-clients" then
      start_initial(state)
    else
      local players = connected_players()
      if players == nil then return end
      if not loaded_for_restart then fail("reopen requires the requested cold host restart") end
      if players.en.force.index ~= state.force_index then fail("rejoined clients changed the observed native force") end
      assert_snapshot(state, players.en.force)
      run_action(state, "reopen", players)
    end
    return
  end
  if state.capture_after_tick == nil or game.tick < state.capture_after_tick then return end
  local players = connected_players()
  if players == nil then return end
  if players.en.force.index ~= state.force_index then fail("client force changed during Browser observation") end
  assert_snapshot(state, players.en.force)
  if state.phase == "first-open-capture" then
    capture_settled(state, "first-open", players)
    -- Native screenshots render after this event. Keep the same GUI through
    -- a separate render grace before the next public action changes it.
    state.phase = "first-open-settled-render"
    state.capture_after_tick = game.tick + CAPTURE_DELAY
  elseif state.phase == "first-open-settled-render" then
    run_action(state, "search", players)
  elseif state.phase == "search-capture" then
    run_action(state, "refresh", players)
  elseif state.phase == "refresh-capture" then
    restart_ready(state)
  elseif state.phase == "reopen-capture" then
    capture_settled(state, "reopen", players)
    state.phase = "reopen-settled-render"
    state.capture_after_tick = game.tick + CAPTURE_DELAY
  elseif state.phase == "reopen-settled-render" then
    -- The final save can display a native modal. Let the requested frame
    -- render first, keeping both observed views intact during this grace.
    for _, locale in ipairs({"en", "de"}) do
      local root = players[locale].gui.screen[ROOT]
      if settled_roots == nil or not valid(root) or root ~= settled_roots[locale] then
        fail("final render grace lost the original public Browser root")
      end
      assert_shape(players[locale], ARMS[state.arm], VIEWS.reopen[locale])
    end
    complete(state)
  else
    fail("fixture capture phase is unrecognized")
  end
end)
