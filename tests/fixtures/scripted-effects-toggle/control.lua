-- Disposable F200 Space Age startup-setting lifecycle witness.  It uses
-- actual labs, native agricultural-tower events, and native spoil clocks;
-- it never reads MIR's storage or synthesizes a gameplay event.
local KEY = "mir5_scripted_effects_toggle"
local FIXTURE = "mir-fixture-mir5-scripted-effects-toggle"
local CASE = "scripted-effects-toggle"
local SAVE = "mir5-native-complete"
local AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
local SPOILAGE = "recipe-prod-research_spoilage_preservation-1"
local FOREIGN = "mir5-scripted-effects-toggle-foreign"
local PROBE = "braking-force-1"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
  "cryogenic-science-pack", "space-science-pack"
}
local GROWTH_TICKS = 18000
local SPOIL_TICKS = 600
local EFFECT = .01
local DEADLINE = 60 * 60 * 40
local loaded_snapshot, initial_logged = nil, false
local marker

local function fail(message) error("[mir5-scripted-effects-toggle] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= .000001
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then
    fail("technology is absent: " .. name)
  end
  return value
end

local function stage()
  local expected = {
    base = "2.0.77", ["elevated-rails"] = "2.0.77", quality = "2.0.77", ["space-age"] = "2.0.77",
    ["more-infinite-research"] = "5.0.20000",
    ["mir-fixture-mir5-active-mods-observer"] = "0.1.0"
  }
  for name, version in pairs(script.active_mods) do
    if name ~= FIXTURE and expected[name] ~= version then
      fail("unexpected scripted-effects toggle closure member " .. tostring(name))
    end
  end
  for name, version in pairs(expected) do
    if script.active_mods[name] ~= version then fail("missing scripted-effects toggle closure member " .. name) end
  end
  local version = script.active_mods[FIXTURE]
  local names = { ["0.1.0"] = "enabled", ["0.2.0"] = "disabled", ["0.3.0"] = "reenabled" }
  local name = names[version]
  if name == nil then fail("fixture version differs") end
  local agriculture = settings.startup["ips-enable-research_agricultural_growth_speed"]
  local spoilage = settings.startup["ips-enable-research_spoilage_preservation"]
  if agriculture == nil or spoilage == nil or type(agriculture.value) ~= "boolean" or type(spoilage.value) ~= "boolean" then
    fail("scripted-effects toggle setting is absent")
  end
  local enabled = name ~= "disabled"
  if agriculture.value ~= enabled or spoilage.value ~= enabled then
    fail("scripted-effects toggle setting differs for " .. name)
  end
  return {name = name, enabled = enabled, version = version}
end

local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end

local function snapshot_queue(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {
    current = force.current_research and force.current_research.name or false,
    queue = queue,
    progress = force.research_progress
  }
end

local function assert_queue(force, expected, label)
  local actual = snapshot_queue(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue differs at " .. tostring(index)) end
  end
end

local function assert_target(force, name, enabled, label)
  local value = technology(force, name)
  if value.level ~= 2 or value.researched ~= false or value.enabled ~= enabled
      or value.research_unit_count ~= 1 or value.research_unit_energy ~= 60 then
    fail(label .. " scripted target differs: " .. name)
  end
  return value
end

local function assert_foreign(state)
  local foreign = game.forces[state.foreign_index]
  if foreign == nil or foreign.valid == false or foreign.name ~= FOREIGN then fail("foreign force is absent") end
  assert_queue(foreign, state.foreign_queue, "foreign")
end

local function power_lab(lab)
  local input = lab and lab.valid and lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("fixture lab input is absent") end
  lab.energy, lab.active = 100000000, true
end

local function start_research(state, name)
  local force, value = game.forces.player, technology(game.forces.player, name)
  if force.current_research ~= nil or value.enabled ~= true or force.add_research(value) ~= true then
    fail("could not begin actual lab research " .. name)
  end
  power_lab(state.lab)
end

local function set_yumako_soil(surface, center)
  local tiles = {}
  for x = center.x - 5, center.x + 5 do
    for y = center.y - 5, center.y + 5 do
      tiles[#tiles + 1] = {name = "natural-yumako-soil", position = {x = x, y = y}}
    end
  end
  surface.set_tiles(tiles)
  if surface.get_tile(center).name ~= "natural-yumako-soil" then fail("could not prepare native yumako soil") end
end

local function create_tower(surface, center)
  local tower = surface.create_entity{name = "agricultural-tower", position = center, force = game.forces.player}
  if tower == nil or tower.valid == false then fail("could not create native agricultural tower") end
  tower.energy = 100000000
  local input = tower.get_inventory(defines.inventory.agricultural_tower_input)
  if input == nil or input.insert{name = "yumako-seed", count = 1} ~= 1 then
    fail("could not insert native yumako seed")
  end
  return tower
end

local function create_spoilage_chest(surface, position)
  local chest = surface.create_entity{name = "wooden-chest", position = position, force = game.forces.player}
  if chest == nil or chest.valid == false then fail("could not create native spoilage chest") end
  local input = chest.get_inventory(defines.inventory.chest)
  if input == nil or input.insert{name = "yumako", count = 1} ~= 1 then fail("could not insert native yumako") end
  local stack = input[1]
  if stack == nil or stack.valid_for_read == false or stack.name ~= "yumako" or type(stack.spoil_tick) ~= "number" then
    fail("native yumako stack has no spoil clock")
  end
  return chest, stack.spoil_tick - game.tick
end

local function assert_lab_witness(state)
  local input = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("real lab input disappeared") end
  for _, name in ipairs(SCIENCE) do
    local expected = (name == "electromagnetic-science-pack" or name == "space-science-pack") and 3 or 2
    if input.get_item_count(name) ~= expected then
      fail("actual lab science witness differs for " .. name)
    end
  end
end

local function assert_source_complete(state)
  if state.phase ~= "source-complete" or state.actual_labs ~= 2 then fail("enabled source lab witness differs") end
  assert_target(game.forces.player, AGRICULTURE, true, "enabled source")
  assert_target(game.forces.player, SPOILAGE, true, "enabled source")
  if not close(game.difficulty_settings.spoil_time_modifier, 2.02) then
    fail("enabled source spoilage effect differs")
  end
  assert_lab_witness(state)
  assert_foreign(state)
end

local function assert_disabled(state)
  if state.phase ~= "source-complete" and state.phase ~= "disabled-complete" then fail("disabled stage has no enabled source witness") end
  assert_target(game.forces.player, AGRICULTURE, false, "disabled stage")
  assert_target(game.forces.player, SPOILAGE, false, "disabled stage")
  if not close(game.difficulty_settings.spoil_time_modifier, 2) then
    fail("disabled stage did not restore matching spoilage baseline")
  end
  assert_lab_witness(state)
  assert_foreign(state)
end

local function assert_reenabled(state)
  if state.phase ~= "disabled-complete" and state.phase ~= "reenabled-complete" then fail("reenabled stage has no disabled witness") end
  assert_target(game.forces.player, AGRICULTURE, true, "reenabled stage")
  assert_target(game.forces.player, SPOILAGE, true, "reenabled stage")
  if not close(game.difficulty_settings.spoil_time_modifier, 3.03) then
    fail("reenabled stage did not apply retained spoilage level to external baseline")
  end
  assert_lab_witness(state)
  assert_foreign(state)
end

local function begin_physical(state, label, modifier, accelerated)
  local surface = game.surfaces.nauvis
  if surface == nil or surface.get_property("pressure") ~= 1000 then fail("Nauvis does not meet agricultural tower contract") end
  local center = label == "enabled" and {x = 64, y = 0} or label == "disabled" and {x = 128, y = 0} or {x = 192, y = 0}
  surface.request_to_generate_chunks(center, 1)
  surface.force_generate_chunk_requests()
  if not close(game.difficulty_settings.spoil_time_modifier, modifier) then
    fail(label .. " physical witness started with wrong spoilage baseline")
  end
  state.phase, state.physical_label, state.physical_accelerated = "physical", label, accelerated
  state.plant, state.remaining_growth, state.spoiled = nil, nil, false
  state.tower, state.chest, state.observed_spoil = nil, nil, nil
  state.expected_modifier, state.expected_spoil = modifier, SPOIL_TICKS * modifier
  state.deadline = game.tick + DEADLINE
  set_yumako_soil(surface, center)
  state.tower = create_tower(surface, center)
  state.chest, state.observed_spoil = create_spoilage_chest(surface, {x = center.x, y = center.y + 12})
  if math.abs(state.observed_spoil - state.expected_spoil) > 1 then
    fail(label .. " native spoil clock differs")
  end
end

local function finish_physical(state)
  if state.plant == nil or state.spoiled ~= true then return false end
  local expected_growth = state.physical_accelerated and math.floor(GROWTH_TICKS / (1 + EFFECT)) or GROWTH_TICKS
  if state.remaining_growth ~= expected_growth then fail(state.physical_label .. " native agricultural timing differs") end
  if math.abs(state.observed_spoil - state.expected_spoil) > 1 then fail(state.physical_label .. " spoil witness changed") end
  if state.physical_label == "enabled" then
    state.phase = "source-complete"
    assert_source_complete(state)
  elseif state.physical_label == "disabled" then
    -- This is an independently supplied external baseline while MIR is
    -- disabled.  The next configuration callback must observe and rebase it.
    game.difficulty_settings.spoil_time_modifier = 3
    if not close(game.difficulty_settings.spoil_time_modifier, 3) then fail("external disabled rebase did not apply") end
    state.external_baseline, state.expected_modifier = 3, 3
    state.phase = "disabled-complete"
    assert_foreign(state)
  else
    state.phase = "reenabled-complete"
    assert_reenabled(state)
  end
  initial_logged = true
  marker("initial", state)
  game.server_save(SAVE)
  return true
end

marker = function(stage_name, state)
  local player = game.forces.player
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE, stage = stage_name, status = "passed", fixture_stage = stage().name,
    actual_labs = state.actual_labs or 0,
    agricultural_level = technology(player, AGRICULTURE).level,
    spoilage_level = technology(player, SPOILAGE).level,
    spoil_time_modifier = game.difficulty_settings.spoil_time_modifier,
    physical_label = state.physical_label,
    physical_growth_ticks = state.remaining_growth,
    physical_spoil_ticks = state.observed_spoil,
    external_baseline = state.external_baseline,
    foreign_queue_current = state.foreign_queue and state.foreign_queue.current,
    foreign_queue_progress = state.foreign_queue and state.foreign_queue.progress,
    on_load_read_only = stage_name == "reload",
    gameplay_scope = "f200-space-age-scripted-effects-startup-toggle-only"
  }))
end

script.on_init(function()
  local current = stage()
  if current.name ~= "enabled" then fail("toggle fixture must start at enabled stage") end
  local surface, player = game.surfaces.nauvis, game.forces.player
  if surface == nil then fail("Nauvis is absent") end
  player.enable_all_prototypes()
  for _, name in ipairs({AGRICULTURE, SPOILAGE}) do
    local value = technology(player, name)
    prerequisites(value)
    if value.level ~= 1 or value.researched then fail("enabled target did not begin at native level one") end
    value.enabled, value.visible_when_disabled = true, false
  end
  -- A foreign baseline supplied before the real spoilage completion.
  game.difficulty_settings.spoil_time_modifier = 2
  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  local probe = technology(foreign, PROBE)
  prerequisites(probe)
  if foreign.add_research(probe) ~= true then fail("could not queue foreign probe") end
  foreign.research_progress = .42
  local lab = surface.create_entity{name = "lab", position = player.get_spawn_position(surface), force = player}
  if lab == nil or lab.valid == false then fail("could not create real lab") end
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("fixture lab input is absent") end
  for _, name in ipairs(SCIENCE) do
    if input.insert{name = name, count = 4} ~= 4 then fail("fixture lab rejected " .. name) end
  end
  storage[KEY] = {
    phase = "source-labs", actual_labs = 0, lab = lab, foreign_index = foreign.index,
    foreign_queue = snapshot_queue(foreign), deadline = game.tick + DEADLINE
  }
  start_research(storage[KEY], AGRICULTURE)
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and (state.phase == "source-complete" or state.phase == "disabled-complete"
      or state.phase == "reenabled-complete") then
    loaded_snapshot = {phase = state.phase, labs = state.actual_labs, modifier = state.expected_modifier,
      foreign_progress = state.foreign_queue and state.foreign_queue.progress}
  else
    loaded_snapshot = nil
  end
  initial_logged = false
end)

script.on_configuration_changed(function()
  -- The input save's on_load is not a destination cold-reload witness.
  loaded_snapshot, initial_logged = nil, false
  local current, state = stage(), storage[KEY]
  if current.name == "enabled" then return end
  if type(state) ~= "table" then fail("toggle destination has no enabled source witness") end
  if current.name == "disabled" then
    assert_disabled(state)
    begin_physical(state, "disabled", 2, false)
  else
    assert_reenabled(state)
    begin_physical(state, "reenabled", 3.03, true)
  end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "source-labs" or event.research == nil
      or event.research.force ~= game.forces.player then return end
  if event.research.name == AGRICULTURE then
    state.actual_labs, state.next_research = state.actual_labs + 1, SPOILAGE
  elseif event.research.name == SPOILAGE then
    state.actual_labs, state.next_research, state.phase = state.actual_labs + 1, nil, "source-physical"
  end
  if state.actual_labs > 2 then fail("unexpected scripted research completion") end
end)

script.on_event(defines.events.on_tower_planted_seed, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "physical" or event.tower == nil or event.plant == nil
      or state.tower == nil or event.tower.unit_number ~= state.tower.unit_number then return end
  if event.plant.name ~= "yumako-tree" or event.plant.prototype.growth_ticks ~= GROWTH_TICKS then
    fail("native tower supplied unexpected plant")
  end
  local remaining = event.plant.tick_grown - event.tick
  local expected = state.physical_accelerated and math.floor(GROWTH_TICKS / (1 + EFFECT)) or GROWTH_TICKS
  if state.plant ~= nil or remaining ~= expected then fail("native tower growth witness differs") end
  state.plant, state.remaining_growth = event.plant, remaining
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  if loaded_snapshot ~= nil then
    if state.phase ~= loaded_snapshot.phase or state.actual_labs ~= loaded_snapshot.labs
        or not close((state.expected_modifier or game.difficulty_settings.spoil_time_modifier), game.difficulty_settings.spoil_time_modifier)
        or not close(state.foreign_queue and state.foreign_queue.progress, loaded_snapshot.foreign_progress) then
      fail("on_load changed scripted-effects toggle witness")
    end
    if state.phase == "source-complete" then assert_source_complete(state)
    elseif state.phase == "disabled-complete" then
      assert_target(game.forces.player, AGRICULTURE, false, "disabled reload")
      assert_target(game.forces.player, SPOILAGE, false, "disabled reload")
      if not close(game.difficulty_settings.spoil_time_modifier, 3) then fail("disabled external baseline changed on reload") end
      assert_foreign(state)
    else assert_reenabled(state) end
    loaded_snapshot = nil
    marker("reload", state)
    return
  end
  if state.phase == "source-labs" then
    if game.tick > state.deadline then fail("actual source labs did not complete") end
    if state.lab and state.lab.valid then state.lab.energy = 100000000 end
    if state.next_research and game.forces.player.current_research == nil then
      local next_research = state.next_research
      state.next_research = nil
      start_research(state, next_research)
    end
    return
  end
  if state.phase == "source-physical" then
    assert_target(game.forces.player, AGRICULTURE, true, "source before physical")
    assert_target(game.forces.player, SPOILAGE, true, "source before physical")
    if not close(game.difficulty_settings.spoil_time_modifier, 2.02) then fail("source spoilage level did not retain baseline two") end
    assert_lab_witness(state)
    begin_physical(state, "enabled", 2.02, true)
    return
  end
  if state.phase == "physical" then
    if game.tick > state.deadline then fail("native scripted-effects physical witness did not complete") end
    if state.tower and state.tower.valid then state.tower.energy = 100000000 end
    local inventory = state.chest and state.chest.valid and state.chest.get_inventory(defines.inventory.chest)
    if inventory and inventory.get_item_count("yumako") == 0 and inventory.get_item_count("spoilage") >= 1 then state.spoiled = true end
    if game.tick > state.deadline - DEADLINE + state.expected_spoil + 120 and state.spoiled ~= true then
      fail("native spoil clock did not complete in bounded interval")
    end
    finish_physical(state)
    return
  end
  if (state.phase == "source-complete" or state.phase == "disabled-complete" or state.phase == "reenabled-complete")
      and initial_logged ~= true then
    -- A same-version reload invokes on_load and takes the reload branch. This
    -- fallback makes a non-reloaded initial terminal stage observable once.
    initial_logged = true
    marker("initial", state)
    game.server_save(SAVE)
  end
end)
