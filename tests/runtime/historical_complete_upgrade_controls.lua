local oracle_module = assert(loadfile("tests/support/MIR422HistoricalCompleteState.lua"))()
local checks = 0
local lines = {"0.13", "0.14", "0.15", "0.16", "0.17", "1.0", "1.1"}
local function check(condition, message) if not condition then error(message) end; checks = checks + 1 end
local function fixture(line)
  global, settings, script = {}, {startup={setting={value="kept"}}}, {active_mods={["more-infinite-research"]="4.2.11000"}}
  local tech={name="kept",order="a",researched=true,enabled=true,level=2,visible_when_disabled=true,
    prerequisites={},research_unit_ingredients={{name="red",amount=1}},effects={{type="ammo-damage",ammo_category="bullet",modifier=0.1}},
    research_unit_count=100,research_unit_energy=30,prototype={max_level=10},saved_progress=0.23}
  local other={name="other",order="b",researched=false,enabled=true,level=1,visible_when_disabled=true,
    prerequisites={},research_unit_ingredients={{name="red",amount=1}},effects={},research_unit_count=50,
    research_unit_energy=30,prototype={max_level=1},saved_progress=0.17}
  local force=setmetatable({technologies={kept=tech,other=other},recipes={plate={enabled=true}},research_queue={tech},
    research_queue_enabled=true,current_research=tech,research_progress=0.42,
    get_saved_technology_progress=function(t) return t.saved_progress end,
    get_ammo_damage_modifier=function() return 0.1 end}, {__index=function() return 0 end})
  local exports={}
  game={forces={player=force},write_file=function(name,text) exports[name]=text end}
  log=function() end
  if line ~= "1.0" and line ~= "1.1" then
    script=setmetatable({}, {__index=function(_, key) error("unsupported historical script field: "..key) end})
  end
  local oracle=oracle_module.new(line,"4.2.11000","4.2.11002")
  oracle.capture()
  if line == "1.0" or line == "1.1" then script.active_mods["more-infinite-research"]="4.2.11002" end
  return oracle,force,exports
end
for _, line in ipairs(lines) do
  local oracle, force, exports=fixture(line)
  oracle.verify("upgrade");oracle.verify("reload")
  check(exports["mir-upgrade-full-state-source.json"] and exports["mir-upgrade-full-state-reload.json"],line.." missing snapshots")
  local function refuses(mutate, message)
    local selected, state=fixture(line);mutate(state)
    check(not pcall(selected.verify,"upgrade"),line.." accepted "..message)
  end
  refuses(function(f) f.technologies.kept=nil end,"removed technology")
  refuses(function(f) f.technologies.kept.researched=false end,"lost earned research")
  refuses(function(f) f.technologies.kept.effects[1].modifier=0.2 end,"changed reward definition")
  refuses(function(f) f.technologies.kept.research_unit_ingredients[1].amount=2 end,"changed science amount")
  refuses(function(f) f.worker_robots_storage_bonus=1 end,"changed earned bonus")
  refuses(function(f) f.research_progress=0.5 end,"changed progress")
  refuses(function(f) f.recipes.plate.enabled=false end,"lost recipe availability")
  if line~="0.13" and line~="0.14" then
    refuses(function(f) f.technologies.kept.level=3 end,"changed infinite level")
    refuses(function(f) f.technologies.other.saved_progress=0.1 end,"changed saved progress")
    refuses(function() settings.startup.setting.value="lost" end,"changed startup setting")
  end
  if line=="0.17" or line=="1.0" or line=="1.1" then
    refuses(function(f) f.research_queue={} end,"changed queue")
    refuses(function(f) f.technologies.kept.visible_when_disabled=false end,"changed visibility")
  end
  local missing=oracle_module.new(line,"4.2.11000","4.2.11002");global={}
  check(not pcall(missing.verify,"upgrade"),line.." accepted skipped source capture")
end
print("MIR-HISTORICAL-COMPLETE-UPGRADE-CONTROLS-PASS "..checks)
