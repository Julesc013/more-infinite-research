-- Scenario (__level__) observer. This file is never installed as a mod control.
-- Only worker4/5 and the new MIR6 laboratory completions are ordinary evidence.
local KEY = "mir_ferrum_worker_native"
local LAB = "mir-fixture-ferrum-worker-storage-native-lab"
local FOUR, FIVE, SIX = "worker-robots-storage-4", "worker-robots-storage-5", "worker-robots-storage-6"
local PRIVATE, SEVEN = "mir-worker-storage-preservation-4", "worker-robots-storage-7"
local SENTINEL, DETACHED = "mir-ferrum-sentinel", "mir-ferrum-detached"
local CALIBRATION = "mir-ferrum-count-control-6"
local NATIVE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack"}
local SOURCE_SCIENCE = {table.unpack(NATIVE)}
SOURCE_SCIENCE[#SOURCE_SCIENCE + 1] = "ferrum-robotics-science-pack"
local MIR_SCIENCE = {table.unpack(SOURCE_SCIENCE)}
MIR_SCIENCE[#MIR_SCIENCE + 1] = "electromagnetic-science-pack"
local PRIVATE_SCIENCE = {table.unpack(NATIVE)}
PRIVATE_SCIENCE[#PRIVATE_SCIENCE + 1] = "electromagnetic-science-pack"
local ROWS = {"worker-robots-storage-1", "worker-robots-storage-2", "worker-robots-storage-3",
  FOUR, FIVE, SIX, PRIVATE, SEVEN, SENTINEL, DETACHED, CALIBRATION}
local loaded, administrative = false, false

local function check(ok, message)
  if not ok then error("[mir-ferrum-worker-native] " .. message, 2) end
end
local function same(a, b, path)
  path = path or "$"
  check(type(a) == type(b), "frame type " .. path)
  if type(a) == "table" then
    for k, v in pairs(a) do same(v, b[k], path .. "/" .. tostring(k)) end
    for k in pairs(b) do check(a[k] ~= nil, "frame extra " .. path .. "/" .. tostring(k)) end
  elseif type(a) == "number" then
    check(math.abs(a - b) < 1e-9, "frame number " .. path)
  else check(a == b, "frame value " .. path) end
end
local function names(values)
  local result = {}
  for _, value in pairs(values) do result[#result + 1] = value.name end
  table.sort(result)
  return result
end
local function sorted(values)
  local result = {table.unpack(values)}
  table.sort(result)
  return result
end
local function copied(value)
  if type(value) ~= "table" then return value end
  local result = {}; for k, v in pairs(value) do result[k] = copied(v) end
  return result
end
local function target()
  local base = script.active_mods.base
  check(base == "2.1.23" or base == "2.0.77", "exact engine tuple")
  return base == "2.1.23" and "5.0.21012" or "5.0.20012"
end
local function closure(with_mir)
  local version = target()
  local modern = script.active_mods.base == "2.1.23"
  local expected = {base = script.active_mods.base, ["space-age"] = script.active_mods.base,
    quality = script.active_mods.base, ["elevated-rails"] = script.active_mods.base,
    PlanetsLib = modern and "2.4.0" or "1.18.0", ["spider-launcher"] = modern and "2.9.87" or "2.9.86",
    ["planet-ferrum"] = modern and "0.1.5" or "0.0.5", [LAB] = "0.1.0",
    ["mir-fixture-mir5-active-mods-observer"] = "0.1.0"}
  if modern then expected.recycler = "2.1.23" end
  if with_mir then expected["more-infinite-research"] = version end
  same(script.active_mods, expected, "active-mods")
  check(game.difficulty_settings.technology_price_multiplier == 1, "map price must remain1")
end
local function facts(t)
  if not t then return false end
  return {level = t.level, researched = t.researched, enabled = t.enabled,
    visible = t.visible_when_disabled, saved = t.saved_progress, count = t.research_unit_count,
    first = t.prototype.level, maximum = t.prototype.max_level, hidden = t.prototype.hidden,
    formula = t.prototype.research_unit_count_formula or false, time = t.prototype.research_unit_energy,
    effects = copied(t.prototype.effects), science = copied(t.prototype.research_unit_ingredients),
    prerequisites = names(t.prerequisites), creator = prototypes.get_history("technology", t.name).created}
end
local function frame(force)
  local rows, queue = {}, {}
  for _, id in ipairs(ROWS) do rows[id] = facts(force.technologies[id]) end
  for _, t in ipairs(force.research_queue or {}) do queue[#queue + 1] = t.name end
  return {index = force.index, bonus = force.worker_robots_storage_bonus,
    lab_bonus = force.laboratory_speed_modifier, current = force.current_research and force.current_research.name or false,
    progress = force.research_progress, queue = queue, rows = rows}
end
local function frames()
  local result, count = {}, 0
  for name, force in pairs(game.forces) do result[name] = frame(force); count = count + 1 end
  check(count <= 16, "bounded force count")
  return result
end
local function marker(stage, physical_frame)
  local s = storage[KEY]
  log("[MIR_FERRUM_WORKER_NATIVE] " .. helpers.table_to_json({stage = stage, phase = s.phase,
    tick = game.tick, mods = script.active_mods, frames = frames(), ordinary = s.ordinary,
    administrative_events = s.administrative_events, consumption = s.consumption,
    calibration_count = s.calibration_count or false, partials_are_scripted_sentinels = true,
    cargo = s.cargo and s.cargo.report or nil, physical_frame = physical_frame}))
end
local function science(t, expected)
  local actual, ids = {}, {}
  for _, ingredient in ipairs(t.prototype.research_unit_ingredients) do
    check(ingredient.amount == 1 and not actual[ingredient.name], "science amount/duplicate")
    actual[ingredient.name] = true
    ids[#ids + 1] = ingredient.name
  end
  same(sorted(ids), sorted(expected), "science")
end
local function effect(t)
  local effects = t.prototype.effects
  check(#effects == 1 and effects[1].type == "worker-robot-storage" and effects[1].modifier == 1,
    "worker effect vector")
  --2.0.77 has no hidden member; preserve that native absence in snapshots.
  if script.active_mods.base == "2.1.23" then check(effects[1].hidden == false, "2.1 effect hidden")
  else check(effects[1].hidden == nil or effects[1].hidden == false, "2.0 effect hidden") end
end
local function contracts(with_mir, initial)
  -- Raw unit.time is60 seconds; the runtime energy getter reports3600 ticks.
  local f = game.forces.player
  for _, row in ipairs({{FOUR, 4, 675, {"worker-robots-storage-3", "ferrum-robotics-science-pack"}},
      {FIVE, 5, 1012, {FOUR}}}) do
    local t = f.technologies[row[1]]
    check(t and t.prototype.level == row[2] and t.prototype.max_level == row[2]
      and t.research_unit_count == row[3] and t.prototype.research_unit_energy == 60 * 60
      and not t.prototype.research_unit_count_formula, "finite worker contract")
    check(prototypes.get_history("technology", t.name).created == "planet-ferrum", "finite creator")
    science(t, SOURCE_SCIENCE); effect(t); same(names(t.prerequisites), sorted(row[4]), "finite prerequisites")
  end
  local c = f.technologies[CALIBRATION]
  check(c and c.prototype.research_unit_count_formula == "1518.75" and c.prototype.hidden
    and c.prototype.level == 6 and c.prototype.max_level == 6 and c.prototype.research_unit_energy == 60 * 60
    and #c.prototype.effects == 0 and not c.enabled and not c.researched and c.saved_progress == 0
    and prototypes.get_history("technology", CALIBRATION).created == LAB,
    "calibration must stay literal/uninvested")
  science(c, {NATIVE[1]}); same(names(c.prerequisites), {}, "calibration prerequisites")
  check(type(c.research_unit_count) == "number" and c.research_unit_count > 0
    and c.research_unit_count == math.floor(c.research_unit_count), "native calibration integer")
  local accepted = {}; for _, name in ipairs(storage[KEY].lab.prototype.lab_inputs) do
    check(not accepted[name], "duplicate lab input"); accepted[name] = true
  end
  for _, name in ipairs(MIR_SCIENCE) do check(accepted[name], "actual Ferrum lab science missing") end
  check(not f.technologies[SEVEN], "unexpected public7 overlap")
  if not with_mir then check(not f.technologies[SIX] and not f.technologies[PRIVATE], "NoMIR rows present"); return end
  for _, row in ipairs({{SIX, 6, "1518.75*1.5^(L-6)", MIR_SCIENCE,
      {FOUR, FIVE, table.unpack(PRIVATE_SCIENCE)}},
      {PRIVATE, 4, "675*1.5^(L-4)", PRIVATE_SCIENCE,
      {"worker-robots-storage-2", "worker-robots-storage-3", table.unpack(PRIVATE_SCIENCE)}}}) do
    local t = f.technologies[row[1]]
    check(t and t.prototype.level == row[2] and t.prototype.max_level == 4294967295
      and t.prototype.research_unit_count_formula == row[3] and t.prototype.research_unit_energy == 60 * 60,
      "MIR formula/level/time contract")
    check(prototypes.get_history("technology", t.name).created == "more-infinite-research", "MIR creator")
    science(t, row[4]); effect(t); same(names(t.prerequisites), sorted(row[5]), "MIR prerequisites")
  end
  local p, n = f.technologies[PRIVATE], f.technologies[SIX]
  check(n.prototype.hidden == false, "public6 must not be hidden")
  check(p.prototype.hidden and not p.enabled and not p.researched and p.level == 4 and p.saved_progress == 0
    and p.visible_when_disabled == false and p.research_unit_count == 675, "private holder must stay full/uninvested")
  if initial then check(n.level == 6 and not n.researched and n.enabled and n.saved_progress == 0
    and n.research_unit_count == c.research_unit_count, "MIR6 native calibrated count/state") end
  for _, force in pairs(game.forces) do
    local private = force.technologies[PRIVATE]
    check(private.level == 4 and not private.researched and not private.enabled and private.saved_progress == 0
      and private.visible_when_disabled == false,
      "all-force private investment/flags")
    if initial then
      local public = force.technologies[SIX]
      check(public.level == 6 and not public.researched and public.enabled and public.visible_when_disabled == false
        and public.saved_progress == 0
        and public.research_unit_count == c.research_unit_count, "all-force new public work")
    end
  end
end
local function queue(force, ids)
  local values = {}; for _, id in ipairs(ids) do values[#values + 1] = force.technologies[id] end
  force.research_queue = values
  local actual = {}; for _, t in ipairs(force.research_queue) do actual[#actual + 1] = t.name end
  same(actual, ids, "ordered queue")
end
local function stopped()
  local lab = storage[KEY].lab
  check(lab.valid and lab.disabled_by_script == true, "lab must remain stopped")
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  for _, name in ipairs(lab.prototype.lab_inputs) do check(inventory.get_item_count(name) == 0, "stopped lab inventory changed") end
end
local function source_frame(actual)
  local source = storage[KEY].source
  for name, previous in pairs(source) do
    check(actual[name] ~= nil, "source force lost")
    local value = actual[name]
    value.rows[SIX], value.rows[PRIVATE] = false, false -- Snapshot copies only.
    same(value, previous, "source/" .. name)
  end
  for name in pairs(actual) do check(source[name] ~= nil, "unexpected force") end
end
local function feed()
  local s, f = storage[KEY], game.forces.player
  check(f.current_research and f.current_research.name == s.work.id, "native current research differs")
  if f.research_progress > 0 and f.research_progress < 1 then s.work.progress_seen = true end
  local inventory = s.lab.get_inventory(defines.inventory.lab_input)
  for name, budget in pairs(s.work.budgets) do
    local left = budget - s.work.inserted[name]
    if left > 0 then
      local added = inventory.insert{name = name, count = left, quality = "normal"}
      check(added >= 0 and added <= left and added == math.floor(added), "science insertion count")
      s.work.inserted[name] = s.work.inserted[name] + added
    end
  end
  s.lab.disabled_by_script = false
end
local function begin(id)
  local s, f = storage[KEY], game.forces.player
  stopped(); queue(f, {id}); check(f.research_progress == 0, "new lab work must start empty")
  local t, budgets, inserted = f.technologies[id], {}, {}
  for _, item in ipairs(t.research_unit_ingredients) do budgets[item.name] = t.research_unit_count * item.amount; inserted[item.name] = 0 end
  s.work = {id = id, units = t.research_unit_count, budgets = budgets, inserted = inserted, progress_seen = false}
  s.phase = "earning"; marker("lab-start"); feed()
end
local function close(phase, save, physical_frame)
  local s = storage[KEY]; stopped(); s.phase = phase; s.closed = frames(); marker(phase, physical_frame); game.server_save(save)
end
local function cargo_inventory(entity, index, item)
  check(entity and entity.valid and entity.quality.name == "normal", "normal cargo entity absent")
  local inventory = entity.get_inventory(index)
  check(inventory ~= nil, "cargo inventory absent")
  local count = inventory.get_item_count{name = item, quality = "normal"}
  check(inventory.get_item_count() == count, "unexpected cargo item/quality")
  return count
end
local function cargo_frame()
  local c = storage[KEY].cargo
  check(c.port.name == "roboport" and c.provider.name == "passive-provider-chest"
    and c.requester.name == "requester-chest" and c.port.force.name == "player"
    and c.provider.force.name == "player" and c.requester.force.name == "player", "cargo fixture identity changed")
  local provider = cargo_inventory(c.provider, defines.inventory.chest, "iron-plate")
  local requester = cargo_inventory(c.requester, defines.inventory.chest, "iron-plate")
  local docked = cargo_inventory(c.port, defines.inventory.roboport_robot, "logistic-robot")
  local slot = c.section.get_slot(1)
  check(c.section.active and slot.min == 7 and slot.max == 7 and slot.value.name == "iron-plate"
    and slot.value.type == "item" and slot.value.quality == "normal" and slot.value.comparator == "=",
    "cargo request changed")
  local network = c.port.logistic_network
  local result = {provider = provider, requester = requester, docked = docked,
    port = c.port.unit_number, provider_id = c.provider.unit_number, requester_id = c.requester.unit_number,
    positions = {port = copied(c.port.position), provider = copied(c.provider.position), requester = copied(c.requester.position)},
    active = {}, network_ready = network ~= nil}
  if not network then return result end
  check(#network.cells == 1 and network.all_logistic_robots == 1 and network.all_construction_robots == 0,
    "cargo requires exactly one normal logistics robot/network")
  result.available = network.available_logistic_robots
  local carried = 0
  for _, robot in pairs(network.logistic_robots) do
    check(#result.active == 0 and robot.name == "logistic-robot" and robot.type == "logistic-robot"
      and robot.prototype.max_payload_size == 1 and robot.force.name == "player"
      and type(robot.unit_number) == "number", "cargo robot identity/base payload")
    local count = cargo_inventory(robot, defines.inventory.robot_cargo, "iron-plate")
    check(count == 0 or count == 7, "cargo must be one full seven-item load")
    carried = carried + count
    result.active[#result.active + 1] = {unit = robot.unit_number, count = count,
      position = {x = robot.position.x, y = robot.position.y}, quality = robot.quality.name}
  end
  check(docked + #result.active == 1, "cargo robot conservation")
  check(provider + requester + carried == 7, "cargo iron conservation")
  return result
end
local function cargo_tick()
  local s = storage[KEY]; local c = s.cargo
  stopped(); same(frames(), s.closed, "cargo-native")
  check(game.tick <= c.deadline, "cargo flight/delivery timeout")
  local current = cargo_frame()
  if not current.network_ready then return end
  local robot = current.active[1]
  if robot and robot.count == 7 then
    check(current.provider == 0 and current.requester == 0, "loaded-flight source/destination")
    if not c.report.loaded then
      c.report.loaded = {tick = game.tick, frame = copied(current)}
      marker("cargo-loaded-seven", current)
    else
      local first = c.report.loaded.frame.active[1]
      check(first.unit == robot.unit, "cargo robot changed during flight")
      if first.position.x ~= robot.position.x or first.position.y ~= robot.position.y then
        if not c.report.flight then
          c.report.flight = {tick = game.tick, frame = copied(current)}
          marker("cargo-seven-in-flight", current)
        end
      end
    end
  end
  if current.requester == 7 then
    check(c.report.flight ~= nil and current.provider == 0, "delivery lacks observed seven-item flight")
    if current.docked == 1 and #current.active == 0 and current.available == 1 then
      c.closed = current; c.completed = true
      c.report.delivered = {tick = game.tick, frame = copied(current)}
      c.report.physical_robot_delivery = true
      close("cargo-destination-saved", "mir-ferrum-worker-cargo-destination", current)
    end
  end
end
commands.add_command("mir-ferrum-worker-cargo", "Test fixture only: start the physical cargo witness.", function(command)
  check(command.player_index == nil and command.parameter == "start", "cargo requires exact server-console command")
  local s, f = storage[KEY], game.forces.player
  check(s and s.phase == "destination-saved" and not s.cargo, "cargo requires fresh ordinary destination endpoint")
  check(script.active_mods.base == "2.1.23" and target() == "5.0.21012", "cargo exact F210 tuple")
  closure(true); stopped(); contracts(true, false); same(frames(), s.closed, "cargo-entry")
  same(s.ordinary, {[FOUR] = 1, [FIVE] = 1, [SIX] = 1}, "cargo ordinary counts")
  check(f.worker_robots_storage_bonus == 6 and prototypes.entity["logistic-robot"].max_payload_size == 1,
    "cargo earned payload must be native1 plus earned6")
  local surface = s.lab.surface
  check(#surface.find_entities_filtered{area = {{-16, 8}, {16, 16}},
    type = {"roboport", "logistic-container", "logistic-robot", "construction-robot"}} == 0,
    "cargo setup area already has logistics entities")
  local tiles = {}; for x = -16, 16 do for y = 8, 16 do
    tiles[#tiles + 1] = {name = "grass-1", position = {x, y}}
  end end
  surface.set_tiles(tiles)
  local function place(name, position)
    local entity = surface.create_entity{name = name, position = position, force = f, quality = "normal"}
    check(entity and entity.valid and entity.name == name and entity.quality.name == "normal", "cargo placement failed")
    return entity
  end
  local port = place("roboport", {0, 12})
  local provider = place("passive-provider-chest", {-12, 12})
  local requester = place("requester-chest", {12, 12})
  check(port.electric_buffer_size >= 40000000, "normal roboport power buffer unavailable")
  port.energy = port.electric_buffer_size -- Labelled one-time administrative power supply only.
  check(port.get_inventory(defines.inventory.roboport_robot).insert{name = "logistic-robot", count = 1, quality = "normal"} == 1,
    "cargo robot setup insertion")
  check(provider.get_inventory(defines.inventory.chest).insert{name = "iron-plate", count = 7, quality = "normal"} == 7,
    "cargo provider setup insertion")
  check(cargo_inventory(requester, defines.inventory.chest, "iron-plate") == 0, "requester must start empty")
  local point = requester.get_logistic_point(defines.logistic_member_index.logistic_container)
  check(point and point.sections_count <= 1, "cargo requester point absent/nonempty")
  local section = point.sections_count == 0 and point.add_section() or point.get_section(1)
  check(section and section.is_manual, "cargo manual requester section absent")
  section.active = true
  section.set_slot(1, {value = {type = "item", name = "iron-plate", quality = "normal", comparator = "="}, min = 7, max = 7})
  s.cargo = {port = port, provider = provider, requester = requester, section = section,
    deadline = game.tick + 7200, report = {physical_robot_delivery = false,
      administrative_setup = {robot_items = 1, provider_iron = 7, requester_iron = 0,
        normal_quality = true, one_time_port_energy = port.energy}, start_tick = game.tick}}
  s.phase = "cargo-active"; marker("cargo-administrative-setup-only")
end)
script.on_init(function()
  game.difficulty_settings.technology_price_multiplier = 1
  closure(false)
  storage[KEY] = {phase = "source-init", ordinary = {}, administrative_events = {}, consumption = {}}
  local s = storage[KEY]
  game.surfaces.nauvis.set_tiles({{name = "grass-1", position = {0, 0}}})
  s.lab = game.surfaces.nauvis.create_entity{name = "mir-ferrum-lab", position = {0, 0}, force = game.forces.player}
  check(s.lab and s.lab.valid, "fixture lab absent"); s.lab.disabled_by_script = true
  game.speed = 16
end)
script.on_load(function() loaded = true end) -- Local reconnect only, no game/storage access.
script.on_configuration_changed(function(event)
  loaded = false
  local s = storage[KEY]
  check(s and s.phase == "source-saved", "configuration requires closed source")
  s.entry = frames(); marker("level-pre-MIR-configuration") -- __level__ runs before MIR.
  closure(true)
  local change = event.mod_changes["more-infinite-research"]
  check(change and change.old_version == nil and change.new_version == target(), "first exact MIR12 addition")
  for name, value in pairs(event.mod_changes) do
    check(name == "more-infinite-research" or value.old_version == value.new_version, "other selection changed")
  end
  source_frame(frames()); stopped(); contracts(true, true)
  s.calibration_count = game.forces.player.technologies[CALIBRATION].research_unit_count
  s.phase = "destination-entry"
end)
script.on_event(defines.events.on_research_finished, function(event)
  local s = storage[KEY]
  local id = event.research.name
  check(id ~= CALIBRATION, "calibration must never be researched")
  if administrative then
    check(id ~= FOUR and id ~= FIVE and id ~= SIX and event.by_script == true, "scripted worker completion")
    check(#s.administrative_events < 512, "bounded administrative events")
    s.administrative_events[#s.administrative_events + 1] = id; return
  end
  check(s.phase == "earning" and event.research.force == game.forces.player
    and id == s.work.id, "unexpected/duplicate completion")
  check(event.by_script == false, "completion requires ordinary lab")
  check(s.work.progress_seen, "ordinary progress was not observed")
  local inventory = s.lab.get_inventory(defines.inventory.lab_input)
  for name, budget in pairs(s.work.budgets) do
    check(s.work.inserted[name] == budget and inventory.get_item_count(name) == 0, "science consumption differs")
  end
  s.lab.disabled_by_script = true
  s.ordinary[id] = (s.ordinary[id] or 0) + 1
  check(s.ordinary[id] == 1, "duplicate ordinary completion")
  s.consumption[#s.consumption + 1] = s.work
  s.finished = id; s.finished_tick = game.tick; s.phase = "completion-pending"; marker("ordinary-finished")
end)
script.on_event(defines.events.on_tick, function()
  local s, f = storage[KEY], game.forces.player
  check(s ~= nil, "scenario state absent")
  if loaded then
    loaded = false; check(s.phase == "destination-saved" or s.phase == "cargo-destination-saved", "cold requires closed destination")
    closure(true); stopped(); same(frames(), s.closed, "cold"); contracts(true, false)
    same(s.ordinary, {[FOUR] = 1, [FIVE] = 1, [SIX] = 1}, "cold ordinary counts")
    local physical_frame
    if s.phase == "cargo-destination-saved" then
      check(s.cargo and s.cargo.completed and s.cargo.report.physical_robot_delivery, "cold physical witness absent")
      physical_frame = cargo_frame()
      same(physical_frame, s.cargo.closed, "cold-cargo")
    end
    marker("cold", physical_frame); return
  end
  if s.phase == "cargo-active" then cargo_tick(); return end
  if s.phase == "source-init" then
    closure(false); contracts(false)
    check(not f.technologies[FOUR].researched and not f.technologies[FIVE].researched, "source already earned")
    administrative = true
    for _, t in pairs(f.technologies[FOUR].prerequisites) do t.research_recursive() end
    f.technologies["electromagnetic-science-pack"].research_recursive()
    administrative = false
    check(f.worker_robots_storage_bonus == 3 and not f.technologies[FOUR].researched
      and not f.technologies[FIVE].researched, "administrative source baseline")
    local foreign = game.create_force("mir-ferrum-foreign")
    queue(foreign, {SENTINEL, DETACHED}); foreign.research_progress = .42
    foreign.technologies[DETACHED].saved_progress = .27; foreign.technologies[FOUR].enabled = false
    s.foreign = frame(foreign); marker("administrative-setup-only"); begin(FOUR); return
  end
  if s.phase == "destination-entry" then
    closure(true); source_frame(frames()); same(frames(), s.entry, "post-MIR-config"); contracts(true, true)
    s.destination_baseline = frames(); marker("post-MIR-configuration"); begin(SIX); return
  end
  if s.phase == "earning" then feed(); return end
  if s.phase ~= "completion-pending" or game.tick <= s.finished_tick then return end
  stopped()
  if s.finished ~= SIX then same(frame(game.forces["mir-ferrum-foreign"]), s.foreign, "foreign") end
  if s.finished == FOUR then
    check(f.technologies[FOUR].researched and f.worker_robots_storage_bonus == 4, "finite4 earned endpoint")
    begin(FIVE)
  elseif s.finished == FIVE then
    check(f.technologies[FIVE].researched and f.worker_robots_storage_bonus == 5, "finite5 earned endpoint")
    queue(f, {SENTINEL, DETACHED}); f.technologies[DETACHED].saved_progress = .27; f.research_progress = .375
    s.source = frames(); close("source-saved", "mir-ferrum-worker-source")
  else
    check(s.finished == SIX and f.technologies[SIX].level + (f.technologies[SIX].researched and 1 or 0) == 7
      and f.worker_robots_storage_bonus == 6, "useful MIR6 earned endpoint")
    local old = s.source.player
    queue(f, old.queue)
    for _, id in ipairs({SENTINEL, DETACHED}) do f.technologies[id].saved_progress = old.rows[id].saved end
    f.research_progress = old.progress
    local current = frames(); current.player.bonus = old.bonus; source_frame(current)
    local settled = frames()
    for name, before in pairs(s.destination_baseline) do
      if name ~= "player" then same(settled[name], before, "destination-foreign/" .. name) end
    end
    same(settled.player.rows[PRIVATE], s.destination_baseline.player.rows[PRIVATE], "private uninvested frame")
    contracts(true, false); close("destination-saved", "mir-ferrum-worker-destination")
  end
end)
remote.add_interface("mir-ferrum-worker-storage-native", {report = function()
  local s = storage[KEY]
  return {phase = s and s.phase or false, frames = frames(), ordinary = s and s.ordinary or false,
    calibration_count = s and s.calibration_count or false,
    physical_robot_delivery = s and s.cargo and s.cargo.completed == true or false,
    cargo = s and s.cargo and copied(s.cargo.report) or nil}
end})
