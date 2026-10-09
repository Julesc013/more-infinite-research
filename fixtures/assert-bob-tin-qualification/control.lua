local technology_name = "recipe-prod-research_material_tin-1"
local recipe_name = "bob-tin-plate"
local required_level = 3
local raw_direct_level = 2
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local function fail(message)
  error("MIR Bob Tin qualification failed: " .. message)
end

local function assert_startup_profile()
  local profile = settings.startup["mir-settings-profile-import"]
  if not profile or type(profile.value) ~= "string" or string.sub(profile.value, 1, 8) ~= "MIRSET1:" then
    fail("MIRSET1 profile import is absent")
  end
  local cap = settings.startup["ips-max-level-research_material_tin"]
  if not cap or cap.value ~= raw_direct_level then
    fail("raw direct Tin maximum-level setting is not 2")
  end
  local decoded, err = profile_codec.decode(profile.value)
  if not decoded then fail("MIRSET1 profile does not decode: " .. tostring(err)) end
  if not decoded.settings or decoded.settings["ips-max-level-research_material_tin"] ~= required_level then
    fail("MIRSET1 imported Tin maximum-level setting is not 3")
  end
  if startup_settings.raw("ips-max-level-research_material_tin") ~= raw_direct_level then
    fail("package startup-settings raw resolver does not expose direct cap 2")
  end
  if startup_settings.get("ips-max-level-research_material_tin") ~= required_level then
    fail("MIRSET1 imported Tin cap does not override direct cap through package startup-settings resolver")
  end
end

local function configure_research(force)
  force.research_all_technologies()
  local technology = force.technologies[technology_name]
  if not technology then fail("runtime Tin technology is absent") end
  technology.level = required_level - 1
  force.research_queue = {technology}
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("could not establish queued fractional Tin research")
  end
  force.research_progress = 0.42
  storage.mir_bob_tin_qualification = {
    current_research_level = technology.level,
    fractional_progress = force.research_progress,
    queued = true,
    production_observed = false,
    load_observed = false
  }
end

local function assert_finite_cap()
  local force = game.create_force("mir-bob-tin-cap-fixture")
  force.enable_all_prototypes()
  local technology = force.technologies[technology_name]
  if not technology then fail("cap force lacks Tin technology") end
  if technology.prototype.max_level < 4294967295 then fail("Tin prototype is not losslessly infinite") end
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  local offered = {}
  while force.add_research(technology) do
    if not force.current_research or force.current_research.name ~= technology_name then
      fail("accepted Tin cap level was not current research")
    end
    table.insert(offered, technology.level)
    force.research_queue = nil
    force.cancel_current_research()
    technology.researched = true
    if #offered > required_level + 1 then fail("Tin research continued past cap") end
  end
  if technology.level ~= required_level + 1 or technology.researched or technology.enabled then
    fail("Tin runtime cap did not stop after absolute level 3")
  end
end

local function configure_furnace(force)
  local surface = game.surfaces[1]
  local furnace = surface.create_entity{name = "stone-furnace", position = {0, 0}, force = force}
  if not furnace then fail("could not create Bob Tin smelting machine witness") end
  local source = furnace.get_inventory(defines.inventory.crafter_input)
  local fuel = furnace.get_inventory(defines.inventory.fuel)
  if not source or not fuel then fail("stone-furnace inventory witness is unavailable") end
  source.insert{name = "bob-tin-ore", count = 2}
  fuel.insert{name = "coal", count = 4}
  storage.mir_bob_tin_qualification.furnace = furnace
end

script.on_init(function()
  if not script.active_mods.bobplates or script.active_mods.angelssmelting then
    fail("fixture requires Bob-only, without Angel smelting")
  end
  assert_startup_profile()
  local force = game.forces.player
  assert_finite_cap()
  configure_research(force)
  configure_furnace(force)
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir_bob_tin_qualification
  if not state or state.load_observed then return end
  local force = game.forces.player
  local technology = force.technologies[technology_name]
  if technology.level ~= state.current_research_level then fail("current Tin research level changed after load") end
  if not force.current_research or force.current_research.name ~= technology_name then fail("fractional Tin research did not survive load") end
  if math.abs(force.research_progress - state.fractional_progress) > 0.0001 then
    fail("fractional Tin progress did not survive load")
  end
  local queued = false
  for _, entry in ipairs(force.research_queue) do
    if entry.name == technology_name then queued = true end
  end
  if not queued or not state.queued then fail("queued Tin research did not survive load") end
  local furnace = state.furnace
  if not furnace or not furnace.valid then fail("Tin furnace did not survive load") end
  local result = furnace.get_inventory(defines.inventory.crafter_output)
  if result and result.get_item_count("bob-tin-plate") > 0 then state.production_observed = true end
  if event.tick >= 300 then
    if not state.production_observed then fail("Bob Tin production/load observation did not complete") end
    state.load_observed = true
    log("[mir-bob-tin] RUNTIME PASS direct=2 imported=3 effective=3 current-research-level=2 fractional=0.42 queued=true production=true load-observation=true")
  end
end)
