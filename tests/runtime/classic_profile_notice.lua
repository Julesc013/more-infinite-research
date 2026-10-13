-- Source-bound controls for the Classic saved-investment notice.  These run
-- under Lua 5.2 only; no Factorio process, package, or save is created.
return function(notice_source, adapter_sources)
  local assertions, failures = 0, {}
  local function check(id, condition, detail)
    assertions = assertions + 1
    if condition then return end
    failures[#failures + 1] = id .. ": " .. detail
  end

  local function notice_for(line, selected_profile)
    local profile = selected_profile
    local profile_reads = 0
    local callbacks, registrations, printed = {}, {}, {}
    local environment = {
      type = type, pairs = pairs, error = error,
      defines = {events = {on_tick = 61}},
      script = {
        on_event = function(event_id, callback)
          callbacks[event_id] = callback
          registrations[#registrations + 1] = {event_id = event_id, callback = callback}
        end
      }
    }
    environment.require = function(name)
      if name == "prototypes.mir.settings.compiler_profile" then
        return {get = function(actual_line)
          profile_reads = profile_reads + 1
          check("CPN-00", actual_line == line,
            "profile selection must use the canonical target factorio line")
          if string.sub(actual_line, 1, 2) == "0." then return "full" end
          return profile or "classic"
        end}
      end
      if name == "prototypes.mir.platform.factorio.target_line" then
        return {factorio_version = line}
      end
      error("unexpected notice dependency " .. tostring(name))
    end
    local notice = assert(load(notice_source, "actual-compiler-profile-notice", "t", environment))()
    local function set_game(players)
      environment.game = {connected_players = players}
    end
    local function no_game_proxy()
      environment.game = setmetatable({}, {__index = function()
        error("on_load accessed LuaGameScript", 0)
      end})
    end
    local function player(valid, name)
      return {valid = valid, print = function(caption)
        printed[#printed + 1] = {name = name, caption = caption}
      end}
    end
    return {
      notice = notice, callbacks = callbacks, registrations = registrations,
      printed = printed, set_game = set_game, no_game_proxy = no_game_proxy,
      player = player, profile_reads = function() return profile_reads end,
      set_profile = function(value) profile = value end
    }
  end

  local initial = notice_for("2.1")
  local initial_a, initial_b = initial.player(true, "group-one"), initial.player(true, "group-two")
  initial.set_game({initial_a, initial_b})
  initial.notice.on_init()
  check("CPN-01", #initial.printed == 2
      and initial.printed[1].caption[1] == "mir-message.classic-profile-initial-scope",
    "default Classic init tells every connected group only that the reduced scope is active")

  local classic = notice_for("2.0", "classic")
  classic.no_game_proxy()
  classic.notice.on_load()
  check("CPN-02", type(classic.callbacks[61]) == "function" and #classic.registrations == 1
      and classic.profile_reads() == 0 and #classic.printed == 0,
    "on_load only installs the one-shot handler and reads neither game nor profile settings")
  classic.notice.on_load()
  check("CPN-03", #classic.registrations == 1,
    "repeated load restoration cannot install duplicate on_tick handlers")
  local alice, invalid, bob = classic.player(true, "group-one"), classic.player(false, "invalid"), classic.player(true, "group-two")
  classic.set_game({alice, invalid, bob})
  classic.callbacks[61]()
  check("CPN-04", classic.callbacks[61] == nil and classic.profile_reads() == 1
      and #classic.printed == 2
      and classic.printed[1].caption[1] == "mir-message.classic-profile-existing-save-scope",
    "first ordinary tick selects Classic, warns every valid connected group, and removes itself")

  local upgrade = notice_for("2.1", "classic")
  local first_group, second_group = upgrade.player(true, "first"), upgrade.player(true, "second")
  upgrade.set_game({first_group, second_group})
  upgrade.notice.on_configuration_changed({mod_changes = {
    ["more-infinite-research"] = {old_version = "4.2.20002"}
  }})
  check("CPN-05", #upgrade.printed == 2
      and upgrade.printed[1].caption[1] == "mir-message.classic-profile-upgrade-warning"
      and upgrade.printed[1].caption[2] == "4.2.20002" and upgrade.callbacks[61] == nil,
    "a known upgrade into Classic names its baseline version and warns every affected group immediately")

  local existing = notice_for("2.1", "classic")
  existing.set_game({existing.player(true, "existing")})
  existing.notice.on_configuration_changed({mod_changes = {}})
  check("CPN-06", #existing.printed == 1
      and existing.printed[1].caption[1] == "mir-message.classic-profile-existing-save-scope",
    "an unproven existing-save transition describes reduced scope without claiming lost investment")

  local cancelled = notice_for("2.1", "classic")
  cancelled.no_game_proxy(); cancelled.notice.on_load()
  cancelled.set_profile("full")
  cancelled.set_game({cancelled.player(true, "full-after-load")})
  cancelled.notice.on_configuration_changed({})
  check("CPN-07", cancelled.callbacks[61] == nil and #cancelled.printed == 0,
    "a Full configuration change removes a pending load notice without printing a stale Classic warning")

  local full = notice_for("2.1", "full")
  full.no_game_proxy(); full.notice.on_load()
  full.set_game({full.player(true, "full")})
  full.callbacks[61]()
  check("CPN-08", #full.printed == 0,
    "Full profile stays silent after the harmless one-shot profile check")

  local historic = notice_for("0.18", "classic")
  historic.set_game({historic.player(true, "historic")})
  historic.notice.on_init(); historic.notice.on_configuration_changed({})
  check("CPN-09", #historic.printed == 0,
    "the canonical historical Full selection never emits the modern Classic warning")

  local function adapter_control(target, source)
    local callbacks, calls = {}, {}
    local notice_calls, browser_calls, passive_calls = {}, {}, {}
    local library = true
    local function record(target_calls, method)
      target_calls[method] = (target_calls[method] or 0) + 1
    end
    local no_op = function() end
    local environment = {
      type = type, error = error, ipairs = ipairs,
      script = {
        on_load = function(callback) callbacks.load = callback end,
        on_init = function(callback) callbacks.init = callback end,
        on_configuration_changed = function(callback) callbacks.configuration = callback end,
        on_event = function(event_id, callback) calls[#calls + 1] = {event_id = event_id, callback = callback} end
      },
      defines = {events = {}}
    }
    local notice = {
      requires_features = {"scripted_techs"},
      on_init = function() record(notice_calls, "on_init") end,
      on_load = function() record(notice_calls, "on_load") end,
      on_configuration_changed = function() record(notice_calls, "on_configuration_changed") end
    }
    local browser = {
      requires_features = {"research_library"}, register = function() record(browser_calls, "register") end,
      on_load = function() record(browser_calls, "on_load") end,
      on_init = function() record(browser_calls, "on_init") end,
      on_configuration_changed = function() record(browser_calls, "on_configuration_changed") end
    }
    environment.require = function(name)
      if name == "prototypes.mir.platform.factorio.target_line" then
        return {feature_enabled = function(feature) return feature == "research_library" and library end}
      end
      if name == "prototypes.mir.runtime.compiler_profile_notice" then return notice end
      if name == "prototypes.mir.runtime.research_browser" then return browser end
      if name == "prototypes.mir.runtime.state" then return {bucket = function() return {} end} end
      if name == "prototypes.mir.runtime.startup_settings" then return {get = function() return false end} end
      return {
        requires_features = {}, register = function() record(passive_calls, "register") end,
        on_load = function() record(passive_calls, "on_load") end,
        on_init = no_op, on_configuration_changed = no_op
      }
    end
    assert(load(source, "actual-notice-coordinator-" .. target, "t", environment))().register()
    callbacks.load(); callbacks.init({}); callbacks.configuration({})
    check("CPN-10-" .. target, (notice_calls.on_load or 0) == 1
        and (notice_calls.on_init or 0) == 1 and (notice_calls.on_configuration_changed or 0) == 1,
      target .. " delegates exact load/init/configuration lifecycle points to the notice")
    check("CPN-11-" .. target, (browser_calls.on_load or 0) == 1
        and (browser_calls.on_init or 0) == 1 and (browser_calls.on_configuration_changed or 0) == 1,
      target .. " preserves existing Library lifecycle routing while adding the notice")
  end
  for target, source in pairs(adapter_sources) do adapter_control(target, source) end

  if #failures > 0 then error(table.concat(failures, "\n"), 0) end
  return {assertions = assertions}
end