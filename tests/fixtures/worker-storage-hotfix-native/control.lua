local CASE, SAVE = "worker-storage-hotfix", "mir5-native-complete"
local MAIN, OTHER = "worker-robots-storage-8", "mir-worker-storage-hotfix-unrelated"
local FOREIGN = {"worker-robots-storage-4", "worker-robots-storage-5", "worker-robots-storage-6", "worker-robots-storage-7"}
local loaded = false

local function fail(message) error("[" .. CASE .. "] " .. message) end
local function close(left, right) return type(left) == "number" and math.abs(left - right) < .000001 end
local function technology(force, name)
  local value = force.technologies[name]
  if not value or value.valid == false then fail("missing technology " .. name) end
  return value
end
local function names(rows)
  local out = {}
  for _, row in pairs(rows or {}) do out[row.name] = true end
  return out
end
local function assert_prototypes(force)
  local main = technology(force, MAIN)
  if main.level < 8 or main.level > 9 or main.prototype.max_level < 4294967295 then fail("MIR continuation is not infinite level eight") end
  local ingredients, prerequisites = names(main.prototype.research_unit_ingredients), names(main.prerequisites)
  if not ingredients["automation-science-pack"] or not ingredients["utility-science-pack"] then fail("MIR8 lost inherited science") end
  if not prerequisites["worker-robots-storage-7"] then fail("MIR8 lost terminal provider prerequisite") end
  if script.active_mods["space-is-fake"] then
    if ingredients["space-science-pack"] or prerequisites["space-science-pack"] then fail("SIF candidate retained white science") end
  elseif not ingredients["space-science-pack"] then fail("available white science was removed without SIF") end
  for index, name in ipairs(FOREIGN) do
    local value = technology(force, name)
    if value.prototype.effects[1].type ~= "worker-robot-storage" or value.prototype.effects[1].modifier ~= 1 then
      fail(name .. " foreign effect changed")
    end
    if value.prototype.max_level ~= index + 3 then fail(name .. " foreign finite level changed") end
  end
  return main
end
local function marker(stage, force, state)
  local main = technology(force, MAIN)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={mir=script.active_mods["more-infinite-research"], sif=script.active_mods["space-is-fake"] ~= nil,
      main=MAIN, initial_level=8, current_level=main.level, worker_bonus=force.worker_robots_storage_bonus,
      actual_lab_completions=state.completions, foreign_finite={4,5,6,7},
      foreign_effect=1, white_retired=not not (script.active_mods["space-is-fake"]),
      initial_biolab_input_slots=state.input_slots,
      current_progress=force.research_progress, unrelated_progress=technology(force, OTHER).saved_progress,
      on_load_read_only=stage == "reload"},
  }))
end
local function verify_saved(force, state)
  local main, other = technology(force, MAIN), technology(force, OTHER)
  assert_prototypes(force)
  if main.level ~= 9 or state.completions ~= 1 or force.worker_robots_storage_bonus ~= 8 then fail("earned worker bonus changed") end
  if force.current_research ~= main or not close(force.research_progress, .42) then fail("main partial research changed") end
  if not close(other.saved_progress, .27) then fail("unrelated saved progress changed") end
  local queue = force.research_queue or {}
  if #queue ~= 2 or queue[1] ~= main or queue[2] ~= other then fail("saved research queue changed") end
end
local function start(force, state, main)
  local lab = state.lab
  if not lab or lab.valid == false then fail("biolab is absent") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("biolab input is absent") end
  state.input_slots = #inventory
  if force.add_research(main) ~= true or force.current_research ~= main then fail("could not start MIR8 actual research") end
end

script.on_init(function()
  local force = game.forces.player
  local main = assert_prototypes(force)
  for _, prerequisite in pairs(main.prerequisites) do prerequisite.researched = true end
  for _, name in ipairs({"worker-robots-storage-1", "worker-robots-storage-2", "worker-robots-storage-3",
      "worker-robots-storage-4", "worker-robots-storage-5", "worker-robots-storage-6", "worker-robots-storage-7"}) do
    technology(force, name).researched = true
  end
  if main.enabled ~= true or force.worker_robots_storage_bonus ~= 7 then fail("provider-only earned baseline is not seven") end
  force.laboratory_speed_modifier = 1000
  local lab = game.surfaces.nauvis.create_entity{name="biolab", position={0, 0}, force=force}
  if not lab or lab.valid == false then fail("could not create actual biolab") end
  local state = {lab=lab, completions=0, phase="researching"}
  storage.worker_storage_hotfix = state
  game.speed = 16
  start(force, state, main)
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state, force = storage.worker_storage_hotfix, game.forces.player
  if not state or not event.research or event.research.force ~= force or event.research.name ~= MAIN then return end
  if event.by_script ~= false then fail("MIR8 was not completed by a real lab") end
  state.completions = state.completions + 1
  if state.completions ~= 1 or force.worker_robots_storage_bonus ~= 8 then fail("MIR8 completion did not add one capacity") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  state.lab.energy = 0; inventory.clear()
  local main, other = technology(force, MAIN), technology(force, OTHER)
  force.research_queue = {main, other}; force.research_progress = .42; other.saved_progress = .27
  state.phase = "saved"
  verify_saved(force, state)
  marker("initial", force, state)
  game.server_save(SAVE)
end)

script.on_load(function()
  local state = storage.worker_storage_hotfix
  loaded = type(state) == "table" and state.phase == "saved"
end)

script.on_event(defines.events.on_tick, function()
  local state = storage.worker_storage_hotfix
  if state and state.phase == "researching" then
    local force, main = game.forces.player, technology(game.forces.player, MAIN)
    local inventory = state.lab.get_inventory(defines.inventory.lab_input)
    for _, ingredient in pairs(main.prototype.research_unit_ingredients) do inventory.insert{name=ingredient.name, count=1000} end
    state.lab.energy = 1000000000
  end
  if not loaded then return end
  loaded = false
  local reload_state, force = storage.worker_storage_hotfix, game.forces.player
  verify_saved(force, reload_state)
  marker("reload", force, reload_state)
end)
