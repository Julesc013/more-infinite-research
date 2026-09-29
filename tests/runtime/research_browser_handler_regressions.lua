-- Real-host click-handler regression. The native fixture supplies this test
-- with trusted source text from research_browser.lua; the test loads that
-- exact source in a small isolated environment, calls M.register(), and
-- invokes the callback captured from script.on_event(on_gui_click). It does
-- not reimplement the host's handler or require an engine GUI mock framework.

local function expect(check, condition, message)
  check(condition, message)
  if not condition then error(message) end
end

local function make_host_factory(host_source)
  local function make_environment()
    local events, buckets = {}, {}
    local metrics = {render_calls = 0, gameplay_mutations = 0}
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
    local modules = {
      ["prototypes.mir.runtime.research_browser_core"] = {
        translation_queue = {}, detail_string_limit = 1024, catalogue_limit = 30000
      },
      ["prototypes.mir.runtime.research_browser_factorio_catalogue"] = {},
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
    return env, events, metrics, function(value) player = value end
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
    local env, events, metrics, set_player = make_environment()
    local chunk, load_error = load(source, "research_browser_handler_fixture", "t", env)
    if not chunk then error(load_error) end
    local host = chunk()
    host.register()
    local root = {valid = true, name = "mir_research_browser"}
    local dropdown = {valid = true, type = "drop-down", tags = {mir_browser = "status"}, parent = root}
    local textfield = {valid = true, type = "textfield", tags = {mir_browser = "search"}, parent = root}
    local unknown_button = {valid = true, type = "button", tags = {mir_browser = "unknown-action"}, parent = root}
    -- The foreign control advertises a destructive MIR action but does not
    -- belong to the player's root, so ownership must reject it first.
    local foreign_button = {valid = true, type = "button", tags = {mir_browser = "close"}}
    local fixture_player = {index = 1, gui = {screen = {mir_research_browser = root}}}
    set_player(fixture_player)
    return {
      on_gui_click = events.on_gui_click,
      player = fixture_player,
      root = root,
      elements = {
        dropdown = dropdown,
        textfield = textfield,
        unknown_button = unknown_button,
        foreign_button = foreign_button
      },
      metrics = metrics
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
return function(host_source_string, check)
  expect(check, type(host_source_string) == "string" and #host_source_string > 0,
    "handler regression receives trusted browser host source")
  expect(check, type(check) == "function", "handler regression receives an assertion function")
  local host_factory = make_host_factory(host_source_string)
  local fixture = fixture_from(host_factory, nil, check)
  -- Factorio dispatches selection/text events separately; these click probes
  -- ensure the broad click subscription cannot rebuild controls while those
  -- controls are being operated.
  invoke_and_assert_inert(fixture, "dropdown", check)
  invoke_and_assert_inert(fixture, "textfield", check)
  invoke_and_assert_inert(fixture, "unknown_button", check)
  invoke_and_assert_inert(fixture, "foreign_button", check)

  local negative = fixture_from(host_factory, {mutate_unconditional_click_render = true}, check)
  local before_render = metric(negative, "render_calls", check)
  local ok = pcall(negative.on_gui_click, {
    player_index = negative.player.index,
    element = negative.elements.unknown_button
  })
  expect(check, not ok or metric(negative, "render_calls", check) > before_render,
    "negative control proves an unconditional unknown-click render is detected")
end
