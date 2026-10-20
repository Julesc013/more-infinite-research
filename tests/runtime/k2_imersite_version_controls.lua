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
  probe(engine, mir, k2, true, false, data_source, control_source, k2so)
  probe(engine, mir, k2, true, true, data_source, control_source, k2so)
  probe(engine, mir, "2.1.3", false, false, data_source, control_source, k2so)
  probe(engine, mir, k2, false, false, data_source, control_source, "2.0.13")
  probe(engine_prefix .. tostring(tonumber(engine_patch) + 1), mir, k2, false, false, data_source, control_source, k2so)
  probe(engine_prefix .. tostring(tonumber(engine_patch) - 1), mir, k2, false, false, data_source, control_source, k2so)
  probe(engine, mir_prefix .. tostring(tonumber(mir_patch) + 1), k2, false, false, data_source, control_source, k2so)
end
print("MIR-K2-VERSION-CONTROLS-PASS " .. checks .. " (host only)")
