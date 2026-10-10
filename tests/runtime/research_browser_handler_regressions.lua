-- Real-host click-handler regression. The native fixture supplies this test
-- with trusted source text from research_browser.lua; the test loads that
-- exact source in a small isolated environment, calls M.register(), and
-- invokes the callback captured from script.on_event(on_gui_click). It does
-- not reimplement the host's handler or require an engine GUI mock framework.

local function expect(check, condition, message)
  check(condition, message)
  if not condition then error(message) end
end

local function make_host_factory(host_source, catalogue_source, platform_source)
  local function make_environment(options)
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
    for _, name in ipairs(options and options.missing_events or {}) do defines_events[name] = nil end
    local catalogue_module = {}
    if catalogue_source then
      local actual = assert(load(catalogue_source, "actual_browser_catalogue_fixture", "t", {
        type = type, pairs = pairs, ipairs = ipairs, table = table, math = math, string = string
      }))()
      local platform = assert(load(platform_source, "actual_catalogue_host_fixture", "t", {}))()
      catalogue_module = setmetatable({snapshot = function(force) return actual.snapshot(force, platform) end}, {__index = actual})
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
      ["prototypes.mir.platform.factorio.browser_host"] = {prototype_collections = function() return {} end},
      ["prototypes.mir.platform.factorio.target_line"] = {feature_enabled = function(name)
        if name == "research_library" then return not (options and options.disable_library) end
        if name == "settings_profiles" then return not (options and options.disable_profiles) end
        return false
      end},
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
        on_event = function(id, callback)
          assert(id ~= nil and defines_events[id] ~= nil, "unsupported event registration: " .. tostring(id))
          events[id] = callback
        end,
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
    if options and options.platform_source then
      modules["prototypes.mir.platform.factorio.browser_host"] = assert(load(
        options.platform_source, "actual_recipe_navigation_host", "t", env))()
    end
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
    local env, events, metrics, buckets, set_player, catalogue_module = make_environment(options)
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
      events = events,
      on_gui_selection_state_changed = events.on_gui_selection_state_changed,
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
      environment = env,
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

local function check_capability_stages(sources, check, catalogue_source)
  expect(check, type(sources) == "table", "Library capability controls receive actual stage and coordinator source")
  for _, family in ipairs{"game", "modern"} do
    local source = sources.host_adapters[family]
    local reads, writes = 0, {}
    local env = setmetatable({}, {__index = function(_, key)
      error("Library adapter read " .. key .. " before its runtime callback")
    end})
    local adapter = assert(load(source, "actual-library-host-" .. family, "t", env))()
    local catalogue = assert(load(catalogue_source, "actual-host-catalogue", "t", {
      type = type, pairs = pairs, ipairs = ipairs, table = table, math = math, string = string
    }))()
    local trigger, trigger_reads = nil, 0
    local prototype = setmetatable({hidden = false, max_level = 1, order = ""}, {__index = function(_, key)
      if key == "research_trigger" and family == "modern" then trigger_reads = trigger_reads + 1; return trigger end
      error("unsupported technology property: " .. key)
    end})
    local technology = {name = "host-field-probe", enabled = true, researched = false,
      prototype = prototype, prerequisites = {}}
    local force = {valid = true, index = 903, name = "host-field-probe",
      research_queue = {}, technologies = {[technology.name] = technology}}
    expect(check, catalogue.snapshot(force, adapter).rows[1].available,
      family .. " catalogues ordinary research through only supported prototype fields")
    trigger = {type = "craft-item", item = "iron-plate", count = 1}
    expect(check, catalogue.snapshot(force, adapter).rows[1].available == (family ~= "modern"),
      family .. " honors the engine's trigger-research capability")
    expect(check, family == "modern" and trigger_reads == 2 or family ~= "modern" and trigger_reads == 0,
      family .. " never probes a missing historical research_trigger field")
    prototype.hidden = true
    expect(check, not catalogue.snapshot(force, adapter).rows[1].available,
      family .. " keeps hidden research out of the available catalogue")
    prototype.hidden = false; trigger = nil
    technology.prerequisites.locked = {name = "locked", researched = false, prerequisites = {}}
    expect(check, not catalogue.snapshot(force, adapter).rows[1].available,
      family .. " retains prerequisite requirements")
    local absent, reason = catalogue.snapshot(force)
    expect(check, absent == nil and reason == "missing-host", "missing host does not guess an engine API")
    local function write_file(path, contents, append, player_index)
      writes[#writes + 1] = {path, contents, append, player_index}
      return "controlled-result"
    end
    local function collections(generation)
      local result = {}
      for _, kind in ipairs{"item", "fluid", "recipe", "technology", "mod_setting"} do
        result[kind] = {marker = generation .. ":" .. kind}
      end
      return result
    end
    local first, second = collections("first"), collections("reloaded")
    local function install(value)
      if family == "modern" then
        env.prototypes, env.helpers = value, {write_file = write_file}
      else
        env.game = setmetatable({write_file = write_file}, {__index = function(_, key)
          for kind, collection in pairs(value) do
            if key == kind .. "_prototypes" then reads = reads + 1; return collection end
          end
          error("Legacy Library adapter queried unsupported game property " .. key)
        end})
      end
    end
    install(first)
    local captured = adapter.prototype_collections()
    for kind, value in pairs(first) do
      expect(check, captured[kind] == value, family .. " retains the actual " .. kind .. " prototype collection")
    end
    expect(check, captured.mod_data == nil, family .. " invents no mod-data evidence when absent")
    install(second)
    expect(check, adapter.prototype_collections().technology == second.technology
      and captured.technology == first.technology, family .. " resolves current runtime objects without retaining a previous host")
    expect(check, adapter.write_file("more-infinite-research/reports/test.txt", "line\n", false, 7) == "controlled-result",
      family .. " preserves the engine file-output result")
    expect(check, #writes == 1 and writes[1][1] == "more-infinite-research/reports/test.txt"
      and writes[1][2] == "line\n" and writes[1][3] == false and writes[1][4] == 7,
      family .. " preserves report bytes, append mode and the requesting player destination")
    if family == "modern" then
      second.mod_data = {marker = "current-modern-evidence"}
      expect(check, adapter.prototype_collections() == second
        and adapter.prototype_collections().mod_data == second.mod_data,
        "modern Library keeps the native registry and mod-data identity")
    else expect(check, reads == 10, "legacy Library reads only its five supported prototype collections per request") end
  end
  for _, library in ipairs{false, true} do
    for _, profiles in ipairs{false, true} do
      local features = {research_library = library, settings_profiles = profiles}
      local shortcuts, registrations = {}, {}
      local modules = {
        ["prototypes.mir.platform.factorio.target_line"] = {feature_enabled = function(name) return features[name] == true end},
        ["prototypes.mir.platform.factorio.data_raw"] = {extend = function(rows) shortcuts = rows end},
        ["prototypes.mir.platform.factorio.mods"] = {exists = function() return false end},
        ["prototypes.mir.streams.registry"] = {},
        ["prototypes.mir.runtime.scripted_techs"] = {register = function() registrations.library = true end},
        ["prototypes.mir.runtime.settings_profile"] = {register = function() registrations.profiles = true end}
      }
      local env = {script = {}, type = type, error = error, rawget = rawget, _G = {},
        require = function(name) return assert(modules[name], "unexpected stage module: " .. name) end}
      assert(load(sources.data_stage, "actual-library-data-stage", "t", env))().run()
      expect(check, (#shortcuts == 1) == library,
        "shortcut availability follows Library capability independently of settings profiles")
      if library then
        expect(check, shortcuts[1].name == "mir-research-browser"
          and shortcuts[1].icon == "__base__/graphics/icons/lab.png",
          "independent Library capability preserves shortcut identity and absent-DLC fallback")
      end
      assert(load(sources.control_stage, "actual-library-control-stage", "t", env))().run()
      expect(check, (registrations.library == true) == library
        and (registrations.profiles == true) == profiles,
        "Library and profile registration are independently selected without gameplay effects")

      for target, source in pairs(sources.coordinators) do
        local callbacks, calls, loads = {}, {}, 0
        local browser = {requires_features = {"research_library"}}
        for _, method in ipairs{"register", "on_load", "on_init", "on_configuration_changed"} do
          local key = method
          browser[key] = function() calls[key] = (calls[key] or 0) + 1 end
        end
        local no_op = function() end
        local environment = {type = type, error = error, ipairs = ipairs,
          script = {on_load = function(fn) callbacks.load = fn end,
            on_init = function(fn) callbacks.init = fn end,
            on_configuration_changed = function(fn) callbacks.configure = fn end,
            on_event = no_op}, defines = {events = {}}}
        environment.require = function(name)
          if name == "prototypes.mir.platform.factorio.target_line" then return modules[name] end
          if name == "prototypes.mir.runtime.research_browser" then loads = loads + 1; return browser end
          if name == "prototypes.mir.runtime.state" then return {bucket = function() return {} end} end
          if name == "prototypes.mir.runtime.startup_settings" then return {get = function() return false end} end
          return {requires_features = {}, register = no_op, on_load = no_op}
        end
        assert(load(source, "actual-library-coordinator-" .. target, "t", environment))().register()
        callbacks.load(); callbacks.init(); callbacks.configure()
        expect(check, loads == (library and 1 or 0), target .. " loads the host only when the Library is supported")
        for _, method in ipairs{"register", "on_load", "on_init", "on_configuration_changed"} do
          expect(check, (calls[method] or 0) == (library and 1 or 0),
            target .. " dispatches Library " .. method .. " independently of profile support")
        end
      end
    end
  end
end

-- host_source_string is trusted project source supplied by the test harness.
-- The isolated load environment exists only inside this regression fixture.
return function(host_source_string, check, catalogue_source_string, capability_sources)
  check_capability_stages(capability_sources, check, catalogue_source_string)
  expect(check, type(host_source_string) == "string" and #host_source_string > 0,
    "handler regression receives trusted browser host source")
  expect(check, type(check) == "function", "handler regression receives an assertion function")
  local host_factory = make_host_factory(host_source_string, catalogue_source_string, capability_sources.host_adapters.modern)
  for _, missing in ipairs{
      {"on_player_locale_changed", "on_research_moved", "on_research_cancelled"},
      {"on_player_locale_changed", "on_research_moved"}, {}} do
    local fixture = fixture_from(host_factory, {missing_events = missing}, check)
    for _, name in ipairs{"on_player_locale_changed", "on_research_moved", "on_research_cancelled"} do
      local available = true
      for _, absent in ipairs(missing) do if absent == name then available = false end end
      expect(check, (fixture.events[name] ~= nil) == available,
        "optional " .. name .. " is registered exactly when provided by the host")
    end
    for _, name in ipairs{"on_gui_click", "on_string_translated", "on_research_started",
        "on_player_changed_force", "on_player_removed"} do
      expect(check, type(fixture.events[name]) == "function",
        "event adaptation preserves supported " .. name .. " handling")
    end
    expect(check, fixture.metrics.gameplay_mutations == 0 and fixture.metrics.destroy_calls == 0,
      "event registration changes no research or open view")
  end
  for _, family in ipairs{"game", "modern"} do
    local fixture = fixture_from(host_factory, {platform_source = capability_sources.host_adapters[family]}, check)
    local calls, recipe = {}, {name = "selected-recipe"}
    fixture.environment.prototypes.recipe = {[recipe.name] = recipe}
    fixture.environment.game.recipe_prototypes = {[recipe.name] = recipe}
    fixture.state.players[1].recipe_ids = {recipe.name, "missing-recipe"}
    if family == "modern" then
      fixture.player.open_factoriopedia_gui = function(value) calls[#calls + 1] = value end
    end
    setmetatable(fixture.player, {__index = function(_, key)
      error("Unsupported player property: " .. key)
    end})
    for _, kind in ipairs{"list-box", "drop-down"} do
      local element = {valid = true, type = kind, selected_index = 1,
        tags = {mir_browser = "recipe-list"}, parent = fixture.root}
      fixture.on_gui_selection_state_changed{player_index = 1, element = element}
      expect(check, fixture.root.valid and fixture.metrics.destroy_calls == 0,
        family .. " recipe navigation preserves the Library root in " .. kind)
      element.selected_index = 2
      fixture.on_gui_selection_state_changed{player_index = 1, element = element}
      element.selected_index = 3
      fixture.on_gui_selection_state_changed{player_index = 1, element = element}
      element.selected_index, element.parent = 1, nil
      fixture.on_gui_selection_state_changed{player_index = 1, element = element}
    end
    expect(check, #calls == (family == "modern" and 2 or 0),
      family .. " opens only available, owned recipe selections through its supported API")
    if family == "modern" then
      expect(check, calls[1] == recipe and calls[2] == recipe,
        "modern list and compact dropdown open the selected current recipe prototype")
    end
    expect(check, fixture.metrics.gameplay_mutations == 0 and fixture.state.players[2] == fixture.peer_view,
      family .. " recipe navigation preserves force research and the other player's view")
  end
  local fixture = fixture_from(host_factory, nil, check)
  expect(check, #fixture.host.requires_features == 1
    and fixture.host.requires_features[1] == "research_library",
    "Library availability declares its own capability, independently of settings profiles")
  local disabled = host_factory{disable_library = true}
  expect(check, disabled.on_gui_click == nil and disabled.on_gui_closed == nil,
    "a target without the Library installs no browser GUI callbacks")
  local without_profiles = fixture_from(host_factory, {disable_profiles = true}, check)
  local export_button = {valid = true, tags = {mir_browser = "export"}, parent = without_profiles.root}
  local export_ok, export_error = pcall(without_profiles.on_gui_click, {
    player_index = without_profiles.player.index, element = export_button})
  expect(check, export_ok, "a stale profile-export action is inert without profile support: " .. tostring(export_error))
  expect(check, without_profiles.root.valid and without_profiles.metrics.gameplay_mutations == 0,
    "disabling profile export retains the Library and gameplay state")
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
