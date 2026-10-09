-- Execute the real fixture's version gates. Supplies only enough objects to
-- reach its unchanged data oracle and runtime setup boundary; no native claim.
local checks = 0
local function effect(recipe, change)
  return {type="change-recipe-productivity", recipe=recipe, change=change}
end
local function probe(base, mir, k2, accepted, wrong_effect)
  local mods = {base=base, Krastorio2=k2, ["Krastorio2-spaced-out"]="2.0.13",
    ["more-infinite-research"]=mir}
  local env = setmetatable({mods=mods, log=function() end}, {__index=_G})
  env.data = {raw={technology={
    ["recipe-prod-research_material_imersite-1"]={max_level=3,
      effects={effect("kr-imersite-powder", 0.02)}},
    ["recipe-prod-research_material_imersite-4"]={max_level="infinite",
      effects={effect("kr-imersite-powder", wrong_effect and 0.03 or 0.02)}},
    ["kr-imersite-productivity"]={effects={effect("kr-imersite-crystal", 0.1)}}}}}
  local ok, reason = pcall(assert(load(MIR_K2_DATA_SOURCE, "fixture-data", "t", env)))
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
  assert(load(MIR_K2_CONTROL_SOURCE, "fixture-control", "t", env))()
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
end
probe("2.1.22", "4.2.21002", "2.1.3", false)
print("MIR-K2-VERSION-CONTROLS-PASS " .. checks .. " (host only)")
