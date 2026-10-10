-- Host controls for the actual 4.2.2 fixture callbacks. These small tables
-- test the oracle's refusals; they do not emulate native research or saves.
local checks = 0
local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local copper_name = "recipe-prod-research_copper-1"
local function check(value, message) checks = checks + 1; assert(value, message) end
local function fixture(cap)
  local callbacks, logs, saves = {}, {}, {}
  local legacy = {name=legacy_name, level=3, researched=true, prototype={max_level=3}}
  local stage = {name=continuation_name, level=4, researched=false, enabled=true, research_unit_count=100,
    prerequisites={legacy}, prototype={max_level=4294967295,
      effects={{type="change-recipe-productivity",recipe="kr-imersite-powder",change=0.02}}}}
  local copper = {name=copper_name, level=2, enabled=true, research_unit_count=100}
  local force = {technologies={[legacy_name]=legacy,[copper_name]=copper}, recipes={
    ["kr-imersite-powder"]={productivity_bonus=0},["kr-imersite-crystal"]={productivity_bonus=0.10}}}
  if cap == 0 then force.technologies[continuation_name] = stage end
  force.research_all_technologies = function() end
  force.reset_technology_effects = function()
    force.recipes["kr-imersite-powder"].productivity_bonus = cap == 0 and 0.08 or 0.06
  end
  force.add_research = function(value) force.current_research = value; return true end
  force.cancel_current_research = function() force.current_research = nil end
  local env = setmetatable({storage={}, settings={startup={
    ["ips-max-level-research_material_imersite"]={value=cap}}},
    script={active_mods={base="2.1.21",Krastorio2="2.1.3",["Krastorio2-spaced-out"]="2.0.13",["more-infinite-research"]="4.2.21001"}},
    defines={events={on_tick=1}}, game={forces={player=force},server_save=function(name) saves[#saves+1]=name end},
    log=function(text) logs[#logs+1]=text end}, {__index=_G})
  env.script.on_init=function(fn) callbacks.init=fn end
  env.script.on_configuration_changed=function(fn) callbacks.upgrade=fn end
  env.script.on_load=function(fn) callbacks.load=fn end
  env.script.on_event=function(id,fn) assert(id==1);callbacks.tick=fn end
  local function load_fixture() assert(load(MIR_K2_MAINTENANCE_SOURCE,"k2-maintenance-fixture","t",env))() end
  load_fixture()
  return {env=env,force=force,legacy=legacy,stage=stage,callbacks=callbacks,logs=logs,saves=saves,load_fixture=load_fixture}
end
local function prepare(cap)
  local f=fixture(cap);f.callbacks.init()
  check(f.force.current_research.name==(cap==0 and continuation_name or copper_name),"source queue subject")
  check(f.env.storage.mir_k2_maintenance.source_version=="4.2.21001","published predecessor identity")
  f.env.script.active_mods["more-infinite-research"]="4.2.21002"
  return f
end
for _, cap in ipairs{0,3} do
  for _, count in ipairs{50,100,200} do
    local f=prepare(cap)
    f.force.current_research.research_unit_count=count
    f.force.research_progress=math.min(1,42/count)
    f.callbacks.upgrade();f.callbacks.tick()
    check(f.saves[1]=="mir-4221002-upgraded" and #f.saves==1,"actual candidate save name")
    for pass=1,2 do
      f.load_fixture();f.callbacks.load();f.callbacks.tick()
      check(f.logs[#f.logs]:find("4.2.21002 upgraded save reload proof complete",1,true)~=nil,"distinct reload callback")
      check(#f.saves==1,"reload does not repeat source save")
    end
  end
  local cases={
    {"wrong input",function(f) f.env.script.active_mods["more-infinite-research"]="4.2.21003" end},
    {"source state changed",function(f) f.env.storage.mir_k2_maintenance.source_version="4.2.21000" end},
    {"source state changed",function(f) f.env.settings.startup["ips-max-level-research_material_imersite"].value=cap==0 and 3 or 0 end},
    {"finite earned domain",function(f) f.legacy.prototype.max_level=4294967295 end},
    {"finite earned domain",function(f) f.legacy.researched=false end},
    {"earned finite level",function(f) f.legacy.level=2 end},
    {"powder reward",function(f) f.force.recipes["kr-imersite-powder"].productivity_bonus=0 end},
    {"separate crystal reward",function(f) f.force.recipes["kr-imersite-crystal"].productivity_bonus=0.12 end},
    {"queue changed",function(f) f.force.research_queue={} end},
    {"research progress",function(f) f.force.research_progress=0.41 end},
    {"research progress",function(f) f.force.current_research.research_unit_count=200 end}}
  if cap==0 then
    cases[#cases+1]={"earned continuation",function(f) f.stage.level=4 end}
    cases[#cases+1]={"finite prerequisite",function(f) f.stage.prerequisites={} end}
    cases[#cases+1]={"continuation owner",function(f) f.stage.prototype.effects[1].recipe="kr-imersite-crystal" end}
    cases[#cases+1]={"continuation modifier",function(f) f.stage.prototype.effects[1].change=0.03 end}
  else
    cases[#cases+1]={"cap three admitted",function(f) f.force.technologies[continuation_name]=f.stage end}
  end
  for _, case in ipairs(cases) do
    local f=prepare(cap);case[2](f)
    local ok,reason=pcall(f.callbacks.upgrade)
    check(not ok and tostring(reason):find(case[1],1,true)~=nil,"oracle must reject "..case[1]..": "..tostring(reason))
  end
  for _, version in ipairs{"4.2.21000","4.2.21002"} do
    local f=fixture(cap);f.env.script.active_mods["more-infinite-research"]=version
    local ok,reason=pcall(f.callbacks.init)
    check(not ok and tostring(reason):find("wrong input",1,true)~=nil,"source version refusal")
  end
end
return checks
