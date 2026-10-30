-- Same mod identity as the protected historical-transition source: its private
-- original state remains available. No new world or predecessor lab is made.
local plan = require("stage")
local KEY, FIXTURE = "mir5_historical_transition", "mir-fixture-mir5-historical-transition"
local CASE, DIRECT, PROBE = "published-f100-forward", "recipe-prod-research_character_mining_speed-1", "braking-force-1"
local SUSPENDED, FOREIGN = "mir-published-f100-suspended", "mir-published-f100-foreign"
local modern = plan.target == "f210"
local loaded, reported = false, false
local rows = {
  "recipe-prod-research_cannon_shooting_speed-1", "recipe-prod-research_character_crafting_speed-1",
  DIRECT, "recipe-prod-research_character_reach-1", "recipe-prod-research_character_walking_speed-1",
  "recipe-prod-research_electric_shooting_speed-1", "recipe-prod-research_flamethrower_shooting_speed-1",
  "recipe-prod-research_inventory_capacity-1", "recipe-prod-research_lab_productivity-1",
  "recipe-prod-research_robot_battery-1", "recipe-prod-research_rocket_shooting_speed-1",
  "braking-force-8", "inserter-capacity-bonus-8", "research-speed-7", "weapon-shooting-speed-7",
  "worker-robots-storage-4",
}
for index = 1, 7 do rows[#rows + 1] = "finite-laser-" .. index end
local function fail(message) error("[mir-published-f100-forward] " .. message) end
local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a-b) < 1e-7 end
local function state()
  local bucket = rawget(_G, "storage") or rawget(_G, "global")
  local value = bucket and bucket[KEY]
  if type(value) ~= "table" then fail("protected historical fixture state absent") end
  return value
end
local function name_for(key)
  local index = key:match("^finite%-laser%-(%d)$")
  return index and plan.laser_prefix .. index or key
end
local function technology(force, key)
  local value = force and force.technologies[name_for(key)]
  if not value or value.valid == false then fail("technology absent: " .. key) end
  return value
end
local function progress(force, value)
  if modern then return value.saved_progress end
  return force.get_saved_technology_progress(value)
end
local function normalize_progress(value)
  -- Old getter absence and modern saved_progress zero represent no investment.
  if value == nil or value == 0 then return 0 end
  return value
end
local function queue(force, current, second, amount)
  local values = force.research_queue or {}
  if (not modern and force.research_queue_enabled ~= true)
      or not force.current_research or force.current_research.name ~= current
      or #values ~= (second and 2 or 1) or values[1].name ~= current
      or (second and values[2].name ~= second) or not close(force.research_progress, amount) then
    fail("current/queued investment differs")
  end
end
local function effects(value)
  local result = {}
  for _, effect in pairs(value.prototype.effects) do
    local kind, ammo = effect.type, effect.ammo_category
    if modern and kind == "bulk-inserter-capacity-bonus" then kind = "stack-inserter-capacity-bonus" end
    if ammo == "laser-turret" then ammo = "laser" end
    result[#result+1] = {type=kind, ammo=ammo, modifier=effect.modifier}
  end
  table.sort(result, function(a,b)
    return a.type .. tostring(a.ammo) .. tostring(a.modifier) < b.type .. tostring(b.ammo) .. tostring(b.modifier)
  end)
  return result
end
local function snapshot(force)
  local result = {}
  for _, key in ipairs(rows) do
    local value = technology(force, key)
    result[key] = {level=value.level, researched=value.researched, enabled=value.enabled,
      visible=value.visible_when_disabled, maximum=value.prototype.max_level,
      progress=normalize_progress(progress(force,value)), effects=effects(value)}
  end
  return result
end
local function same(actual, expected, label)
  if type(actual) ~= type(expected) then fail(label .. " type differs") end
  if type(expected) == "number" then
    if not close(actual,expected) then fail(label .. " number differs") end
  elseif type(expected) == "table" then
    for key, value in pairs(expected) do same(actual[key], value, label .. "." .. tostring(key)) end
    for key in pairs(actual) do if expected[key] == nil then fail(label .. " extra field") end end
  elseif actual ~= expected then fail(label .. " value differs") end
end
local function closure()
  local mods = script.active_mods
  if mods.base ~= plan.base or mods["more-infinite-research"] ~= plan.mir
      or mods[FIXTURE] ~= plan.fixture then fail("exact engine/MIR/fixture closure differs") end
end
local function original_source(value, completed)
  local force, direct = game.forces.player, technology(game.forces.player,DIRECT)
  if value.origin ~= "published" or value.source_direct_finished ~= 1
      or not close(value.before_mining,0) or direct.level ~= (completed and 3 or 2) or direct.researched
      or not close(force.manual_mining_speed_modifier, completed and .1 or .05) then
    fail("original published mining lab/earned bonus differs")
  end
  local lab = value.source_lab
  if not lab or lab.valid ~= true or lab.active ~= false or lab.energy ~= 0 then fail("original source lab is not frozen") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  for _, pack in ipairs({"military-science-pack", "utility-science-pack"}) do
    if type(value.source_lab_initial[pack]) ~= "number"
        or value.source_lab_initial[pack] - inventory.get_item_count(pack) < 1 then
      fail("original source lab science consumption differs")
    end
  end
  if completed then queue(force,PROBE,nil,0)
  else queue(force,DIRECT,PROBE,.42) end
end
local function successor_science(saved)
  local lab=saved.lab
  if not lab or lab.valid~=true or lab.active~=false or lab.energy~=0
      or not close(saved.successor_units,35/60) then fail("successor frozen lab/work differs") end
  if modern and lab.disabled_by_script~=true then fail("successor scripted lab disablement differs") end
  local input=lab.get_inventory(defines.inventory.lab_input)
  for _, pack in ipairs({"military-science-pack","utility-science-pack"}) do
    local units,found=0,false
    for index=1,#input do
      local stack=input[index]
      if stack.valid_for_read and stack.name==pack then
        if type(stack.count)~="number" or stack.count<1 or stack.count%1~=0
            or type(stack.durability)~="number" or stack.durability<=0 or stack.durability>1 then
          fail("successor native science stack differs")
        end
        units,found=units+stack.count-1+stack.durability,true
      end
    end
    if not found or not close(units,32-saved.successor_units) then fail("successor actual fractional science consumption differs") end
  end
end
local function witness(value, completed)
  original_source(value,completed)
  local saved = value.forward
  if type(saved) ~= "table" or saved.origin ~= "published-f100-4.7.10003"
      or saved.seeded_finite_lasers ~= 7 or saved.seeded_inserter_levels ~= 1 then fail("enhanced source provenance differs") end
  if saved.successor_labs ~= (completed and 1 or 0)
      or (completed and value.successor_direct_finished ~= 1) then fail("successor real lab count differs") end
  if completed then successor_science(saved) end
  local force, observed = game.forces.player, snapshot(game.forces.player)
  -- Completing one new mining level is the only earned-state delta permitted.
  if completed then
    observed[DIRECT].level = observed[DIRECT].level - 1
    observed[DIRECT].progress = saved.player[DIRECT].progress
  end
  same(observed,saved.player,"player retained23")
  local capacity = modern and force.bulk_inserter_capacity_bonus or force.stack_inserter_capacity_bonus
  if not close(force.inserter_stack_size_bonus,saved.inserter)
      or not close(capacity,saved.stack) or not close(force.get_gun_speed_modifier(plan.ammo),2.2) then
    fail("earned laser/inserter native totals differ")
  end
  local paused, foreign = game.forces[SUSPENDED], game.forces[FOREIGN]
  if not paused or not foreign then fail("unrelated force absent") end
  same(snapshot(paused),saved.suspended,"suspended retained23")
  same(snapshot(foreign),saved.foreign,"foreign retained23")
  if paused.current_research ~= nil or #(paused.research_queue or {}) ~= 0
      or not close(progress(paused,technology(paused,DIRECT)),.27) then fail("suspended27% differs") end
  queue(foreign,PROBE,nil,.42)
end
local function seed(value)
  if plan.role ~= "source" or value.phase ~= "published-ready" or value.forward ~= nil then fail("enhancement origin/phase differs") end
  original_source(value,false) -- Original earned work is checked before writes.
  local force = game.forces.player
  if force.technologies["laser-turret-speed-8"] ~= nil then fail("published laser8 unexpectedly exists;review exact source before seeding") end
  local modifiers = {.1,.2,.3,.3,.4,.4,.5}
  for index = 1, 7 do
    local laser = technology(force,"finite-laser-" .. index)
    local vector = effects(laser)
    if laser.level ~= index or laser.prototype.max_level ~= index or #vector ~= 1
        or vector[1].type ~= "gun-speed" or vector[1].ammo ~= "laser"
        or not close(vector[1].modifier,modifiers[index]) then fail("published finite laser definition differs") end
  end
  local inserter = technology(force,"inserter-capacity-bonus-8")
  same(effects(inserter),{{type="inserter-stack-size-bonus",modifier=2},
    {type="stack-inserter-capacity-bonus",modifier=4}},"published inserter definition")
  if inserter.level ~= 8 or inserter.researched then fail("source inserter witness is not fresh") end
  for index = 1, 7 do technology(force,"finite-laser-" .. index).researched = true end
  -- Setting the next infinite level earns its prior effect. A later
  -- researched=false setter would erase it; deliberately do not issue one.
  inserter.level = 9
  force.reset_technology_effects()
  if inserter.researched or not close(force.inserter_stack_size_bonus,2)
      or not close(force.stack_inserter_capacity_bonus,4)
      or not close(force.get_gun_speed_modifier(plan.ammo),2.2) then fail("source seeded native bonuses differ") end
  local paused = game.create_force(SUSPENDED)
  paused.set_saved_technology_progress(technology(paused,DIRECT),.27)
  local foreign = game.create_force(FOREIGN)
  technology(foreign,DIRECT).enabled, technology(foreign,DIRECT).visible_when_disabled = false,false
  foreign.research_queue_enabled = true
  technology(foreign,PROBE).enabled = true
  local pending,seen,count = {technology(foreign,PROBE)},{},0
  while #pending > 0 do
    local current = table.remove(pending)
    if not seen[current.name] then
      seen[current.name],count = true,count+1
      if count > 256 then fail("foreign probe prerequisite bound exceeded") end
      for _, prerequisite in pairs(current.prerequisites or {}) do
        prerequisite.enabled,prerequisite.researched = true,true
        pending[#pending+1] = prerequisite
      end
    end
  end
  if foreign.add_research(technology(foreign,PROBE)) ~= true then fail("foreign queue failed") end
  foreign.research_progress = .42
  value.forward = {origin="published-f100-4.7.10003",phase="source-complete",seeded_finite_lasers=7,
    seeded_inserter_levels=1,player=snapshot(force),suspended=snapshot(paused),foreign=snapshot(foreign),
    inserter=force.inserter_stack_size_bonus,stack=force.stack_inserter_capacity_bonus,successor_labs=0}
  witness(value,false)
end
local function start_successor(value)
  witness(value,false) -- Every source assertion precedes fixture writes.
  if value.phase ~= "published-ready" or value.forward.phase ~= "source-complete"
      or value.forward.successor_labs ~= 0 then fail("successor transition phase differs") end
  local force, surface = game.forces.player, game.surfaces[1]
  if not close(force.laboratory_speed_modifier,0) or not close(force.laboratory_productivity_bonus,0) then fail("native lab modifiers differ") end
  local units=math.ceil((1-force.research_progress)*60)/60
  if not close(units,35/60) then fail("successor partial work differs") end
  local position = force.get_spawn_position(surface)
  local lab = surface.create_entity{name="lab",position={x=position.x+8,y=position.y},force=force}
  if not lab or lab.valid ~= true then fail("successor real lab creation failed") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  for _, pack in ipairs({"military-science-pack","utility-science-pack"}) do
    if inventory.insert{name=pack,count=32} ~= 32 then fail("successor lab science insertion failed") end
  end
  value.forward.lab, value.forward.phase, value.forward.deadline = lab,"successor-lab",game.tick+18000
  value.forward.successor_units=units
  value.phase, value.successor_direct_finished = "mir5-successor",0
end
local function marker(stage, value)
  log('[MIR5_NATIVE_FIXTURE] RESULT {"case":"' .. CASE .. '","stage":"' .. stage
    .. '","role":"' .. plan.role .. '","target":"' .. plan.target
    .. '","status":"passed","origin":"published-f100-4.7.10003","retained_rows":23'
    .. ',"reused_source_labs":1,"new_source_labs":0,"seeded_finite_lasers":7,"seeded_inserter_levels":1'
    .. ',"successor_labs":' .. tostring(value.forward.successor_labs)
    .. ',"laser_bonus":2.2,"inserter_bonus":2,"stack_or_bulk_bonus":4,"source_queued_progress":0.42'
    .. ',"suspended_progress":0.27,"foreign_disabled":true,"on_load_read_only":' .. tostring(stage=="reload") .. '}')
end
script.on_init(function() fail("protected F100 save required;fresh worlds forbidden") end)
script.on_configuration_changed(function()
  closure()
  local value = state()
  if plan.role == "source" then
    if value.forward == nil then seed(value) else witness(value,false) end
  elseif plan.role == "bridge" then
    witness(value,false)
    if value.forward.phase ~= "source-complete" then fail("engine bridge source phase differs") end
  elseif plan.role == "successor" then
    if value.forward and value.forward.phase == "successor-complete" then witness(value,true)
    else start_successor(value) end
  else fail("unknown forward role") end
end)
script.on_load(function()
  local value = state()
  loaded = value.forward and value.forward.phase == (plan.role=="successor" and "successor-complete" or "source-complete")
  reported = false -- Local only; no game/native/persistent writes.
end)
script.on_event(defines.events.on_research_finished,function(event)
  local value = state()
  if event.research and event.research.force == game.forces.player and event.research.name == DIRECT then
    if not value.forward or value.forward.phase ~= "successor-lab" then fail("unexpected extra mining completion") end
    value.forward.successor_labs = value.forward.successor_labs+1
    if value.forward.successor_labs ~= 1 then fail("duplicate successor completion") end
    value.successor_direct_finished, value.forward.phase = 1,"successor-observe"
  end
end)
script.on_event(defines.events.on_tick,function()
  local value = state()
  closure()
  local saved = value.forward
  if not saved then fail("enhanced source absent") end
  if saved.phase == "successor-lab" then
    if game.tick > saved.deadline then fail("successor useful research deadline exceeded") end
    saved.lab.energy = 100000000
    return
  end
  if saved.phase == "successor-observe" then
    if modern then saved.lab.disabled_by_script = true
    else saved.lab.active = false end
    saved.lab.energy = 0
    successor_science(saved)
    saved.phase,value.phase = "successor-complete","mir5-complete"
  end
  local completed = plan.role=="successor"
  if saved.phase ~= (completed and "successor-complete" or "source-complete") then fail("settled phase differs") end
  witness(value,completed)
  local save_key = "saved_" .. plan.role .. "_" .. plan.target
  if not saved[save_key] then
    saved[save_key] = true
    marker("initial",value);game.server_save("mir5-native-complete")
    loaded,reported = false,true
  elseif loaded and not reported then
    marker("reload",value);reported = true
  end
end)
