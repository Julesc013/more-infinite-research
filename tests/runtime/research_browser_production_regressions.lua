-- Actual core, Factorio adapter and registered click consumer. Controlled
-- statistics do not qualify native production, GUI, saves or multiplayer.
return function(core, adapter, host_source, check, host_adapter_source, game_api)
  check(type(adapter.production_snapshot) == "function", "adapter supplies an opt-in science snapshot")
  check(type(core.production_load_check) == "function", "core evaluates copied science rates")
  local queries, reads = {}, 0
  local production, consumption = 120, 75
  local force = {valid = true, index = 1, name = "factory"}
  local native_queue = {{name = "active-research"}}
  force.research_queue, force.research_progress = native_queue, 0.42
  local surface = {valid = true, index = 2, name = "nauvis"}
  local technology = {valid = true, name = "tin-productivity-4", force = force,
    research_unit_ingredients = {{name = "automation-science-pack", amount = 2}}}
  force.technologies = {[technology.name] = technology}
  force.get_item_production_statistics = function(selected_surface)
    check(selected_surface == surface, "adapter selects the player's exact surface")
    reads = reads + 1
    return {valid = true, get_flow_count = function(query)
      queries[#queries + 1] = query
      check(query.name.name == "automation-science-pack" and query.name.quality == "normal",
        "statistics explicitly select the ingredient and normal quality")
      check(query.precision_index == 1 and query.count == false and query.sample_index == nil
        and query.input == nil, "adapter requests a period average using the current API")
      check(query.category == "input" or query.category == "output", "only production and consumption are read")
      if query.category == "input" then return production end
      return consumption
    end}
  end
  local snapshot = adapter.production_snapshot(force, surface, technology, 1, 3600)
  local report = core.production_load_check(snapshot)
  check(reads == 1 and #queries == 2, "one explicit snapshot performs only two rate reads per pack")
  check(report and report.rows[1].produced == 120 and report.rows[1].consumed == 75
    and report.rows[1].balance == 45, "copied rates show the actual surplus without a throughput forecast")
  check(report.force_index == 1 and report.surface_index == 2 and report.tick == 3600,
    "snapshot binds force, surface and observation tick")
  snapshot.rows[1].produced = 999
  check(report.rows[1].produced == 120, "core owns copied scalar rows")
  production, consumption = 3, 10
  local next_report = core.production_load_check(adapter.production_snapshot(force, surface, technology, 1, 3660))
  check(next_report.rows[1].balance == -7 and report.rows[1].balance == 45,
    "another manual read observes a deficit without mutating the prior snapshot")
  production, consumption = 0, 0
  local idle = core.production_load_check(adapter.production_snapshot(force, surface, technology, 1, 3660))
  check(idle and idle.rows[1].produced == 0 and idle.rows[1].consumed == 0 and idle.rows[1].balance == 0,
    "observed idle production remains distinct from unavailable statistics")
  local before = reads
  check(adapter.production_snapshot(force, surface, technology, nil, 3660) == nil and reads == before,
    "missing precision capability performs no rate read")
  technology.force = {valid = true, index = 9}
  check(adapter.production_snapshot(force, surface, technology, 1, 3660) == nil and reads == before,
    "foreign force technology cannot select another force's statistics")
  technology.force = force
  local ingredients = technology.research_unit_ingredients
  technology.research_unit_ingredients = {}
  check(adapter.production_snapshot(force, surface, technology, 1, 3660) == nil and reads == before,
    "trigger or ingredient-free research has no invented science load")
  local many = {}
  for index = 1, 17 do many[index] = {name = "pack-" .. index, amount = 1} end
  technology.research_unit_ingredients = many
  check(adapter.production_snapshot(force, surface, technology, 1, 3660) == nil and reads == before,
    "oversized science lists are withheld before statistics work")
  technology.research_unit_ingredients = ingredients
  for _, bad in ipairs{false, -1, math.huge, 0/0} do
    production = bad
    check(core.production_load_check(adapter.production_snapshot(force, surface, technology, 1, 3660)) == nil,
      "invalid statistics never become an observed zero or a player claim")
  end
  production, consumption = 120, 75
  local normal_method = force.get_item_production_statistics
  force.get_item_production_statistics = function() error("unsupported statistics") end
  check(adapter.production_snapshot(force, surface, technology, 1, 3660) == nil,
    "unsupported statistics fail without escaping into the GUI handler")
  force.get_item_production_statistics = normal_method
  local clean = adapter.production_snapshot(force, surface, technology, 1, 3660)
  clean.rows[1].quality = "legendary"
  check(core.production_load_check(clean) == nil, "normal-quality scope cannot silently include another quality")
  clean.rows[1].quality = "normal"
  clean.rows[1].name = ""
  check(core.production_load_check(clean) == nil, "invalid ingredient identity is withheld")
  clean = adapter.production_snapshot(force, surface, technology, 1, 3660)
  clean.rows[2] = clean.rows[1]
  check(core.production_load_check(clean) == nil, "duplicate ingredient observations grant no aggregate claim")
  clean.rows[2] = nil; clean.rows[3] = clean.rows[1]
  check(core.production_load_check(clean) == nil, "sparse observations are withheld")
  clean.rows[3] = nil; clean.tick = -1
  check(core.production_load_check(clean) == nil, "invalid snapshot timing is withheld")

  -- Load the actual host and invoke its registered callback. Only its small
  -- output panel is represented here; entering the full renderer is an error.
  local events, buckets, labels, clears = {}, {}, {}, 0
  local panel = {valid = true, name = "mir_browser_production_load", tags = {mir_browser_section = "production-load"}}
  panel.clear = function() labels = {}; clears = clears + 1 end
  panel.add = function(spec)
    check(spec.type == "label", "production panel adds only presentation labels")
    local child = {valid = true, caption = spec.caption, tags = spec.tags, style = {}}
    labels[#labels + 1] = child
    return child
  end
  local root = {valid = true, name = "mir_research_browser"}
  local facts = {valid = true, parent = root, style = {maximal_width = 320}, mir_browser_production_load = panel}
  local button = {valid = true, type = "button", parent = facts,
    tags = {mir_browser = "production-check", technology = technology.name}}
  local player = {valid = true, index = 1, force = force, surface = surface,
    gui = {screen = {mir_research_browser = root}}}
  local personal = {schema = 3, tab = "research", selected = technology.name, visibility = 1,
    search = "retained search", sort = "progression"}
  buckets.research_browser = {players = {[1] = personal, [2] = {search = "peer", selected = "peer-tech"}}}
  local modules = {
    ["prototypes.mir.runtime.research_browser_core"] = core,
    ["prototypes.mir.runtime.research_browser_factorio_catalogue"] = adapter,
    ["prototypes.mir.runtime.research_browser_mir_provider"] = {},
    ["prototypes.mir.runtime.state"] = {bucket = function(name) return buckets[name] end},
    ["prototypes.mir.platform.factorio.runtime_state"] = {root = function() return {} end},
    ["prototypes.mir.platform.factorio.target_line"] = {feature_enabled = function(name)
      return name == "research_library" or name == "settings_profiles"
    end},
    ["prototypes.mir.runtime.startup_settings"] = {},
    ["prototypes.mir.settings.profile_codec"] = {},
    ["prototypes.mir.settings.catalog"] = {}, ["prototypes.mir.streams.registry"] = {}
  }
  local env = setmetatable({
    assert = assert, error = error, pairs = pairs, ipairs = ipairs, next = next,
    type = type, tostring = tostring, tonumber = tonumber, math = math, string = string, table = table, pcall = pcall,
    defines = {events = {}, flow_precision_index = {one_minute = 1}},
    script = {on_event = function(event, callback) events[event] = callback end,
      on_nth_tick = function() end},
    remote = {add_interface = function() end}, commands = {add_command = function() end},
    game = {tick = 3660, get_player = function(index) return index == 1 and player or nil end},
    prototypes = {item = {["automation-science-pack"] = {localised_name = {"custom.science-pack"}}}},
    require = function(name) return assert(modules[name], "unexpected module " .. name) end
  }, {__index = function(_, key) error("unexpected host read: " .. key) end})
  check(type(host_adapter_source) == "string", "production consumer receives the actual platform adapter")
  if game_api then
    for _, kind in ipairs{"item", "fluid", "recipe", "technology", "mod_setting"} do
      env.game[kind .. "_prototypes"] = env.prototypes[kind] or {}
    end
    env.prototypes = nil
  end
  modules["prototypes.mir.platform.factorio.browser_host"] = assert(load(
    host_adapter_source, "actual-production-host-adapter", "t", env))()
  -- Give register its actual event names without installing any background
  -- callback capable of sampling statistics.
  for name in host_source:gmatch("defines%.events%.([%w_]+)") do env.defines.events[name] = name end
  local host = assert(load(host_source, "production-host-consumer", "t", env))()
  before = reads
  host.register()
  check(reads == before and labels[1] == nil, "registering the host does not poll production")
  local callback = assert(events.on_gui_click)
  callback{player_index = 1, element = button}
  check(reads == before + 1 and clears == 1 and #labels == 4,
    "actual owned click reads once and patches only its snapshot panel")
  check(labels[1].caption[1] == "mir-browser.production-scope"
    and labels[1].caption[2] == "factory" and labels[1].caption[3] == "nauvis",
    "actual host labels force, surface and normal-quality scope")
  check(labels[4].caption[1] == "mir-browser.production-row"
    and labels[4].caption[3] == "120" and labels[4].caption[4] == "75" and labels[4].caption[5] == "45",
    "real consumer formats production, usage and balance in their correct order")
  check(labels[4].caption[2][1] == "?" and labels[4].caption[2][2][1] == "custom.science-pack",
    "real consumer honors custom item localization rather than inventing a locale key")
  check(personal.search == "retained search" and root.valid and buckets.research_browser.players[2].search == "peer"
    and personal.production_snapshot == nil, "sampling retains personal controls, peer state and no saved rate cache")
  check(force.research_queue == native_queue and force.research_queue[1].name == "active-research"
    and force.research_progress == 0.42, "sampling preserves native research queue and progress")
  production, consumption = 3, 10
  callback{player_index = 1, element = button}
  check(labels[4].caption[5] == "-7" and clears == 2, "manual refresh replaces the panel with the new deficit")
  before = reads
  for _, mutate in ipairs{
    function() personal.selected = "other-tech" end,
    function() personal.selected = technology.name; personal.tab = "settings" end,
    function() personal.tab = "research"; personal.visibility = 3 end,
    function() personal.visibility = 1; button.parent = nil end
  } do
    mutate(); callback{player_index = 1, element = button}
    check(reads == before and clears == 2, "stale, foreign and inactive controls cannot sample or rebuild")
  end
  button.parent = facts
  force.get_item_production_statistics = function() error("unavailable") end
  callback{player_index = 1, element = button}
  check(#labels == 1 and labels[1].caption[1] == "mir-browser.production-unavailable",
    "actual consumer replaces stale data with an unavailable explanation")
end
