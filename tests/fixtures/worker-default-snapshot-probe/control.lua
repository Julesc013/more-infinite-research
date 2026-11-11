local probe = require("__mir-fixture-worker-default-snapshot__/snapshot")
local M = {}

function M.on_init()
  probe.closure()
  probe.require(script.active_mods[probe.fixture] == "0.1.0", "source role required")
  local p = prototypes.technology[probe.main]
  probe.require(p and p.level == 4 and p.max_level == 4294967295
    and p.research_unit_count_formula == "675*1.5^(L-4)" and p.research_unit_energy == 3600,
    "unchanged published default work contract")
  local ingredients = p.research_unit_ingredients
  probe.require(#ingredients == #probe.sciences and #p.effects == 1
    and p.effects[1].type == "worker-robot-storage" and p.effects[1].modifier == 1,
    "default science/effect contract")
  for index, pack in ipairs(probe.sciences) do
    probe.require(ingredients[index].name == pack and ingredients[index].amount == 1, "default science vector")
  end
  probe.require(prototypes.get_history("technology", probe.main).created == "more-infinite-research",
    "default creation custody")
  storage.labs, storage.initializing = {}, true
  storage.setup = {scripted_prerequisites=true, scripted_initial_partials=true,
    lab_speed=3600, native_unit_energy=3600, no_claimed_ordinary_completions=true}
  local surface = game.surfaces[1]
  for index, name in ipairs(probe.forces) do
    local force = game.forces[name] or game.create_force(name)
    local row = force.technologies[probe.main]
    for _, prerequisite in pairs(row.prerequisites) do prerequisite.research_recursive() end
    probe.require(row.level == 4 and not row.researched and row.research_unit_count == 675,
      "source starts at unpaid default4")
    probe.require(force.laboratory_speed_modifier == 0 and force.laboratory_productivity_bonus == 0,
      "zero force laboratory bonuses")
    local position = {x=(index-1)*12, y=0}
    local tiles = {}
    for x=-2,2 do for y=-2,2 do
      tiles[#tiles + 1] = {name="stone-path", position={x=position.x+x, y=position.y+y}}
    end end
    surface.set_tiles(tiles)
    local lab = surface.create_entity{name=probe.lab, position=position, force=force}
    probe.require(lab and lab.valid and lab.disabled_by_script == false
      and lab.prototype.get_researching_speed("normal") == 3600, "ordinary active owned lab")
    local input = lab.get_inventory(defines.inventory.lab_input)
    for _, pack in ipairs(probe.sciences) do probe.require(input.insert{name=pack,count=200} == 200, "initial lab supplies") end
    storage.labs[name] = lab
    if index == 1 then
      force.research_queue = {probe.main, probe.sentinel}
      probe.require(force.current_research and force.current_research.name == probe.main, "ordinary current work")
    else
      force.research_queue = index == 2 and {probe.sentinel, probe.main} or {probe.sentinel}
      probe.require(force.current_research and force.current_research.name == probe.sentinel, "foreign current work")
      force.research_progress = index == 2 and .42 or .125 -- explicit diagnostic setup, not earned work.
      row.saved_progress = index == 2 and .27 or .23
    end
  end
  storage.initializing, storage.ordinary_completions = false, 0
  storage.continuous_advances = 0
  probe.emit("source-init", {native_tick=game.tick, native=probe.capture(), setup=storage.setup,
    active_mods=script.active_mods, game_speed=game.speed})
end

function M.on_tick(event)
  if script.active_mods[probe.fixture] ~= "0.1.0" then return end
  probe.closure()
  -- Top up before observing; never remove science or freeze the save boundary.
  for _, name in ipairs(probe.forces) do
    local input = storage.labs[name].get_inventory(defines.inventory.lab_input)
    for _, pack in ipairs(probe.sciences) do
      if input.get_item_count(pack) < 64 then probe.require(input.insert{name=pack,count=200} > 0, "continuous lab supplies") end
    end
  end
  local current, prior = probe.capture(), storage.last_tick
  local labs = probe.lab_witnesses()
  local advancing = prior ~= nil
  for index, row in ipairs(current) do
    local lab = labs[index]
    probe.require(not lab.disabled and lab.modules_empty and lab.speed == 3600
      and lab.force_speed == 0 and lab.force_productivity == 0, "continuous ordinary laboratory controls")
    if not prior or row.current ~= prior.native[index].current or row.progress <= prior.native[index].progress then advancing = false end
  end
  storage.continuous_advances = advancing and storage.continuous_advances + 1 or 0
  storage.last_tick = {tick=event.tick, native=current, continuous_advances=storage.continuous_advances,
    ordinary_completions=storage.ordinary_completions, labs=labs}
  if event.tick == 259 or event.tick == 260 or event.tick == 261 then probe.emit("continuous-source", storage.last_tick) end
  if event.tick == probe.save_tick then
    probe.require(storage.continuous_advances >= 16 and storage.ordinary_completions == 0,
      "autosave must occur during genuinely advancing unfinished native work")
    storage.autosave_requested_tick = event.tick
    probe.emit("autosave-request", {saved_lua=storage.last_tick, active_mods=script.active_mods})
    game.auto_save(probe.save_name)
  end
  -- Keep observing and all labs running AFTER requesting the native autosave.
end

function M.on_configuration_changed(event)
  probe.observe("configuration-entry")
  local change = event and event.mod_changes and event.mod_changes[probe.fixture]
  probe.require(change and change.old_version == "0.1.0" and change.new_version == "0.1.1"
    and event.mod_startup_settings_changed == false, "metadata-only observation transition")
  for name, row in pairs(event.mod_changes) do
    probe.require(name == probe.fixture or row.old_version == row.new_version, "unrelated configuration change")
  end
end

script.on_init(M.on_init)
script.on_load(function() end) -- read-only; observation occurs at migration/configuration.
script.on_configuration_changed(M.on_configuration_changed)
script.on_event(defines.events.on_tick, M.on_tick)
script.on_event(defines.events.on_research_finished, function(event)
  if storage.initializing then return end
  if event and event.by_script == false then storage.ordinary_completions = storage.ordinary_completions + 1 end
end)
return M
