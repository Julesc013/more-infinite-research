-- Native base-only A04 witness. No data-stage mutations, rocket-part writes,
-- manufactured space science, research-progress writes or research-all calls.
-- Test setup supplies prerequisites, entities, exact inputs and electrical power.
local prefix = "[mir-a04-launch] "
local key = "mir_a04_launch"
local science = "space-science-pack"
local technology_name = "research-speed-7"
local loaded_phase, terminal_reported

local function insist(condition, message)
  if not condition then error(prefix .. message) end
end

local function environment()
  local version = script.active_mods.base or ""
  local target = version:sub(1, 3)
  insist(target == "2.0" or target == "2.1", "unsupported engine family")
  local expected = target == "2.0" and "4.2.20002" or "4.2.21002"
  insist(script.active_mods["more-infinite-research"] == expected, "wrong MIR identity")
  for name in pairs(script.active_mods) do
    insist(name == "base" or name == "core" or name == "more-infinite-research"
      or name == "mir-fixture-assert-modern-launch-return", "unexpected active mod " .. name)
  end
end

local function reaches(technology, name, seen)
  if technology.name == name then return true end
  seen = seen or {}
  if seen[technology.name] then return false end
  seen[technology.name] = true
  for _, prerequisite in pairs(technology.prerequisites) do
    if reaches(prerequisite, name, seen) then return true end
  end
  return false
end

local function catalogue(force)
  for _, name in ipairs({technology_name, "weapon-shooting-speed-7"}) do
    local technology = force.technologies[name]
    insist(technology and technology.enabled, "missing enabled continuation " .. name)
    local found = false
    for _, ingredient in pairs(technology.prototype.research_unit_ingredients) do
      if ingredient.name == science and ingredient.amount > 0 then found = true end
    end
    insist(found, "ordinary base continuation lost space science " .. name)
    insist(reaches(technology, "rocket-silo"), "continuation lost launch prerequisites " .. name)
  end
end

local function emit(stage, state)
  local force = game.forces.player
  local inventory = state.pad.get_inventory(defines.inventory.cargo_landing_pad_main)
  local row = {stage = stage, tick = game.tick, mir = script.active_mods["more-infinite-research"],
    base = script.active_mods.base, phase = state.phase, crafts = state.crafts or 0,
    rockets_launched = force.rockets_launched, return_count = state.return_count or 0,
    pad_count = inventory.get_item_count(science), lab_transfer = state.lab_transfer or 0,
    technology = force.current_research and force.current_research.name or "",
    progress = force.research_progress, saved_progress = state.saved_progress or 0,
    feed_remaining = state.feed_remaining, consumed = state.consumed or {},
    launch_ordered = state.launch_ordered == true}
  log(prefix .. "RESULT " .. helpers.table_to_json(row))
end

local function assert_complete(state)
  environment()
  local force = game.forces.player
  catalogue(force)
  insist(state.phase == "complete" and state.crafts == 100 and state.return_count == 1000,
    "saved production result differs")
  insist(force.rockets_launched == 1 and state.launch_ordered, "launch count differs")
  insist(force.current_research and force.current_research.name == technology_name,
    "current research differs")
  local queue = force.research_queue or {}
  insist(#queue == 1 and queue[1].name == technology_name, "research queue differs")
  insist(state.saved_progress > 0 and state.saved_progress < 1
    and math.abs(force.research_progress - state.saved_progress) < 0.000000001,
    "earned research progress differs")
  insist(state.pad.get_inventory(defines.inventory.cargo_landing_pad_main).get_item_count(science)
    == 1000 - state.lab_transfer, "remaining returned science differs")
  insist(state.lab.get_inventory(defines.inventory.lab_input).get_item_count(science) == 0,
    "lab did not consume its returned science")
  local input = state.silo.get_inventory(defines.inventory.crafter_input)
  for _, name in ipairs({"processing-unit", "low-density-structure", "rocket-fuel"}) do
    insist(state.feed_remaining[name] == 0 and state.consumed[name] == 1000
      and input.get_item_count(name) == 0, "construction consumption differs " .. name)
  end
end

script.on_init(function()
  environment()
  local force = game.forces.player
  catalogue(force)
  insist(force.rockets_launched == 0 and not force.current_research, "fresh force required")
  -- Explicit factory setup, not a claim of a complete early-game playthrough.
  force.technologies["rocket-silo"].research_recursive()
  local technology = force.technologies[technology_name]
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  for _, name in ipairs({"rocket-silo", "rocket-part", "satellite", "cargo-landing-pad"}) do
    insist(force.recipes[name] and force.recipes[name].enabled, "setup did not unlock " .. name)
  end
  local recipe = force.recipes["rocket-part"]
  insist(recipe.productivity_bonus == 0, "unexpected construction productivity")
  local expected = {["processing-unit"] = 10, ["low-density-structure"] = 10, ["rocket-fuel"] = 10}
  insist(#recipe.ingredients == 3, "construction ingredient count differs")
  for _, ingredient in ipairs(recipe.ingredients) do
    insist(ingredient.type == "item" and expected[ingredient.name] == ingredient.amount,
      "construction ingredient differs")
  end
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0, 0}, 1)
  surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities_filtered{area = {{-18, -8}, {18, 8}}}) do
    entity.destroy()
  end
  local tiles = {}
  for x = -18, 18 do
    for y = -8, 8 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end
  end
  surface.set_tiles(tiles)
  local state = {phase = "constructing", started_tick = game.tick,
    feed_remaining = {["processing-unit"] = 1000, ["low-density-structure"] = 1000, ["rocket-fuel"] = 1000}}
  state.silo = surface.create_entity{name = "rocket-silo", position = {-8, 0}, force = force}
  state.pad = surface.create_entity{name = "cargo-landing-pad", position = {6, 0}, force = force}
  state.lab = surface.create_entity{name = "lab", position = {12, 0}, force = force}
  insist(state.silo and state.pad and state.lab, "factory entities missing")
  insist(state.silo.prototype.rocket_parts_required == 100, "construction craft count differs")
  insist(state.silo.get_recipe().name == "rocket-part", "fixed recipe differs")
  insist(state.pad.get_inventory(defines.inventory.cargo_landing_pad_main).is_empty(), "receiver not empty")
  insist(state.lab.get_inventory(defines.inventory.lab_input).is_empty(), "lab not empty")
  storage[key] = state
  game.speed = 10 -- Tick acceleration only; no performance claim.
  emit("create", state)
end)

script.on_load(function()
  loaded_phase = storage[key] and storage[key].phase
  terminal_reported = false
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage[key]
  insist(state and state.silo.valid and state.pad.valid and state.lab.valid, "saved factory missing")
  if state.phase == "complete" then
    if loaded_phase == "complete" and not terminal_reported then
      assert_complete(state)
      emit("reload", state)
      terminal_reported = true
    end
    return
  end
  insist(event.tick - state.started_tick < 60000, "bounded production deadline exceeded")
  state.silo.energy = 100000000
  state.lab.energy = 100000000
  local input = state.silo.get_inventory(defines.inventory.crafter_input)
  if state.phase == "constructing" then
    for name, remaining in pairs(state.feed_remaining) do
      if remaining > 0 then
        state.feed_remaining[name] = remaining - input.insert{name = name, count = remaining}
      end
    end
    if state.silo.rocket_silo_status == defines.rocket_silo_status.rocket_ready then
      insist(state.silo.rocket_parts == 100, "rocket became ready without exactly 100 parts")
      state.crafts = state.silo.rocket_parts
      state.consumed = {}
      for name, remaining in pairs(state.feed_remaining) do
        insist(remaining == 0 and input.get_item_count(name) == 0, "rocket construction did not consume exact input")
        state.consumed[name] = 1000
      end
      local payload = state.silo.get_inventory(defines.inventory.rocket_silo_rocket)
      insist(payload and payload.insert{name = "satellite", count = 1} == 1, "satellite insertion failed")
      insist(state.silo.launch_rocket(), "native launch refused")
      state.launch_ordered = true
      state.phase = "returning"
    end
  elseif state.phase == "returning" then
    local returned = state.pad.get_inventory(defines.inventory.cargo_landing_pad_main)
    local count = returned.get_item_count(science)
    if count > 0 then
      insist(count == 1000 and game.forces.player.rockets_launched == 1, "satellite return differs")
      state.return_count = count
      local force = game.forces.player
      local technology = force.technologies[technology_name]
      force.research_queue_enabled = true
      insist(force.add_research(technology), "continuation cannot be researched")
      force.research_queue = {technology}
      insist(force.research_progress == 0, "new continuation has unexpected progress")
      local lab_input = state.lab.get_inventory(defines.inventory.lab_input)
      for _, ingredient in pairs(technology.prototype.research_unit_ingredients) do
        insist(ingredient.amount > 0, "nonpositive research ingredient")
        if ingredient.name == science then
          insist(returned.remove{name = science, count = ingredient.amount} == ingredient.amount,
            "returned science transfer failed")
          state.lab_transfer = ingredient.amount
        end
        insist(lab_input.insert{name = ingredient.name, count = ingredient.amount} == ingredient.amount,
          "lab ingredient insertion failed")
      end
      insist(state.lab_transfer and state.lab_transfer < 1000, "lab science transfer differs")
      state.phase = "researching"
    end
  elseif state.phase == "researching" then
    local force = game.forces.player
    if force.research_progress > 0 and state.lab.status == defines.entity_status.missing_science_packs then
      state.saved_progress = force.research_progress
      state.phase = "complete"
      game.speed = 1
      assert_complete(state)
      emit("production", state)
      game.server_save("mir-a04-launch-complete")
    end
  else
    error(prefix .. "unknown fixture phase")
  end
end)
