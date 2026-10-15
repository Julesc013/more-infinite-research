local oracle_module = assert(loadfile("tests/support/MIR422HistoricalCompleteState.lua"))()
local checks = 0
local lines = {"0.13", "0.14", "0.15", "0.16", "0.17", "1.0", "1.1"}
local codes = { ["0.13"]="013", ["0.14"]="014", ["0.15"]="015", ["0.16"]="016", ["0.17"]="017", ["1.0"]="100", ["1.1"]="110" }
local function check(condition, message) if not condition then error(message) end; checks = checks + 1 end
local function version(line, minor, patch) return "4." .. minor .. "." .. codes[line] .. patch end
local function set_prerequisites(technology, names)
  technology.prerequisites = {}
  for _, name in ipairs(names) do technology.prerequisites[name] = {} end
end
local function fixture(line, reviewed_name, delta, source_version, target_version)
  source_version = source_version or version(line, "2", "00")
  target_version = target_version or version(line, "2", "02")
  global, settings, script = {}, {startup={setting={value="kept"}}}, {active_mods={["more-infinite-research"]=source_version}}
  local tech={name="kept",order="a",researched=true,enabled=true,level=2,visible_when_disabled=true,
    prerequisites={},research_unit_ingredients={{name="red",amount=1}},effects={{type="ammo-damage",ammo_category="bullet",modifier=0.1}},
    research_unit_count=100,research_unit_energy=30,prototype={max_level=10},saved_progress=0.23}
  local other={name="other",order="b",researched=false,enabled=true,level=1,visible_when_disabled=true,
    prerequisites={},research_unit_ingredients={{name="red",amount=1}},effects={},research_unit_count=50,
    research_unit_energy=30,prototype={max_level=1},saved_progress=0.17}
  if reviewed_name then
    tech.name=reviewed_name
    for field, values in pairs(delta) do
      if field == "ingredients" then tech.research_unit_ingredients=values.before
      elseif field == "prerequisites" then set_prerequisites(tech, values.before)
      else error("unsupported reviewed field: " .. field) end
    end
  end
  local force=setmetatable({technologies={kept=tech,other=other},recipes={plate={enabled=true}},research_queue={tech},
    research_queue_enabled=true,current_research=tech,research_progress=0.42,
    get_saved_technology_progress=function(t) return t.saved_progress end,
    get_ammo_damage_modifier=function() return 0.1 end}, {__index=function() return 0 end})
  local exports={}
  if reviewed_name then force.technologies.kept=nil;force.technologies[reviewed_name]=tech end
  game={forces={player=force},write_file=function(name,text) exports[name]=text end}
  log=function() end
  if line ~= "1.0" and line ~= "1.1" then
    script=setmetatable({}, {__index=function(_, key) error("unsupported historical script field: "..key) end})
  end
  local oracle=oracle_module.new(line,source_version,target_version)
  oracle.capture()
  if line == "1.0" or line == "1.1" then script.active_mods["more-infinite-research"]=target_version end
  return oracle,force,exports
end
local function apply_delta(force, name, delta)
  local technology = force.technologies[name]
  for field, values in pairs(delta) do
    if field == "ingredients" then technology.research_unit_ingredients = values.after
    elseif field == "prerequisites" then set_prerequisites(technology, values.after)
    else error("unsupported reviewed field: " .. field) end
  end
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
  local selected, state=fixture(line)
  state.technologies.added={name="added",order="c",researched=false,enabled=true,level=1,visible_when_disabled=true,
    prerequisites={},research_unit_ingredients={},effects={{type="gun-speed",ammo_category="electric",modifier=0.1}},
    research_unit_count=50,research_unit_energy=30,prototype={max_level=1},saved_progress=0}
  state.get_gun_speed_modifier=function() return 0 end
  check(pcall(selected.verify,"upgrade"),line.." rejected new zero category")
  state.get_gun_speed_modifier=function() return 0.1 end
  check(not pcall(selected.verify,"upgrade"),line.." accepted new earned category bonus")
  refuses(function(f) f.get_ammo_damage_modifier=function() return 0 end end,"lost earned category bonus")
  if line~="0.13" and line~="0.14" then
    refuses(function(f) f.technologies.kept.level=3 end,"changed infinite level")
    refuses(function(f) f.technologies.other.saved_progress=0.1 end,"changed saved progress")
    refuses(function() settings.startup.setting.value="lost" end,"changed startup setting")
  end
  if line=="0.17" or line=="1.0" or line=="1.1" then
    refuses(function(f) f.research_queue={} end,"changed queue")
    refuses(function(f) f.technologies.kept.visible_when_disabled=false end,"changed visibility")
  end
  local missing=oracle_module.new(line,version(line,"2","00"),version(line,"2","02"));global={}
  check(not pcall(missing.verify,"upgrade"),line.." accepted skipped source capture")
end

local legacy_transitions = {
  ["0.15"]={from="4.2.01500",to="4.2.01502"},
  ["0.16"]={from="4.2.01600",to="4.2.01602"}
}
for line, rows in pairs(oracle_module.reviewed_frontiers) do
  local transition = legacy_transitions[line]
  for name, delta in pairs(rows) do
    local oracle,force=fixture(line,name,delta,transition.from,transition.to);apply_delta(force,name,delta)
    check(pcall(oracle.verify,"upgrade"),line.." rejected reviewed frontier "..name)
    force.technologies[name].research_unit_count=101
    check(not pcall(oracle.verify,"upgrade"),line.." accepted unreviewed cost "..name)
    oracle,force=fixture(line,name,delta,transition.from,transition.to);apply_delta(force,name,delta);force.technologies[name].researched=false
    check(not pcall(oracle.verify,"upgrade"),line.." accepted earned loss "..name)
    oracle,force=fixture(line,name,delta,transition.from,transition.to);apply_delta(force,name,delta);force.technologies[name].prerequisites.unreviewed={}
    check(not pcall(oracle.verify,"upgrade"),line.." accepted unreviewed prerequisite "..name)
    oracle,force=fixture(line,name,delta,version(line,"2","01"),transition.to);apply_delta(force,name,delta)
    check(not pcall(oracle.verify,"upgrade"),line.." applied legacy exception to wrong predecessor "..name)
    oracle,force=fixture(line,name,delta,transition.from,version(line,"3","02"));apply_delta(force,name,delta)
    check(not pcall(oracle.verify,"upgrade"),line.." applied legacy exception to wrong destination "..name)
  end
end

-- Preserve the admitted 4.2.0 source paths beyond the original 4.2.2 check.
-- The oracle still compares every unlisted state field exactly.
local legacy_regressions = {
  {line="0.15",from="4.2.01500",to="4.2.01501",label="4.2.1"},
  {line="0.16",from="4.2.01600",to="4.3.01600",label="4.3.0"}
}
for _, transition in ipairs(legacy_regressions) do
  for name, delta in pairs(oracle_module.reviewed_frontiers[transition.line]) do
    local oracle, force = fixture(transition.line,name,delta,transition.from,transition.to);apply_delta(force,name,delta)
    check(pcall(oracle.verify,"upgrade"),transition.line.." rejected admitted legacy "..transition.label.." path for "..name)
  end
end

local f016_transitions = {
  {from="4.4.01600",to="4.4.01602"},
  {from="4.4.01601",to="4.4.01602"}
}
local f016_rows = oracle_module.reviewed_frontier_transitions["0.16"]["4.4.01600->4.4.01602"]
check(f016_rows == oracle_module.reviewed_frontier_transitions["0.16"]["4.4.01601->4.4.01602"],"F016 predecessor maps diverged without an independent allowance")
for _, transition in ipairs(f016_transitions) do
  for name, delta in pairs(f016_rows) do
    local oracle, force = fixture("0.16",name,delta,transition.from,transition.to);apply_delta(force,name,delta)
    check(pcall(oracle.verify,"upgrade"),"F016 rejected reviewed prerequisite restoration "..transition.from.."/"..name)
  end
end
local f016_name, f016_delta = "braking-force-8", f016_rows["braking-force-8"]
local function f016_refuses(mutate, message, source_version, target_version, seed_delta)
  local oracle, force = fixture("0.16",f016_name,seed_delta or f016_delta,source_version or "4.4.01600",target_version or "4.4.01602")
  mutate(force)
  check(not pcall(oracle.verify,"upgrade"),"F016 accepted "..message)
end
do
  local oracle, force = fixture("0.15",f016_name,f016_delta,"4.4.01600","4.4.01602");apply_delta(force,f016_name,f016_delta)
  check(not pcall(oracle.verify,"upgrade"),"F016 accepted wrong engine line")
end
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta) end,"wrong predecessor","4.4.01602")
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta) end,"wrong destination",nil,"4.4.01601")
do
  local oracle, force = fixture("0.16",f016_name,f016_delta,"4.4.01601","4.4.01603");apply_delta(force,f016_name,f016_delta)
  check(not pcall(oracle.verify,"upgrade"),"F016 accepted 4.4.1 restoration for an unlisted destination")
end
do
  local oracle, force = fixture("0.15",f016_name,f016_delta,"4.4.01601","4.4.01602");apply_delta(force,f016_name,f016_delta)
  check(not pcall(oracle.verify,"upgrade"),"F016 accepted 4.4.1 restoration on the wrong engine line")
end
do
  local bad_before={prerequisites={before={"advanced-electronics","braking-force-7"},after=f016_delta.prerequisites.after}}
  local oracle, force = fixture("0.16",f016_name,bad_before,"4.4.01600","4.4.01602");apply_delta(force,f016_name,f016_delta)
  check(not pcall(oracle.verify,"upgrade"),"F016 accepted an incorrect predecessor prerequisite vector")
end
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta);force.technologies[f016_name].prerequisites.engine=nil end,"missing restored gate")
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta);force.technologies[f016_name].prerequisites.unreviewed={} end,"extra restored gate")
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta);force.technologies[f016_name].research_unit_count=101 end,"changed cost")
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta);force.technologies[f016_name].effects[1].modifier=0.2 end,"changed effect")
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta);force.technologies[f016_name].research_unit_ingredients[1].amount=2 end,"changed ingredient")
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta);force.technologies[f016_name].saved_progress=0.91 end,"changed technology progress")
f016_refuses(function(force) apply_delta(force,f016_name,f016_delta);force.research_progress=0.5 end,"changed force state")
do
  local unlisted={prerequisites={before=f016_delta.prerequisites.before,after=f016_delta.prerequisites.after}}
  local oracle, force = fixture("0.16","unlisted-f016-tech",unlisted,"4.4.01600","4.4.01602");apply_delta(force,"unlisted-f016-tech",unlisted)
  check(not pcall(oracle.verify,"upgrade"),"F016 accepted an unlisted technology")
end
do
  local direct_422={prerequisites={before=f016_delta.prerequisites.after,after=f016_delta.prerequisites.after}}
  local oracle, force = fixture("0.16",f016_name,direct_422,"4.2.01602","4.4.01602")
  set_prerequisites(force.technologies[f016_name],f016_delta.prerequisites.before)
  check(not pcall(oracle.verify,"upgrade"),"F016 accepted changed direct 4.2.2 candidate")
end
print("MIR-HISTORICAL-COMPLETE-UPGRADE-CONTROLS-PASS "..checks)
