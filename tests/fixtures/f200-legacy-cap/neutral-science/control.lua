local ID = "mir-fixture-native-science-consumption"
local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
local loaded, logged = false, false
local function check(condition, message)
  assert(condition, "[native-science-control] " .. message)
end
local function observe(stage, state)
  check(script.active_mods.base == "2.1.23" and script.active_mods["more-infinite-research"] == nil,
    "engine/MIR closure differs")
  local lab = state.lab
  check(lab and lab.valid and lab.disabled_by_script and lab.energy == 0, "finished lab differs")
  check(state.actual_labs == 1 and game.forces.player.technologies[ID].level == 2, "one real native completion is absent")
  local inventory, counts = lab.get_inventory(defines.inventory.lab_input), {}
  for _, name in ipairs(PACKS) do
    counts[name] = inventory.get_item_count(name)
    check(counts[name] == 15, "one item per science pack was not consumed: " .. name)
  end
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read then check(stack.is_tool == false and stack.type == "item", "science is not an ordinary item") end
  end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "native-science-consumption", stage = stage, status = "passed",
    mir_absent = true, source_progress = .27, research_unit_count = 1, research_unit_energy = 60,
    inserted_per_pack = 16, consumed_per_pack = 1, remaining = counts,
    actual_lab_completions = state.actual_labs, next_level = 2,
    raw_elapsed_ticks = state.finished_tick - state.start_tick, on_load_read_only = stage == "reload",
  }))
end
script.on_init(function()
  check(script.active_mods["more-infinite-research"] == nil, "MIR is present")
  local force = game.forces.player
  local research = force.technologies[ID]
  check(research.research_unit_count == 1 and research.research_unit_energy == 60, "native unit workload differs")
  local lab = game.surfaces[1].create_entity{name = "lab", position = {0, 0}, force = force}
  check(lab and lab.valid, "lab creation failed")
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  for _, name in ipairs(PACKS) do check(inventory.insert{name = name, count = 16} == 16, "science insertion failed") end
  lab.energy = 1000000000
  check(force.add_research(ID) == true, "research queue failed")
  force.research_progress = .27
  check(math.abs(force.research_progress - .27) < .000001, "partial research seed differs")
  storage.native_science_control = {lab = lab, start_tick = game.tick, phase = "running", actual_labs = 0}
end)
script.on_event(defines.events.on_research_finished, function(event)
  local state = storage.native_science_control
  if event.research.name == ID and event.research.force == game.forces.player then
    check(state and state.phase == "running", "completion phase differs")
    state.actual_labs, state.finished_tick, state.phase = state.actual_labs + 1, game.tick, "finished"
  end
end)
script.on_load(function() loaded, logged = true, false end)
script.on_event(defines.events.on_tick, function()
  local state = storage.native_science_control
  check(state ~= nil, "saved control state is absent")
  if state.phase == "running" then
    check(game.tick - state.start_tick < 600, "native lab deadline exceeded")
    state.lab.energy = 1000000000
  elseif state.phase == "finished" then
    state.lab.disabled_by_script, state.lab.energy, state.phase = true, 0, "completed"
    observe("initial", state)
    game.server_save("mir5-native-complete")
  elseif state.phase == "completed" and loaded and not logged then
    observe("reload", state)
    logged = true
  end
end)
