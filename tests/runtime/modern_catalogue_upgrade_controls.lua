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
  local subject = {name="low-density-structure-productivity",level=4,researched=false,enabled=true,
    saved_progress=0,research_unit_count=100,research_unit_ingredients={{name="automation-science-pack"}},prototype={max_level=4294967295}}
  local force = {technologies={[subject.name]=subject},recipes={iron={productivity_bonus=0.1}},research_queue={}}
  for _, name in ipairs({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_ice-1", "recipe-prod-research_science_pack_productivity-1", "weapon-shooting-speed-7"}) do
    force.technologies[name] = {name=name,level=3,researched=false,enabled=true,saved_progress=0.23}
  end
  force.research_all_technologies = function() end
  force.add_research = function(value) force.current_research=value;force.research_queue={value};return true end
  local env = setmetatable({storage={},settings={startup={
    ["mir-upgrade-archetype"]={value="space-age-native-owner"},["ips-max-level-research_low_density_structure"]={value=5}}},
    script={active_mods={["more-infinite-research"]=from,["space-age"]="2.1.21"}},defines={events={on_tick=1}},
    game={forces={player=force},server_save=function() end},log=function(text) logs[#logs+1]=text end}, {__index=_G})
  env.script.on_init=function(fn) callbacks.init=fn end
  env.script.on_configuration_changed=function(fn) callbacks.upgrade=fn end
  env.script.on_load=function(fn) callbacks.load=fn end
  env.script.on_event=function(_,fn) callbacks.tick=fn end
  local function reload() assert(load(source,"complete-catalogue-fixture","t",env))() end
  reload();callbacks.init()
  env.script.active_mods["more-infinite-research"]=to
  return {env=env,force=force,callbacks=callbacks,logs=logs,reload=reload}
end
for _, transition in ipairs({{"4.1.21000","4.2.21000"},{"4.2.21000","4.2.21001"},{"4.2.21001","4.2.21002"}}) do
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
  {"research queue changed",function(f) f.force.research_queue={} end}
}
for _, case in ipairs(mutations) do
  local f=fixture("4.2.21001","4.2.21002");case[2](f)
  local ok,reason=pcall(f.callbacks.upgrade)
  check(not ok and tostring(reason):find(case[1],1,true)~=nil,"upgrade oracle must reject "..case[1])
  f=fixture("4.2.21001","4.2.21002");f.callbacks.upgrade();f.reload();case[2](f)
  ok,reason=pcall(f.callbacks.tick)
  check(not ok and tostring(reason):find(case[1],1,true)~=nil,"reload oracle must reject "..case[1])
end
print("MIR-MODERN-CATALOGUE-CONTROLS-PASS "..checks)
