-- Host controls for the actual native fixture, not a replacement for Factorio.
-- The caller supplies the exact control.lua bytes in MIR_LAUNCH_CONTROL_SOURCE.
local checks = 0
local function check(value, label)
  assert(value, label)
  checks = checks + 1
end
local function clone(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = clone(v) end
  return result
end
local function inventory()
  local items = {}
  return {items = items,
    insert = function(stack)
      local added = math.min(stack.count, 100 - (items[stack.name] or 0))
      items[stack.name] = (items[stack.name] or 0) + added
      return added
    end,
    remove = function(stack)
      local removed = math.min(stack.count, items[stack.name] or 0)
      items[stack.name] = (items[stack.name] or 0) - removed
      return removed
    end,
    get_item_count = function(name) return items[name] or 0 end,
    is_empty = function() for _, n in pairs(items) do if n ~= 0 then return false end end return true end}
end
local function world(line)
  local env = setmetatable({}, {__index = _G})
  local callbacks, records, saves, entities = {}, {}, {}, {}
  env.storage = {}
  env.defines = {inventory = {crafter_input = 1, cargo_landing_pad_main = 2, lab_input = 3, rocket_silo_rocket = 4},
    events = {on_tick = 1}, rocket_silo_status = {rocket_ready = 1}, entity_status = {missing_science_packs = 1}}
  env.script = {active_mods = {base = line .. ".77", ["more-infinite-research"] = line == "2.0" and "4.2.20002" or "4.2.21002"},
    on_init = function(f) callbacks.init = f end,
    on_load = function(f) callbacks.load = f end,
    on_event = function(_, f) callbacks.tick = f end}
  env.helpers = {table_to_json = function(row) records[row.stage] = clone(row); return row.stage end}
  env.log = function() end
  local force = {rockets_launched = 0, research_progress = 0, technologies = {}, recipes = {}}
  for _, name in ipairs({"rocket-silo", "rocket-part", "satellite", "cargo-landing-pad"}) do force.recipes[name] = {enabled = true} end
  force.recipes["rocket-part"].productivity_bonus = 0
  force.recipes["rocket-part"].ingredients = {}
  for _, name in ipairs({"processing-unit", "low-density-structure", "rocket-fuel"}) do
    table.insert(force.recipes["rocket-part"].ingredients, {type = "item", name = name, amount = 10})
  end
  local root = {name = "rocket-silo", prerequisites = {}, research_recursive = function() end}
  force.technologies["rocket-silo"] = root
  for _, name in ipairs({"research-speed-7", "weapon-shooting-speed-7"}) do
    force.technologies[name] = {name = name, enabled = true, prerequisites = {root},
      prototype = {research_unit_ingredients = {{name = "automation-science-pack", amount = 1}, {name = "space-science-pack", amount = 1}}}}
  end
  force.add_research = function(technology) force.current_research = technology; return true end
  local surface = {request_to_generate_chunks = function() end, force_generate_chunk_requests = function() end,
    find_entities_filtered = function() return {} end, set_tiles = function() end}
  surface.create_entity = function(spec)
    local inv = inventory()
    local e = {valid = true, prototype = {rocket_parts_required = 100}, rocket_parts = 0, rocket_silo_status = 0, inv = inv,
      get_inventory = function() return inv end, get_recipe = function() return {name = "rocket-part"} end}
    if spec.name == "rocket-silo" then
      local payload = inventory()
      e.get_inventory = function(id) return id == 4 and payload or inv end
      e.launch_rocket = function()
        check(payload.get_item_count("satellite") == 1, "one satellite supplied")
        force.rockets_launched = 1
        entities["cargo-landing-pad"].inv.items["space-science-pack"] = 1000
        return true
      end
    end
    entities[spec.name] = e
    return e
  end
  env.game = {tick = 0, forces = {player = force}, surfaces = {surface}, server_save = function(name) saves[#saves + 1] = name end}
  assert(load(MIR_LAUNCH_CONTROL_SOURCE, "native-launch-fixture", "t", env))()
  return env, callbacks, records, saves, entities, force
end

for _, line in ipairs({"2.0", "2.1"}) do
  local env, cb, records, saves, entities, force = world(line)
  cb.init()
  check(records.create.pad_count == 0 and #saves == 0, "initial setup invents no returned science or save")
  cb.load()
  for tick = 1, 110 do
    env.game.tick = tick
    cb.tick{tick = tick}
    local state = env.storage.mir_a04_launch
    if state.phase == "constructing" then
      local silo = entities["rocket-silo"]
      for _, name in ipairs({"processing-unit", "low-density-structure", "rocket-fuel"}) do
        assert(silo.inv.remove{name = name, count = 10} == 10, "fixture supplies bounded construction inputs")
      end
      silo.rocket_parts = silo.rocket_parts + 1 -- Simulated engine, outside the fixture.
      if silo.rocket_parts == 100 then silo.rocket_silo_status = 1 end
    elseif state.phase == "researching" then
      local lab = entities.lab
      check(lab.inv.remove{name = "space-science-pack", count = 1} == 1, "lab receives transferred return")
      force.research_progress = 0.001 -- Simulated engine, outside the fixture.
      lab.status = 1
    end
  end
  check(#saves == 1 and saves[1] == "mir-a04-launch-complete", "one completed save request")
  check(records.production.return_count == 1000 and records.production.pad_count == 999,
    "production observation reports actual inventories")
  check(records.reload == nil, "production process cannot pretend to reload itself")
  cb.load()
  cb.tick{tick = 111}
  check(records.reload.progress == 0.001 and #saves == 1, "reload observes progress without resaving")
  for _, mutation in ipairs({
    function() force.research_progress = 0.002 end,
    function() force.rockets_launched = 2 end,
    function() force.research_queue = {} end,
    function() entities["cargo-landing-pad"].inv.items["space-science-pack"] = 998 end,
    function() env.storage.mir_a04_launch.consumed["rocket-fuel"] = 999 end
  }) do
    local old_progress, old_rockets, old_queue = force.research_progress, force.rockets_launched, force.research_queue
    local state = env.storage.mir_a04_launch
    mutation(); cb.load()
    check(not pcall(cb.tick, {tick = 112}), "corrupted saved fact is rejected")
    force.research_progress, force.rockets_launched, force.research_queue = old_progress, old_rockets, old_queue
    entities["cargo-landing-pad"].inv.items["space-science-pack"] = 999
    state.consumed["rocket-fuel"] = 1000
  end
  for _, mutation in ipairs({
    function(e, f) e.script.active_mods["space-age"] = "2.0.77" end,
    function(e, f) e.script.active_mods["more-infinite-research"] = "4.2.21001" end,
    function(e, f) f.technologies["research-speed-7"].prototype.research_unit_ingredients = {{name = "automation-science-pack", amount = 1}} end,
    function(e, f) f.technologies["weapon-shooting-speed-7"].prerequisites = {} end,
    function(e, f) f.recipes["rocket-part"].productivity_bonus = 0.1 end
  }) do
    local e, c, _, _, _, f = world(line)
    mutation(e, f)
    check(not pcall(c.init), "wrong environment or oracle is rejected")
  end
end
print("MIR-MODERN-LAUNCH-CONTROLS-PASS " .. checks)
