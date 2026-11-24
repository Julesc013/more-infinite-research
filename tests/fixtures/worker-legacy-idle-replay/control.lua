local MIR = "more-infinite-research"
local SETTING = "ips-cost-base-research_gears"
local PUBLIC = "worker-robots-storage-4"
local OWNER = "mir-worker-storage-default-4"
local DEBIT = "mir-worker-storage-head-4"

local function record(name, value)
  value.mir = script.active_mods[MIR]
  value.tick = game.tick
  helpers.write_file(name .. ".json", helpers.table_to_json(value) .. "\n")
end

local function equal(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) == "number" then return math.abs(left - right) < 1e-7 end
  if type(left) ~= "table" then return left == right end
  for k, v in pairs(left) do if not equal(v, right[k]) then return false end end
  for k in pairs(right) do if left[k] == nil then return false end end
  return true
end

local function technology(force, name)
  local t = assert(force.technologies[name], name)
  return {level=t.level, researched=t.researched, saved=t.saved_progress, enabled=t.enabled,
    visible=t.visible_when_disabled}
end

local function queue(force)
  local out = {}
  for i, tech in ipairs(force.research_queue) do out[i] = tech.name end
  return out
end

local function unrelated()
  local force = game.forces["unrelated-research"]
  return {queue=queue(force), current=force.current_research.name, progress=force.research_progress,
    parked=technology(force, "logistics"), disabled=technology(force, "worker-robots-speed-4"),
    bonus=force.worker_robots_speed_modifier}
end

local function workers(candidate)
  local out = {}
  for name, force in pairs(game.forces) do
    local row = {public=technology(force, PUBLIC), bonus=force.worker_robots_storage_bonus,
      queue=queue(force)}
    if candidate then row.owner, row.debit = technology(force, OWNER), technology(force, DEBIT) end
    out[name] = row
  end
  return out
end

local function idle(row)
  assert(row.level == 4 and row.researched == false and row.saved == 0, "worker row already has work")
end

local function check_unrelated()
  assert(equal(storage.unrelated, unrelated()), "unrelated force changed")
end

script.on_init(function()
  assert(script.active_mods[MIR] == "4.7.21003" and settings.startup[SETTING].value == 8000,
    "exact source startup setting")
  for _, name in ipairs{"base","space-age","quality","elevated-rails","recycler"} do
    assert(script.active_mods[name] == "2.1.24", "unexpected official mod " .. name)
  end
  local foreign = game.create_force("unrelated-research")
  for _, name in ipairs{"steam-power","electronics","automation-science-pack"} do
    foreign.technologies[name].researched = true
  end
  for _, name in ipairs{"automation","logistics"} do foreign.technologies[name].enabled = true end
  foreign.research_queue = {"automation","logistics"}
  foreign.research_progress = .42
  foreign.technologies.logistics.saved_progress = .27
  foreign.technologies["worker-robots-speed-4"].enabled = false
  foreign.worker_robots_speed_modifier = .5
  storage.unrelated = unrelated()
  assert(equal(storage.unrelated.queue, {"automation","logistics"}) and
    equal(storage.unrelated.progress, .42) and equal(storage.unrelated.parked.saved, .27) and
    storage.unrelated.disabled.enabled == false and storage.unrelated.bonus == .5, "source foreign setup")
  storage.source = workers(false)
  for _, row in pairs(storage.source) do
    idle(row.public)
    for _, id in ipairs(row.queue) do assert(id ~= PUBLIC, "source queued worker cargo") end
  end
  storage.phase = "source"
end)

script.on_configuration_changed(function(event)
  assert(storage.phase == "source" and script.active_mods[MIR] == "5.0.21023", "successor configuration")
  local change = event.mod_changes[MIR]
  assert(change.old_version == "4.7.21003" and change.new_version == "5.0.21023" and
    event.mod_startup_settings_changed == true and settings.startup[SETTING].value == 8001,
    "configuration does not demonstrate the unrelated startup change")
  for name in pairs(event.mod_changes) do assert(name == MIR, "unexpected mod change " .. name) end
  storage.event = {startup_settings_changed=event.mod_startup_settings_changed, old=change.old_version,
    new=change.new_version, setting=settings.startup[SETTING].value}
  storage.phase = "check-upgrade"
end)

local function start_lab()
  check_unrelated()
  local current = workers(true)
  for name, original in pairs(storage.source) do
    local row = assert(current[name])
    idle(row.public)
    idle(row.owner)
    idle(row.debit)
    assert(row.bonus == original.bonus and equal(row.queue, original.queue), "worker transfer disturbed " .. name)
    assert(not row.public.enabled and row.owner.enabled == original.public.enabled and not row.debit.enabled,
      "worker ownership flags differ for " .. name)
  end
  record("upgrade", {event=storage.event, workers=current, unrelated=unrelated()})

  local player, surface = game.forces.player, game.surfaces[1]
  local owner = assert(player.technologies[OWNER])
  for _, prerequisite in pairs(owner.prerequisites) do prerequisite.researched = true end
  assert(owner.research_unit_count == 675, "unexpected ordinary cargo price")
  local science = {}
  for _, ingredient in ipairs(owner.research_unit_ingredients) do
    assert(ingredient.amount == 1)
    science[#science+1] = ingredient.name
  end
  assert(equal(science, {"automation-science-pack","logistic-science-pack","chemical-science-pack",
    "production-science-pack","utility-science-pack","electromagnetic-science-pack"}), "wrong native cargo science")
  local pos = assert(surface.find_non_colliding_position("lab", {0,0}, 64, .5))
  storage.lab = assert(surface.create_entity{name="lab", position=pos, force=player})
  storage.lab_minimum = player.laboratory_speed_modifier
  player.laboratory_speed_modifier = 3600
  storage.inserted, storage.science, storage.lab_bonus = {}, science, player.worker_robots_storage_bonus
  assert(player.add_research(OWNER), "could not queue ordinary cargo")
  game.speed = 12
  storage.phase = "lab"
end

script.on_event(defines.events.on_research_finished, function(event)
  if storage.phase ~= "lab" then return end
  assert(event.research.name == OWNER and event.research.force == game.forces.player, "unexpected research event")
  storage.phase = "lab-finished"
end)

script.on_event(defines.events.on_tick, function(event)
  if script.test_arg == "reload" then
    assert(storage.phase == "closed" and equal(storage.closed, workers(true)), "cold worker state changed")
    check_unrelated()
    assert(storage.lab.valid and storage.lab.disabled_by_script, "cold lab changed")
    record("cold", {workers=workers(true), unrelated=unrelated(), spent=storage.spent})
    script.finish_test(true)
  elseif storage.phase == "source" and event.tick == 1 then
    record("source-empty", {workers=storage.source, unrelated=storage.unrelated})
    game.server_save("predecessor-empty")
  elseif storage.phase == "source" and event.tick == 31 then
    local t = game.forces.player.technologies[PUBLIC]
    t.saved_progress = .27
    assert(equal(t.saved_progress, .27), "source paid-progress opponent")
    record("source-paid", {workers=workers(false), unrelated=unrelated()})
    game.server_save("predecessor-paid")
  elseif storage.phase == "check-upgrade" then
    start_lab()
  elseif storage.phase == "lab" then
    local lab = storage.lab
    lab.energy = 2000000
    local input = lab.get_inventory(defines.inventory.lab_input)
    for _, name in ipairs(storage.science) do
      if input.get_item_count(name) < 64 then
        local count = input.insert{name=name, count=200}
        assert(count > 0)
        storage.inserted[name] = (storage.inserted[name] or 0) + count
      end
    end
  elseif storage.phase == "lab-finished" then
    local player, lab = game.forces.player, storage.lab
    check_unrelated()
    lab.disabled_by_script = true
    player.laboratory_speed_modifier = storage.lab_minimum
    game.speed = 1
    local input = lab.get_inventory(defines.inventory.lab_input)
    storage.spent = {}
    for _, name in ipairs(storage.science) do
      storage.spent[name] = storage.inserted[name] - input.get_item_count(name)
      assert(storage.spent[name] == 675, "unexpected science consumption " .. name)
    end
    storage.closed = workers(true)
    local row = storage.closed.player
    assert(row.owner.level == 5 and not row.owner.researched and row.debit.level == 5 and
      row.bonus == storage.lab_bonus + 1 and #row.queue == 0, "ordinary cargo result differs")
    storage.phase = "closed"
    record("closed", {workers=storage.closed, unrelated=unrelated(), spent=storage.spent})
    game.server_save("successor")
  end
end)
