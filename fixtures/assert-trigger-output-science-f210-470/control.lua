local source_mir_version = "4.6.21000"
local target_mir_version = "4.7.21000"
local reloaded_after_target = false

local function fail(message)
  error("MIR trigger-output representative runtime failed: " .. message)
end

local function ingredient_names(technology)
  local names = {}
  for _, ingredient in pairs(technology.research_unit_ingredients or {}) do
    names[#names + 1] = ingredient.name
  end
  table.sort(names)
  return names
end

local function contains(values, expected)
  for _, value in ipairs(values) do if value == expected then return true end end
  return false
end

local function prerequisite_reaches(technology_name, expected, visited)
  if technology_name == expected then return true end
  visited = visited or {}
  if visited[technology_name] then return false end
  visited[technology_name] = true
  local prototype = prototypes.technology[technology_name]
  if not prototype then return false end
  for name in pairs(prototype.prerequisites or {}) do
    if prerequisite_reaches(name, expected, visited) then return true end
  end
  return false
end

local function productivity_effect(technology, recipe_name, amount)
  for _, effect in pairs(technology.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name
      and effect.change == amount then return true end
  end
  return false
end

local function assert_target_runtime()
  for name, effects in pairs({
    ["recipe-prod-research_ice-1"] = {
      ["oxide-asteroid-crushing"] = 0.10,
      ["advanced-oxide-asteroid-crushing"] = 0.10
    },
    ["recipe-prod-research_platform-1"] = { ["ice-platform"] = 0.10, ["space-platform-foundation"] = 0.05 }
  }) do
    local technology = game.forces.player.technologies[name]
    if not technology then fail("generated technology is absent: " .. name) end
    local sciences = ingredient_names(technology)
    if not contains(sciences, "space-science-pack") or not contains(sciences, "cryogenic-science-pack") then
      fail("generated science vector is incomplete: " .. name)
    end
    if not prerequisite_reaches(name, "space-science-pack") then
      fail("generated trigger-output progression is absent: " .. name)
    end
    for recipe_name, amount in pairs(effects) do
      if not productivity_effect(technology, recipe_name, amount) then
        fail("generated productivity effect changed: " .. name .. "/" .. recipe_name)
      end
    end
  end
end

script.on_init(function()
  if script.active_mods["more-infinite-research"] ~= source_mir_version
    or not script.active_mods["space-age"] then
    fail("source arm is not the untouched published 4.6 Space Age input")
  end
  storage.mir_trigger_output_representative = {phase = "source", source_version = source_mir_version}
  log("[mir-trigger-output-fixture] stage=source untouched-published-input=1")
end)

script.on_configuration_changed(function()
  local state = storage.mir_trigger_output_representative
  if not state or state.phase ~= "source" or state.source_version ~= source_mir_version then
    fail("candidate transition lacks an untouched source record")
  end
  if script.active_mods["more-infinite-research"] ~= target_mir_version then
    fail("candidate MIR identity is wrong")
  end
  assert_target_runtime()
  state.phase = "target-verified"
  state.target_version = target_mir_version
  log("[mir-trigger-output-fixture] stage=upgrade emitted-science-prerequisite-effects=verified")
end)

script.on_load(function()
  local state = storage.mir_trigger_output_representative
  reloaded_after_target = state and state.phase == "target-verified" or false
end)

script.on_event(defines.events.on_tick, function()
  if not reloaded_after_target then return end
  reloaded_after_target = false
  assert_target_runtime()
  log("[mir-trigger-output-fixture] stage=reload emitted-science-prerequisite-effects=verified")
end)
