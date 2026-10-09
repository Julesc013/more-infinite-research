-- Real-host click-handler regression. The native fixture supplies this test
-- with trusted source text from research_browser.lua; the test loads that
-- exact source in a small isolated environment, calls M.register(), and
-- invokes the callback captured from script.on_event(on_gui_click). It does
-- not reimplement the host's handler or require an engine GUI mock framework.

local function expect(check, condition, message)
  check(condition, message)
  if not condition then error(message) end
end

local function make_host_factory(host_source, catalogue_source)
  local function make_environment()
    local events, buckets = {}, {}
    local metrics = {render_calls = 0, gameplay_mutations = 0, destroy_calls = 0, shortcut_calls = 0}
    local player
    local event_names = {
      "on_gui_selected_tab_changed", "on_gui_location_changed", "on_gui_click",
      "on_gui_selection_state_changed", "on_gui_text_changed", "on_string_translated",
      "on_lua_shortcut", "on_gui_confirmed", "on_gui_checked_state_changed",
      "on_gui_closed", "on_player_created", "on_player_removed",
      "on_player_locale_changed", "on_player_changed_force",
      "on_player_display_resolution_changed", "on_player_display_scale_changed",
      "on_research_started", "on_research_cancelled", "on_research_moved"
    }
    local defines_events = {}
    for _, name in ipairs(event_names) do defines_events[name] = name end
    local catalogue_module = {}
    if catalogue_source then
      catalogue_module = assert(load(catalogue_source, "actual_browser_catalogue_fixture", "t", {
        type = type, pairs = pairs, ipairs = ipairs, table = table, math = math, string = string
      }))()
    end
    local modules = {
      ["prototypes.mir.runtime.research_browser_core"] = {
        translation_queue = {}, detail_string_limit = 1024, catalogue_limit = 30000
      },
      ["prototypes.mir.runtime.research_browser_factorio_catalogue"] = catalogue_module,
      ["prototypes.mir.runtime.research_browser_mir_provider"] = {},
      ["prototypes.mir.runtime.state"] = {
        bucket = function(name)
          buckets[name] = buckets[name] or {}
          return buckets[name]
        end
      },
      ["prototypes.mir.platform.factorio.runtime_state"] = {root = function() return {} end},
      ["prototypes.mir.runtime.startup_settings"] = {},
      ["prototypes.mir.settings.profile_codec"] = {},
      ["prototypes.mir.settings.catalog"] = {},
      ["prototypes.mir.streams.registry"] = {}
    }
    local env = {
      assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
      tostring = tostring, tonumber = tonumber, type = type, math = math,
      string = string, table = table, pcall = pcall,
      defines = {events = defines_events, input_action = {}},
      script = {
        active_mods = {base = "2.1.20", ["more-infinite-research"] = "4.2.0"},
        on_event = function(id, callback) events[id] = callback end,
        on_nth_tick = function() end
      },
      remote = {add_interface = function() end},
      commands = {add_command = function() end},
      settings = {}, prototypes = {}, helpers = {}, storage = {},
      require = function(name)
        local module = modules[name]
        if module == nil then error("unexpected host require: " .. tostring(name)) end
        return module
      end
    }
    env.game = {
      get_player = function(index) return player and index == player.index and player or nil end,
      connected_players = {}, players = {}, forces = {}
    }
    setmetatable(env, {__index = function(_, key)
      error("unexpected host global access: " .. tostring(key))
    end})
    return env, events, metrics, buckets, function(value) player = value end, catalogue_module
  end

  return function(options)
    local source = host_source
    if options and options.mutate_unconditional_click_render then
      local count
      source, count = string.gsub(source, "else return end\n  render%(player%)",
        "else -- handler regression injected unconditional render\n  end\n  render(player)", 1)
      if count ~= 1 then error("handler mutation anchor not found") end
      source, count = string.gsub(source, "render = function%(player%)",
        "render = function(player) error('__handler_render_sentinel__')", 1)
      if count ~= 1 then error("render sentinel anchor not found") end
    end
    if options and options.mutate_name_only_location then
      local count
      source, count = string.gsub(source,
        "if owned_root%(player, event.element%) then view%(player%).location = event.element.location end",
        "if player and event.element and event.element.valid and event.element.name == ROOT then view(player).location = event.element.location end", 1)
      if count ~= 1 then error("location ownership mutation anchor not found") end
    end
    if options and options.mutate_name_only_close then
      local count
      source, count = string.gsub(source, "if owned_root%(player, event.element%) then close%(player%) end",
        "if event.element and event.element.valid and event.element.name == ROOT then close(player) end", 1)
      if count ~= 1 then error("close ownership mutation anchor not found") end
    end
    local env, events, metrics, buckets, set_player, catalogue_module = make_environment()
    local chunk, load_error = load(source, "research_browser_handler_fixture", "t", env)
    if not chunk then error(load_error) end
    local host = chunk()
    host.register()
    local root = {valid = true, name = "mir_research_browser", location = {x = 10, y = 20}}
    local dropdown = {valid = true, type = "drop-down", tags = {mir_browser = "status"}, parent = root}
    local textfield = {valid = true, type = "textfield", tags = {mir_browser = "search"}, parent = root}
    local unknown_button = {valid = true, type = "button", tags = {mir_browser = "unknown-action"}, parent = root}
    -- The foreign control advertises a destructive MIR action but does not
    -- belong to the player's root, so ownership must reject it first.
    local foreign_button = {valid = true, type = "button", tags = {mir_browser = "close"}}
    local fixture_player = {valid = true, index = 1, gui = {screen = {mir_research_browser = root}}}
    fixture_player.force = setmetatable({}, {
      __index = function() error("lifecycle fixture must not read force gameplay") end,
      __newindex = function()
        metrics.gameplay_mutations = metrics.gameplay_mutations + 1
        error("lifecycle fixture must not write force gameplay")
      end
    })
    fixture_player.set_shortcut_toggled = function(_, toggled)
      metrics.shortcut_calls = metrics.shortcut_calls + 1
      metrics.shortcut_toggled = toggled
    end
    root.destroy = function()
      metrics.destroy_calls = metrics.destroy_calls + 1
      root.valid = false
      fixture_player.gui.screen.mir_research_browser = nil
    end
    -- A second player's pending search and saved view share this namespace.
    -- Lifecycle callbacks for player 1 must leave that peer's state intact.
    local peer_view = {location = {x = 30, y = 40}, search = "peer search"}
    buckets.research_browser = {
      players = {[1] = {location = root.location}, [2] = peer_view},
      pending_search_refresh = {[1] = 10, [2] = 20}
    }
    set_player(fixture_player)
    return {
      on_gui_click = events.on_gui_click,
      on_gui_closed = events.on_gui_closed,
      on_gui_location_changed = events.on_gui_location_changed,
      player = fixture_player,
      root = root,
      elements = {
        dropdown = dropdown,
        textfield = textfield,
        unknown_button = unknown_button,
        foreign_button = foreign_button
      },
      metrics = metrics,
      host = host,
      catalogue = catalogue_module,
      state = buckets.research_browser,
      peer_view = peer_view
    }
  end
end

local function fixture_from(host_factory, options, check)
  local fixture = host_factory(options)
  expect(check, type(fixture) == "table", "handler fixture loads the real browser host")
  expect(check, type(fixture.on_gui_click) == "function",
    "handler fixture captures the real registered on_gui_click callback")
  expect(check, type(fixture.player) == "table" and type(fixture.player.index) == "number",
    "handler fixture supplies the event player")
  expect(check, fixture.root and fixture.root.valid == true,
    "handler fixture supplies an initially retained root")
  expect(check, type(fixture.elements) == "table" and type(fixture.metrics) == "table",
    "handler fixture supplies owned elements and sentinel observations")
  return fixture
end

local function metric(fixture, name, check)
  local value = fixture.metrics[name]
  expect(check, type(value) == "number", "handler fixture exposes numeric " .. name)
  return value
end

local function invoke_and_assert_inert(fixture, element_name, check)
  local element = fixture.elements[element_name]
  expect(check, element and element.valid == true, "fixture supplies valid " .. element_name)
  local root, textfield = fixture.root, fixture.elements.textfield
  local before_render = metric(fixture, "render_calls", check)
  local before_gameplay = metric(fixture, "gameplay_mutations", check)
  local ok, err = pcall(fixture.on_gui_click, {player_index = fixture.player.index, element = element})
  expect(check, ok, element_name .. " click is ignored without an error: " .. tostring(err))
  expect(check, root.valid == true and fixture.root == root,
    element_name .. " click retains the browser root")
  expect(check, textfield and textfield.valid == true and fixture.elements.textfield == textfield,
    element_name .. " click retains the search field")
  expect(check, metric(fixture, "render_calls", check) == before_render,
    element_name .. " click does not render or rebuild the retained library")
  expect(check, metric(fixture, "gameplay_mutations", check) == before_gameplay,
    element_name .. " click cannot mutate gameplay")
end

-- host_source_string is trusted project source supplied by the test harness.
-- The isolated load environment exists only inside this regression fixture.
return function(host_source_string, check, catalogue_source_string)
  expect(check, type(host_source_string) == "string" and #host_source_string > 0,
    "handler regression receives trusted browser host source")
  expect(check, type(check) == "function", "handler regression receives an assertion function")
  local host_factory = make_host_factory(host_source_string, catalogue_source_string)
  local fixture = fixture_from(host_factory, nil, check)
  -- Factorio dispatches selection/text events separately; these click probes
  -- ensure the broad click subscription cannot rebuild controls while those
  -- controls are being operated.
  invoke_and_assert_inert(fixture, "dropdown", check)
  invoke_and_assert_inert(fixture, "textfield", check)
  invoke_and_assert_inert(fixture, "unknown_button", check)
  invoke_and_assert_inert(fixture, "foreign_button", check)

  -- A foreign or replaced element can use the same name as the browser root.
  -- Names do not prove that a lifecycle event belongs to the retained frame.
  expect(check, type(fixture.on_gui_location_changed) == "function"
    and type(fixture.on_gui_closed) == "function", "real host registers lifecycle callbacks")
  local foreign_root = {valid = true, name = fixture.root.name, location = {x = 900, y = 800}}
  local stale_root = {valid = true, name = fixture.root.name, location = {x = 700, y = 600}}
  local named_child = {valid = true, name = fixture.root.name, parent = fixture.root, location = {x = 500, y = 400}}
  for _, element in ipairs{foreign_root, stale_root, named_child} do
    fixture.on_gui_location_changed{player_index = 1, element = element}
    expect(check, fixture.state.players[1].location == fixture.root.location,
      "a same-named foreign or replaced frame cannot overwrite the browser location")
    fixture.on_gui_closed{player_index = 1, element = element}
    expect(check, fixture.root.valid and fixture.metrics.destroy_calls == 0
      and fixture.metrics.shortcut_calls == 0 and fixture.state.pending_search_refresh[1] == 10,
      "a same-named foreign or replaced frame cannot close the retained browser")
  end
  for _, element in ipairs{{valid = false, name = fixture.root.name}, {valid = true, name = "another-frame"}} do
    fixture.on_gui_location_changed{player_index = 1, element = element}
    fixture.on_gui_closed{player_index = 1, element = element}
  end
  fixture.on_gui_location_changed{player_index = 99, element = fixture.root}
  fixture.on_gui_closed{player_index = 99, element = fixture.root}
  fixture.on_gui_location_changed{player_index = 1}
  fixture.on_gui_closed{player_index = 1}
  expect(check, fixture.root.valid and fixture.metrics.destroy_calls == 0
    and fixture.state.players[1].location == fixture.root.location,
    "invalid, unrelated, missing-element and missing-player lifecycle events are inert")
  fixture.root.location = {x = 50, y = 60}
  fixture.on_gui_location_changed{player_index = 1, element = fixture.root}
  expect(check, fixture.state.players[1].location == fixture.root.location,
    "the retained root can persist its actual position")
  fixture.on_gui_closed{player_index = 1, element = fixture.root}
  expect(check, not fixture.root.valid and fixture.metrics.destroy_calls == 1
    and fixture.metrics.shortcut_calls == 1 and fixture.metrics.shortcut_toggled == false
    and fixture.state.pending_search_refresh[1] == nil
    and fixture.state.players[1].location == fixture.root.location,
    "closing the retained root saves its position, clears its search and updates its shortcut")
  expect(check, fixture.state.players[2] == fixture.peer_view
    and fixture.peer_view.location.x == 30 and fixture.peer_view.location.y == 40
    and fixture.peer_view.search == "peer search" and fixture.state.pending_search_refresh[2] == 20,
    "one player's lifecycle events preserve the peer's saved view and pending search")
  expect(check, fixture.metrics.gameplay_mutations == 0,
    "browser lifecycle events do not change force gameplay")

  local name_only_location = fixture_from(host_factory, {mutate_name_only_location = true}, check)
  name_only_location.on_gui_location_changed{player_index = 1, element = foreign_root}
  expect(check, name_only_location.state.players[1].location == foreign_root.location,
    "negative control independently detects a name-only location guard")
  local name_only_close = fixture_from(host_factory, {mutate_name_only_close = true}, check)
  name_only_close.on_gui_closed{player_index = 1, element = foreign_root}
  expect(check, not name_only_close.root.valid and name_only_close.metrics.destroy_calls == 1,
    "negative control independently detects a name-only close guard")

  local negative = fixture_from(host_factory, {mutate_unconditional_click_render = true}, check)
  local before_render = metric(negative, "render_calls", check)
  local ok = pcall(negative.on_gui_click, {
    player_index = negative.player.index,
    element = negative.elements.unknown_button
  })
  expect(check, not ok or metric(negative, "render_calls", check) > before_render,
    "negative control proves an unconditional unknown-click render is detected")

  expect(check, type(catalogue_source_string) == "string" and #catalogue_source_string > 0,
    "force lifecycle controls receive trusted actual catalogue source")
  local lifecycle = fixture_from(host_factory, nil, check)
  local destination_reads = 0
  local function force(index, name, key, destination)
    local prototype = setmetatable({}, {__index = function(_, field)
      if field == "max_level" then return 1 end
      if field == "order" then
        if destination then destination_reads = destination_reads + 1 end
        return "fixture-order"
      end
    end})
    return {valid = true, index = index, name = name, technologies = {
      [key] = {name = key, enabled = true, researched = false, prerequisites = {}, prototype = prototype}
    }, research_queue = {}}
  end
  local destination = force(7, "destination", "destination-tech", true)
  local source = force(8, "source", "source-tech")
  local before_destination = lifecycle.catalogue.snapshot(destination)
  expect(check, before_destination.rows[1].key == "destination-tech"
    and lifecycle.catalogue.snapshot(source).rows[1].key == "source-tech",
    "actual adapter populates independent source and destination catalogue facts")
  local reads = destination_reads
  lifecycle.host.on_forces_merged{source_index = source.index, destination = destination}
  source.technologies = force(8, "source", "fresh-source-facts").technologies
  local refreshed_source = lifecycle.catalogue.snapshot(source)
  expect(check, refreshed_source and refreshed_source.rows[1]
    and refreshed_source.rows[1].key == "fresh-source-facts",
    "the real merged-force callback discards facts belonging to the merged source index")
  destination.technologies["destination-tech"].researched = true
  local after_destination = lifecycle.catalogue.snapshot(destination)
  expect(check, after_destination.rows[1].key == "destination-tech"
    and after_destination.rows[1].researched and destination_reads == reads,
    "merge cleanup preserves destination static facts while reading its current research state")
  for _, event in ipairs{{}, {source_index = 0}, {source_index = -1},
      {source_index = "7"}, {source_index = 7.5}, {source_index = 900}} do
    lifecycle.host.on_forces_merged(event)
  end
  lifecycle.host.on_forces_merged()
  lifecycle.catalogue.snapshot(destination)
  expect(check, destination_reads == reads and lifecycle.metrics.gameplay_mutations == 0
    and lifecycle.state.players[2] == lifecycle.peer_view,
    "unknown or malformed merge identities preserve unrelated caches, gameplay and personal state")
end
