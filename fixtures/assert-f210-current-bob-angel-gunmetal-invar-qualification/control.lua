local subjects = {
  {technology = "recipe-prod-research_material_gunmetal-1", recipe = "angels-plate-gunmetal"},
  {technology = "recipe-prod-research_material_invar-1", recipe = "angels-plate-invar"}
}

local reload_pending = false

local function fail(message)
  error("[mir-f210-current-ba-gunmetal-invar] " .. message)
end

local function assert_runtime_state(stage)
  local force = game.forces.player
  if not force then fail(stage .. " player force is absent") end
  for _, subject in ipairs(subjects) do
    local technology = force.technologies[subject.technology]
    local recipe = force.recipes[subject.recipe]
    if not technology or not technology.researched then
      fail(stage .. " researched technology differs " .. subject.technology)
    end
    if not recipe or math.abs((recipe.productivity_bonus or -1) - 0.02) > 0.000001 then
      fail(stage .. " runtime productivity differs " .. subject.recipe)
    end
  end
end

script.on_init(function()
  local force = game.forces.player
  if not force then fail("initial player force is absent") end
  force.enable_all_prototypes()
  for _, subject in ipairs(subjects) do
    local technology = force.technologies[subject.technology]
    if not technology then fail("initial technology is absent " .. subject.technology) end
    technology.researched = true
  end
  assert_runtime_state("initial")
  storage.mir_f210_current_ba_gunmetal_invar = {version = 1, completed = true}
  log("[mir-f210-current-ba-gunmetal-invar] RUNTIME PASS"
    .. " stage=create gunmetal=0.02 invar=0.02 technologies=researched")
end)

script.on_load(function()
  reload_pending = true
end)

script.on_event(defines.events.on_tick, function()
  if not reload_pending then return end
  reload_pending = false
  local state = storage.mir_f210_current_ba_gunmetal_invar
  if not state or state.version ~= 1 or state.completed ~= true then
    fail("reload stored state differs")
  end
  assert_runtime_state("reload")
  log("[mir-f210-current-ba-gunmetal-invar] RELOAD PASS"
    .. " gunmetal=0.02 invar=0.02 technologies=researched save-state=preserved")
end)
