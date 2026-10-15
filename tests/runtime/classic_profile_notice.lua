-- Source-bound lifecycle controls for the compiler-profile notice.  The
-- saved `classic` value aliases Full in current packages; existing private
-- Classic notification APIs remain characterized, but on_load must never
-- create an on_tick handler absent from the saved server.
return function(notice_source, profile_source, adapter_sources)
  local assertions, failures = 0, {}
  local function check(id, condition, detail)
    assertions = assertions + 1
    if condition then return end
    failures[#failures + 1] = id .. ": " .. detail
  end

  local function actual_profile(raw_value)
    local environment = {
      type = type, tostring = tostring,
      settings = {startup = { ["mir-compiler-profile"] = {value = raw_value} }}
    }
    return assert(load(profile_source, "actual-compiler-profile", "t", environment))()
  end

  local function notice_world(name, profile, line)
    local callbacks, registrations, printed, profile_reads = {}, {}, {}, 0
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
    environment.require = function(module_name)
      if module_name == "prototypes.mir.settings.compiler_profile" then
        return {get = function(actual_line)
          profile_reads = profile_reads + 1
          return profile.get(actual_line)
        end}
      end
      if module_name == "prototypes.mir.platform.factorio.target_line" then
        return {factorio_version = line or "2.0"}
      end
      error("unexpected notice dependency " .. tostring(module_name), 0)
    end
    local notice = assert(load(notice_source, "actual-compiler-profile-notice-" .. name, "t", environment))()
    local function no_game_proxy()
      environment.game = setmetatable({}, {__index = function()
        error("notice lifecycle accessed LuaGameScript", 0)
      end})
    end
    local function set_game(players)
      environment.game = {connected_players = players}
    end
    return {
      notice = notice,
      callbacks = callbacks,
      registrations = registrations,
      printed = printed,
      no_game_proxy = no_game_proxy,
      set_game = set_game,
      profile_reads = function() return profile_reads end,
      player = function(valid, player_name)
        return {valid = valid, print = function(caption)
          printed[#printed + 1] = {name = player_name, caption = caption}
        end}
      end
    }
  end

  -- This direct source guard rejects the former deferred on_load subscription.
  check("CPN-01", not notice_source:find("script.on_event", 1, true),
    "notice must not own an on_tick subscription")

  -- Opposing legacy behavior: the harness sees exactly the reported drift
  -- when an on_load implementation registers a one-shot tick after a server
  -- has saved with no such handler.
  local legacy_source = "local M={} function M.on_load() script.on_event(defines.events.on_tick,function() end) end return M"
  local legacy = notice_world("legacy-opposite", actual_profile("full"), "2.0")
  legacy.notice = assert(load(legacy_source, "legacy-on-load-opposite", "t", {
    defines = {events = {on_tick = 61}}, script = {
      on_event = function(event_id, callback)
        legacy.callbacks[event_id] = callback
        legacy.registrations[#legacy.registrations + 1] = {event_id = event_id, callback = callback}
      end
    }
  }))()
  check("CPN-02", legacy.callbacks[61] == nil and #legacy.registrations == 0,
    "saved server begins without the legacy notice handler")
  legacy.notice.on_load()
  check("CPN-03", type(legacy.callbacks[61]) == "function" and #legacy.registrations == 1,
    "opposing legacy on_load reproduces the server/client handler mismatch")

  -- Both serialized values must execute Full for both current modern lines.
  for _, line in ipairs({"2.0", "2.1"}) do
    for _, raw_value in ipairs({"full", "classic"}) do
      local profile = actual_profile(raw_value)
      local fresh = notice_world("fresh-" .. line .. "-" .. raw_value, profile, line)
      fresh.no_game_proxy()
      fresh.notice.on_init()
      check("CPN-04-" .. line .. "-" .. raw_value,
        #fresh.registrations == 0 and #fresh.printed == 0 and fresh.profile_reads() == 1,
        "fresh " .. line .. " " .. raw_value .. " stays Full without a notice")

      local saved = notice_world("saved-" .. line .. "-" .. raw_value, profile, line)
      saved.set_game({saved.player(true, "server")})
      saved.notice.on_init()
      saved.notice.on_configuration_changed({})
      check("CPN-05-" .. line .. "-" .. raw_value,
        #saved.registrations == 0 and saved.callbacks[61] == nil and #saved.printed == 0,
        "saved server has no notice tick for " .. line .. " " .. raw_value)

      local load = notice_world("load-" .. line .. "-" .. raw_value, profile, line)
      load.no_game_proxy()
      local loaded = pcall(load.notice.on_load)
      load.notice.on_load()
      check("CPN-06-" .. line .. "-" .. raw_value,
        loaded and load.profile_reads() == 0 and #load.registrations == 0 and load.callbacks[61] == nil,
        "load leaves the saved handler set unchanged for " .. line .. " " .. raw_value)

      local client = notice_world("client-" .. line .. "-" .. raw_value, profile, line)
      client.no_game_proxy()
      client.notice.on_load()
      client.set_game({client.player(true, "joining-client")})
      client.notice.on_load()
      check("CPN-07-" .. line .. "-" .. raw_value,
        #client.registrations == 0 and client.callbacks[61] == nil and #client.printed == 0,
        "reload and joining client preserve handler parity for " .. line .. " " .. raw_value)
    end
  end

  -- Preserve the retained private API for a historical controlled caller: it
  -- may still request a Classic warning, but loading never schedules a tick.
  local classic_profile = {get = function() return "classic" end}
  local retained = notice_world("retained-private-classic", classic_profile, "2.0")
  retained.set_game({retained.player(true, "first"), retained.player(true, "second")})
  retained.notice.on_init()
  retained.notice.on_configuration_changed({mod_changes = {
    ["more-infinite-research"] = {old_version = "4.3.20001"}
  }})
  retained.no_game_proxy()
  retained.notice.on_load()
  check("CPN-08", #retained.printed == 4
      and retained.printed[1].caption[1] == "mir-message.classic-profile-initial-scope"
      and retained.printed[3].caption[1] == "mir-message.classic-profile-upgrade-warning"
      and retained.printed[3].caption[2] == "4.3.20001"
      and #retained.registrations == 0 and retained.callbacks[61] == nil,
    "retained private Classic notices do not restore the removed deferred subscription")

  local function adapter_control(target, source)
    local callbacks, event_calls = {}, {}
    local environment = {
      type = type, error = error, ipairs = ipairs,
      script = {
        on_load = function(callback) callbacks.load = callback end,
        on_init = function(callback) callbacks.init = callback end,
        on_configuration_changed = function(callback) callbacks.configuration = callback end,
        on_event = function(event_id, callback)
          event_calls[#event_calls + 1] = {event_id = event_id, callback = callback}
        end
      },
      defines = {events = {on_tick = 61}}
    }
    local actual_notice
    local full_profile = actual_profile("classic")
    local no_op = function() end
    environment.require = function(module_name)
      if module_name == "prototypes.mir.platform.factorio.target_line" then
        return {factorio_version = "2.0", feature_enabled = function(feature) return feature == "research_library" and false end}
      end
      if module_name == "prototypes.mir.settings.compiler_profile" then return full_profile end
      if module_name == "prototypes.mir.runtime.compiler_profile_notice" then
        if not actual_notice then actual_notice = assert(load(notice_source, "actual-notice-coordinator-" .. target, "t", environment))() end
        return actual_notice
      end
      if module_name == "prototypes.mir.runtime.state" then return {bucket = function() return {} end} end
      if module_name == "prototypes.mir.runtime.startup_settings" then return {get = function() return false end} end
      return {
        requires_features = {}, register = no_op, on_load = no_op,
        on_init = no_op, on_configuration_changed = no_op
      }
    end
    assert(load(source, "actual-notice-coordinator-" .. target, "t", environment))().register()
    check("CPN-09-" .. target, type(callbacks.load) == "function"
        and type(callbacks.init) == "function" and type(callbacks.configuration) == "function",
      target .. " keeps its one coordinator lifecycle registration")
    environment.game = setmetatable({}, {__index = function() error("adapter load accessed game", 0) end})
    local before = #event_calls
    callbacks.load()
    callbacks.init({})
    callbacks.configuration({})
    check("CPN-10-" .. target, #event_calls == before,
      target .. " delegates fresh/save/load lifecycle points without creating an on_tick handler")
  end

  for target, source in pairs(adapter_sources) do adapter_control(target, source) end

  if #failures > 0 then error(table.concat(failures, "\n"), 0) end
  return {assertions = assertions}
end
