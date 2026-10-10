-- Exercise the actual specialized upgrade callbacks. These controlled tables
-- prove oracle activation and refusal; they are not native save evidence.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function fixture(from, to)
  local file = assert(io.open(REPO_ROOT .. "/fixtures/assert-upgrade-4-0-21000-to-4-1-21000/control.lua", "rb"))
  local source = file:read("*a"); file:close()
  -- Use the same collision-free version substitutions as the native runner.
  source = source:gsub("4%.0%.21000", "__FROM__"):gsub("4%.1%.21000", "__TO__")
  source = source:gsub("__FROM__", from):gsub("__TO__", to)
  local callbacks, logs = {}, {}
  local function technology_record(name)
    return {name=name,level=3,researched=false,enabled=true,visible_when_disabled=true,
      saved_progress=0.23,research_unit_count=100,research_unit_count_formula=nil,research_unit_energy=30,
      research_unit_ingredients={{name="automation-science-pack",amount=1}},
      prototype={max_level=4294967295,order="a",hidden=false,hidden_in_factoriopedia=false,
        prerequisites={automation={}},effects={{type="worker-robot-storage",modifier=1}}}}
  end
  local subject = technology_record("low-density-structure-productivity")
  subject.level=4;subject.saved_progress=0
  local force = {technologies={[subject.name]=subject},recipes={iron={productivity_bonus=0.1}},research_queue={}}
  for _, name in ipairs({"artillery_range_modifier","beacon_distribution_modifier","belt_stack_size_bonus",
    "bulk_inserter_capacity_bonus","character_build_distance_bonus","character_health_bonus",
    "character_inventory_slots_bonus","character_item_drop_distance_bonus","character_item_pickup_distance_bonus",
    "character_loot_pickup_distance_bonus","character_reach_distance_bonus","character_resource_reach_distance_bonus",
    "character_running_speed_modifier","following_robots_lifetime_modifier","inserter_stack_size_bonus",
    "laboratory_productivity_bonus","laboratory_speed_modifier","manual_crafting_speed_modifier",
    "manual_mining_speed_modifier","mining_drill_productivity_bonus","train_braking_force_bonus",
    "worker_robots_battery_modifier","worker_robots_speed_modifier","worker_robots_storage_bonus"}) do force[name]=0.5 end
  for _, name in ipairs({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_ice-1", "recipe-prod-research_science_pack_productivity-1", "weapon-shooting-speed-7"}) do
    force.technologies[name] = technology_record(name)
  end
  force.research_all_technologies = function() end
  force.add_research = function(value) force.current_research=value;force.research_queue={value};return true end
  local env = setmetatable({storage={},settings={startup={
    ["mir-upgrade-archetype"]={value="space-age-native-owner"},["ips-max-level-research_low_density_structure"]={value=5},["mir-use-installed-space-age-icons"]={value=false}}},
    script={active_mods={["more-infinite-research"]=from,["space-age"]="2.1.21"}},defines={events={on_tick=1}},
    game={forces={player=force},server_save=function() end},
    helpers={table_to_json=function(value) return value.stage end,write_file=function(path,value) logs[#logs+1]="external snapshot "..path.."="..value end},
    log=function(text) logs[#logs+1]=text end}, {__index=_G})
  env.script.on_init=function(fn) callbacks.init=fn end
  env.script.on_configuration_changed=function(fn) callbacks.upgrade=fn end
  env.script.on_load=function(fn) callbacks.load=fn end
  env.script.on_event=function(_,fn) callbacks.tick=fn end
  local function reload() assert(load(source,"complete-catalogue-fixture","t",env))() end
  reload();callbacks.init()
  env.script.active_mods["more-infinite-research"]=to
  return {env=env,force=force,callbacks=callbacks,logs=logs,reload=reload}
end
for _, transition in ipairs({{"4.1.21000","4.2.21000"},{"4.2.21000","4.2.21001"},{"4.2.21000","4.2.21002"},{"4.2.21001","4.2.21002"}}) do
  local f=fixture(transition[1],transition[2])
  check(f.env.storage.mir_upgrade_fixture.complete_state~=nil,"complete oracle must capture "..transition[1].." -> "..transition[2])
  f.callbacks.upgrade()
  check(table.concat(f.logs,"\n"):find("complete Space Age state retained technologies=5 recipes=1",1,true)~=nil,"full-state proof marker")
  for pass=1,2 do f.reload();f.callbacks.load();f.callbacks.tick() end
  check(f.env.storage.mir_upgrade_fixture.upgrade_complete,"two reload callback checks")
end
local mutations={
  {"existing technology disappeared",function(f) f.force.technologies["weapon-shooting-speed-7"]=nil end},
  {"existing technology state changed",function(f) f.force.technologies["weapon-shooting-speed-7"].level=1 end},
  {"saved research progress changed",function(f) f.force.technologies["weapon-shooting-speed-7"].saved_progress=0 end},
  {"recipe research bonus changed",function(f) f.force.recipes.iron.productivity_bonus=0 end},
  {"research queue changed",function(f) f.force.research_queue={} end},
  {"earned force effect changed",function(f) f.force.worker_robots_storage_bonus=0 end},
  {"technology visibility changed",function(f) f.force.technologies["weapon-shooting-speed-7"].visible_when_disabled=false end},
  {"technology definition changed",function(f) f.force.technologies["weapon-shooting-speed-7"].prototype.effects[1].modifier=2 end},
  {"technology definition changed",function(f) f.force.technologies["weapon-shooting-speed-7"].prototype.prerequisites={} end},
  {"technology definition changed",function(f) f.force.technologies["weapon-shooting-speed-7"].research_unit_ingredients[1].amount=2 end},
  {"startup/imported settings changed",function(f) f.env.settings.startup["mir-use-installed-space-age-icons"].value=true end},
  {"complete source forces missing",function(f) f.env.storage.mir_upgrade_fixture.complete_forces=nil end}
}
for _, case in ipairs(mutations) do
  local f=fixture("4.2.21001","4.2.21002");case[2](f)
  local ok,reason=pcall(f.callbacks.upgrade)
  check(not ok and tostring(reason):find(case[1],1,true)~=nil,"upgrade oracle must reject "..case[1])
  if case[1] ~= "complete source forces missing" then
    f=fixture("4.2.21001","4.2.21002");f.callbacks.upgrade();f.reload();case[2](f)
    ok,reason=pcall(f.callbacks.tick)
    check(not ok and tostring(reason):find(case[1],1,true)~=nil,"reload oracle must reject "..case[1])
  end
end
local f=fixture("4.2.21001","4.2.21002")
check(table.concat(f.logs,"\n"):find("external snapshot mir-upgrade-full-state-source.json=source",1,true)~=nil,"independent source output required")
local added=fixture("4.2.21000","4.2.21002")
added.env.settings.startup["ips-enable-research_material_glycerol"]={value=true}
added.env.settings.startup["ips-cost-linear-increment-research_material_py_wood"]={value=0}
local allowed,reason=pcall(added.callbacks.upgrade)
check(allowed,"only the exact adopted new setting defaults may appear: "..tostring(reason))
for _, change in ipairs({
  {"ips-enable-research_material_glycerol",false},
  {"ips-cost-base-research_material_py_wood",201},
  {"ips-enable-research_material_unreviewed",true}
}) do
  local control=fixture("4.2.21000","4.2.21002")
  control.env.settings.startup[change[1]]={value=change[2]}
  local accepted,why=pcall(control.callbacks.upgrade)
  check(not accepted and tostring(why):find("startup/imported settings changed",1,true),"unreviewed new settings must fail")
end
f.force.technologies["recipe-prod-research_ice-1"]=nil
f.env.storage.mir_upgrade_fixture.complete_forces.player.technologies["recipe-prod-research_ice-1"]=nil
f.env.storage.mir_upgrade_fixture.complete_state.technologies["recipe-prod-research_ice-1"]=nil
local ok,reason=pcall(f.callbacks.upgrade)
check(not ok and tostring(reason):find("reported technology absent",1,true)~=nil,"damaged predecessor cannot hide missing restored definition")
print("MIR-MODERN-CATALOGUE-CONTROLS-PASS "..checks)
