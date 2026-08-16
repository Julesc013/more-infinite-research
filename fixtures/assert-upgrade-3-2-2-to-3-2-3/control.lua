local archetype = settings.startup["mir-upgrade-archetype"].value
local landfill_name = "recipe-prod-research_landfill-1"
local ice_name = "recipe-prod-research_ice-1"
local platform_name = "recipe-prod-research_platform-1"
local progress = 0.42
local epsilon = 0.000001

local function fail(message)
  error("MIR 3.2.2 to 3.2.3 Platform transfer validation failed: " .. message)
end

local function effect_change(technology, recipe_name)
  local found = nil
  for _, effect in pairs((technology and technology.prototype and technology.prototype.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      if found ~= nil then fail("duplicate effect for " .. recipe_name .. " in " .. technology.name) end
      found = effect.change
    end
  end
  return found
end

local function assert_change(technology, recipe_name, expected)
  local actual = effect_change(technology, recipe_name)
  if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
    fail(technology.name .. " change for " .. recipe_name .. " was "
      .. tostring(actual) .. ", expected " .. tostring(expected))
  end
end

local function assert_setting(name, expected)
  local setting = settings.startup[name]
  if not setting or setting.value ~= expected then
    fail("startup setting " .. name .. " was "
      .. tostring(setting and setting.value) .. ", expected " .. tostring(expected))
  end
end

local function recipe_owners(force, recipe_name)
  local out = {}
  for name, technology in pairs(force.technologies) do
    if effect_change(technology, recipe_name) ~= nil then table.insert(out, name) end
  end
  table.sort(out)
  return out
end

script.on_init(function()
  if archetype ~= "space-age-native-owner" then fail("unexpected archetype " .. tostring(archetype)) end
  if script.active_mods["more-infinite-research"] ~= "3.2.2" then
    fail("source save did not use MIR 3.2.2")
  end
  if not script.active_mods["space-age"] then fail("Space Age was not active") end
  assert_setting("ips-cost-base-research_landfill", 4321)
  assert_setting("ips-cost-base-research_ice", 2345)

  local force = game.forces.player
  local landfill = force.technologies[landfill_name]
  local ice = force.technologies[ice_name]
  if not landfill or not ice then fail("source Landfill or Ice technology is missing") end
  if force.technologies[platform_name] then fail("Platform technology existed in the 3.2.2 source") end
  assert_change(landfill, "ice-platform", 0.02)
  assert_change(landfill, "space-platform-foundation", 0.01)

  force.research_all_technologies()
  landfill.level = 4
  ice.level = 3
  if not force.add_research(ice) then fail("could not queue Ice productivity") end
  force.research_progress = progress
  storage.mir_322_323 = {
    landfill_level = landfill.level,
    ice_level = ice.level,
    research_name = force.current_research and force.current_research.name,
    research_progress = force.research_progress,
    landfill_cost = settings.startup["ips-cost-base-research_landfill"].value,
    ice_cost = settings.startup["ips-cost-base-research_ice"].value
  }
  log("[mir-fixture] 3.2.2 upgrade source proof complete archetype=" .. archetype)
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "3.2.3" then
    fail("upgraded save did not use MIR 3.2.3")
  end
  local state = storage.mir_322_323
  if not state then fail("fixture storage did not survive upgrade") end
  local force = game.forces.player
  local landfill = force.technologies[landfill_name]
  local ice = force.technologies[ice_name]
  local platform = force.technologies[platform_name]
  if not landfill or not ice or not platform then fail("upgraded technology set is incomplete") end
  if landfill.level ~= state.landfill_level then fail("Landfill level did not survive") end
  if ice.level ~= state.ice_level then fail("Ice level did not survive") end
  if not force.current_research or force.current_research.name ~= state.research_name then
    fail("current Ice research did not survive")
  end
  if math.abs(force.research_progress - state.research_progress) > epsilon then
    fail("fractional Ice research progress did not survive")
  end
  if platform.researched then fail("Platform technology was automatically granted") end
  if effect_change(landfill, "ice-platform") ~= nil
    or effect_change(landfill, "space-platform-foundation") ~= nil then
    fail("Landfill retained a transferred Platform recipe")
  end
  assert_change(platform, "ice-platform", 0.10)
  assert_change(platform, "space-platform-foundation", 0.05)
  for _, recipe_name in ipairs({"ice-platform", "space-platform-foundation"}) do
    local owners = recipe_owners(force, recipe_name)
    if #owners ~= 1 or owners[1] ~= platform_name then
      fail(recipe_name .. " owner transfer was not exact: " .. table.concat(owners, ","))
    end
  end
  assert_setting("ips-cost-base-research_landfill", state.landfill_cost)
  assert_setting("ips-cost-base-research_ice", state.ice_cost)
  assert_setting("ips-enable-research_platform", true)
  state.upgrade_complete = true
  log("[mir-fixture] 3.2.2 to 3.2.3 upgrade proof complete archetype=" .. archetype)
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir_322_323
  if state and state.upgrade_complete and not state.server_save_requested then
    state.server_save_requested = true
    game.server_save("mir-323-upgraded")
    log("[mir-fixture] governed upgraded save requested tick=" .. event.tick)
  end
end)

script.on_load(function()
  if storage.mir_322_323 and storage.mir_322_323.upgrade_complete then
    log("[mir-fixture] 3.2.3 upgraded save reload proof complete archetype=" .. archetype)
  end
end)
