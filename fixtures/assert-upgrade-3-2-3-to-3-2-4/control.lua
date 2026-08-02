local archetype = settings.startup["mir-upgrade-archetype"].value
local technology_name = "recipe-prod-research_gears-1"
local progress = 0.42
local epsilon = 0.000001

local function fail(message)
  error("MIR 3.2.3 to 3.2.4 research-cost upgrade validation failed: " .. message)
end

local function assert_setting(name, expected)
  local setting = settings.startup[name]
  if not setting or setting.value ~= expected then
    fail("startup setting " .. name .. " was "
      .. tostring(setting and setting.value) .. ", expected " .. tostring(expected))
  end
end

script.on_init(function()
  if archetype ~= "space-age-native-owner" then fail("unexpected archetype " .. tostring(archetype)) end
  if script.active_mods["more-infinite-research"] ~= "3.2.3" then
    fail("source save did not use MIR 3.2.3")
  end
  if settings.startup["ips-cost-linear-increment-research_gears"]
    or settings.startup["mir-cost-linear-increment-worker-robots-storage"] then
    fail("linear increment settings existed in the source save")
  end
  assert_setting("ips-cost-base-research_gears", 4321)
  assert_setting("ips-cost-growth-research_gears", 1.25)
  assert_setting("mir-cost-base-worker-robots-storage", 2345)
  assert_setting("mir-cost-growth-worker-robots-storage", 1.1)

  local force = game.forces.player
  local technology = force.technologies[technology_name]
  if not technology then fail("gears productivity technology is missing") end
  force.research_all_technologies()
  technology.level = 4
  if not force.add_research(technology) then fail("could not queue gears productivity") end
  force.research_progress = progress
  storage.mir_323_324 = {
    technology_level = technology.level,
    research_name = force.current_research and force.current_research.name,
    research_progress = force.research_progress
  }
  log("[mir-fixture] 3.2.3 upgrade source proof complete archetype=" .. archetype)
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "3.2.4" then
    fail("upgraded save did not use MIR 3.2.4")
  end
  local state = storage.mir_323_324
  if not state then fail("fixture storage did not survive upgrade") end
  local force = game.forces.player
  local technology = force.technologies[technology_name]
  if not technology then fail("upgraded gears productivity technology is missing") end
  if technology.level ~= state.technology_level then fail("technology level did not survive") end
  if not force.current_research or force.current_research.name ~= state.research_name then
    fail("current research did not survive")
  end
  if math.abs(force.research_progress - state.research_progress) > epsilon then
    fail("fractional research progress did not survive")
  end
  assert_setting("ips-cost-base-research_gears", 4321)
  assert_setting("ips-cost-growth-research_gears", 1.25)
  assert_setting("mir-cost-base-worker-robots-storage", 2345)
  assert_setting("mir-cost-growth-worker-robots-storage", 1.1)
  assert_setting("ips-cost-linear-increment-research_gears", 0)
  assert_setting("mir-cost-linear-increment-worker-robots-storage", 0)
  state.upgrade_complete = true
  log("[mir-fixture] 3.2.3 to 3.2.4 upgrade proof complete archetype=" .. archetype)
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir_323_324
  if state and state.upgrade_complete and not state.server_save_requested then
    state.server_save_requested = true
    game.server_save("mir-324-upgraded")
    log("[mir-fixture] governed upgraded save requested tick=" .. event.tick)
  end
end)

script.on_load(function()
  if storage.mir_323_324 and storage.mir_323_324.upgrade_complete then
    log("[mir-fixture] 3.2.4 upgraded save reload proof complete archetype=" .. archetype)
  end
end)
