-- Execute the real fixture's version gates. Supplies only enough objects to
-- reach its unchanged data oracle and runtime setup boundary; no native claim.
local checks = 0
local function effect(recipe, change)
  return {type="change-recipe-productivity", recipe=recipe, change=change}
end
local function probe(base, mir, k2, accepted, wrong_effect, data_source, control_source, k2so)
  local mods = {base=base, Krastorio2=k2, ["Krastorio2-spaced-out"]=k2so or "2.0.13",
    ["more-infinite-research"]=mir}
  local env = setmetatable({mods=mods, log=function() end}, {__index=_G})
  env.data = {raw={technology={
    ["recipe-prod-research_material_imersite-1"]={max_level=3,
      effects={effect("kr-imersite-powder", 0.02)}},
    ["recipe-prod-research_material_imersite-4"]={max_level="infinite",
      effects={effect("kr-imersite-powder", wrong_effect and 0.03 or 0.02)}},
    ["kr-imersite-productivity"]={effects={effect("kr-imersite-crystal", 0.1)}}}}}
  local ok, reason = pcall(assert(load(data_source or MIR_K2_DATA_SOURCE, "fixture-data", "t", env)))
  assert(ok == (accepted and not wrong_effect), tostring(reason))
  checks = checks + 1
  if wrong_effect then return end
  local init
  env.script = {active_mods=mods, on_init=function(callback) init=callback end,
    on_load=function() end, on_event=function() end}
  env.defines = {events={on_tick=1}}
  env.game = {forces={player={research_all_technologies=function()
    error("CONTROLLED_SETUP_REACHED")
  end}}}
  assert(load(control_source or MIR_K2_CONTROL_SOURCE, "fixture-control", "t", env))()
  ok, reason = pcall(init)
  assert(not ok)
  local reached = string.find(tostring(reason), "CONTROLLED_SETUP_REACHED", 1, true) ~= nil
  assert(reached == accepted, tostring(reason))
  checks = checks + 1
end

-- The selected 2.1.22/K2 2.1.4 fixture deliberately avoids the retained
-- template's broad research-all setup. This Factorio-shaped boundary catches
-- its exact visible-state setup without simulating production or persistence.
local function probe_selected_current(data_source, control_source, engine, mir, k2, k2so)
  local mods = {base=engine, Krastorio2=k2, ["Krastorio2-spaced-out"]=k2so,
    ["more-infinite-research"]=mir}
  local env = setmetatable({mods=mods, log=function() end}, {__index=_G})
  env.data = {raw={technology={
    ["recipe-prod-research_material_imersite-1"]={max_level=3,
      effects={effect("kr-imersite-powder", 0.02)}},
    ["recipe-prod-research_material_imersite-4"]={max_level="infinite",
      effects={effect("kr-imersite-powder", 0.02)}},
    ["kr-imersite-productivity"]={effects={effect("kr-imersite-crystal", 0.1)}}}}}
  assert(pcall(assert(load(data_source, "selected-fixture-data", "t", env))))
  checks = checks + 1

  local init, reset_bonuses, broad_calls, prerequisite_calls = nil, {}, 0, 0
  local function prerequisite(name)
    local value = {name=name, researched=false}
    value.research_recursive = function()
      value.researched = true
      prerequisite_calls = prerequisite_calls + 1
    end
    return value
  end
  local legacy_prerequisite = prerequisite("legacy-prerequisite")
  local native_prerequisite = prerequisite("native-prerequisite")
  local stage_prerequisite = prerequisite("stage-prerequisite")
  local legacy = {name="recipe-prod-research_material_imersite-1", level=1, researched=false,
    prototype={max_level=3}, prerequisites={legacy_prerequisite}}
  legacy.research_recursive = function()
    legacy.researched = true
    prerequisite_calls = prerequisite_calls + 1
  end
  local stage = {name="recipe-prod-research_material_imersite-4", level=4, researched=false,
    prototype={max_level=4294967295}, prerequisites={legacy, stage_prerequisite}}
  local native = {name="kr-imersite-productivity", researched=false, prerequisites={native_prerequisite}}
  local early = {name="mir-k2-imersite-staged-state-1", researched=false}
  local tail = {name="mir-k2-imersite-continuation-state-4", researched=false}
  local force = {technologies={[legacy.name]=legacy, [stage.name]=stage, [native.name]=native,
    [early.name]=early, [tail.name]=tail}, recipes={
      ["kr-imersite-powder"]={enabled=false, productivity_bonus=0},
      ["kr-imersite-crystal"]={enabled=false, productivity_bonus=0}}, research_progress=0}
  setmetatable(force, {__newindex=function(target, key, value)
    if key == "research_queue" and value then
      for _, technology in ipairs(value) do
        for _, prerequisite_value in pairs(technology.prerequisites) do
          assert(prerequisite_value.researched, "UNMET_STAGE_PREREQUISITE:" .. prerequisite_value.name)
        end
      end
    end
    rawset(target, key, value)
    if key == "research_queue" then rawset(target, "current_research", value and value[1] or nil) end
  end})
  force.research_all_technologies = function() broad_calls = broad_calls + 1; error("BROAD_RESEARCH_FORBIDDEN") end
  force.reset_technology_effects = function()
    local powder = legacy.researched and legacy.level == 3 and 0.06 or 0
    if stage.level == 5 then powder = powder + 0.02 end
    force.recipes["kr-imersite-powder"].productivity_bonus = powder
    force.recipes["kr-imersite-crystal"].productivity_bonus = native.researched and 0.1 or 0
    reset_bonuses[#reset_bonuses + 1] = powder
  end
  env.script = {active_mods=mods, on_init=function(callback) init=callback end,
    on_load=function() end, on_event=function() end}
  env.defines = {events={on_tick=1}}
  env.game = {forces={player=force}, create_force=function() error("CURRENT_SETUP_REACHED") end}
  assert(load(control_source, "selected-fixture-control", "t", env))()
  local ok, reason = pcall(init)
  assert(not ok and tostring(reason):find("CURRENT_SETUP_REACHED", 1, true), tostring(reason))
  assert(broad_calls == 0, "selected current fixture used broad research")
  assert(prerequisite_calls == 4 and legacy_prerequisite.researched and native_prerequisite.researched
    and stage_prerequisite.researched, "selected current fixture did not close each direct prerequisite set")
  assert(legacy.level == 3 and legacy.researched and legacy.prototype.max_level == 3,
    "selected current fixture did not earn finite visible levels")
  assert(native.researched and not early.researched and not tail.researched,
    "selected current fixture did not isolate native/hidden credit")
  assert(force.recipes["kr-imersite-powder"].enabled
    and force.recipes["kr-imersite-powder"].productivity_bonus == 0.08
    and force.recipes["kr-imersite-crystal"].productivity_bonus == 0.1,
    "selected current fixture did not retain exact recipe effects")
  assert(reset_bonuses[1] == 0.06 and reset_bonuses[2] == 0.08,
    "selected current fixture did not establish finite state before continuation")
  assert(stage.level == 5 and force.current_research == stage and force.research_progress == 0.42,
    "selected current fixture did not retain visible continuation queue/progress")
  checks = checks + 1
end
for _, base in ipairs({"2.1.20", "2.1.21"}) do
  for _, mir in ipairs({"4.2.21001", "4.2.21002"}) do
    probe(base, mir, "2.1.3", true)
    probe(base, mir, "2.1.3", true, true)
    probe(base, mir, "2.1.2", false)
  end
  for _, mir in ipairs({"4.2.21000", "4.2.21003", "4.2.20002", "4.2.2"}) do
    probe(base, mir, "2.1.3", false)
  end
  probe(base, "4.4.21000", "2.1.3", true, false, MIR_K2_DATA_SOURCE_440, MIR_K2_CONTROL_SOURCE_440)
  probe(base, "4.4.21000", "2.1.3", true, true, MIR_K2_DATA_SOURCE_440, MIR_K2_CONTROL_SOURCE_440)
  probe(base, "4.4.21000", "2.1.2", false, false, MIR_K2_DATA_SOURCE_440, MIR_K2_CONTROL_SOURCE_440)
  probe(base, "4.4.21000", "2.1.3", false)
end
probe("2.1.22", "4.2.21002", "2.1.3", false)
probe("2.1.22", "4.4.21000", "2.1.3", false, false, MIR_K2_DATA_SOURCE_440, MIR_K2_CONTROL_SOURCE_440)
if MIR_K2_SELECTED_DATA_SOURCE then
  local data_source, control_source = MIR_K2_SELECTED_DATA_SOURCE, MIR_K2_SELECTED_CONTROL_SOURCE
  local engine, mir = MIR_K2_SELECTED_ENGINE, MIR_K2_SELECTED_MIR
  local k2, k2so = MIR_K2_SELECTED_K2, MIR_K2_SELECTED_K2SO
  local engine_prefix, engine_patch = string.match(engine, "^(%d+%.%d+%.)(%d+)$")
  local mir_prefix, mir_patch = string.match(mir, "^(%d+%.%d+%.)(%d+)$")
  assert(engine_prefix and mir_prefix and type(k2) == "string" and type(k2so) == "string", "selected exact version inputs")
  probe(engine, mir, k2, true, true, data_source, control_source, k2so)
  probe_selected_current(data_source, control_source, engine, mir, k2, k2so)
  probe(engine, mir, "2.1.3", false, false, data_source, control_source, k2so)
  probe(engine, mir, k2, false, false, data_source, control_source, "2.0.13")
  probe(engine_prefix .. tostring(tonumber(engine_patch) + 1), mir, k2, false, false, data_source, control_source, k2so)
  probe(engine_prefix .. tostring(tonumber(engine_patch) - 1), mir, k2, false, false, data_source, control_source, k2so)
  probe(engine, mir_prefix .. tostring(tonumber(mir_patch) + 1), k2, false, false, data_source, control_source, k2so)
end
print("MIR-K2-VERSION-CONTROLS-PASS " .. checks .. " (host only)")
