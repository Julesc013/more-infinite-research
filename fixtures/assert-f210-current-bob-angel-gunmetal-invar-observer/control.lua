local subjects = {
  {family = "gunmetal", technology = "recipe-prod-research_material_gunmetal-1"},
  {family = "invar", technology = "recipe-prod-research_material_invar-1"}
}
local reload_pending = false

local function state_line()
  local force = game.forces.player
  local values = {}
  for _, subject in ipairs(subjects) do
    local technology = force and force.technologies[subject.technology] or nil
    values[#values + 1] = subject.family .. ":present=" .. tostring(technology ~= nil)
      .. ":researched=" .. tostring(technology and technology.researched or false)
  end
  return table.concat(values, ",")
end

script.on_init(function()
  log("[mir-f210-current-ba-gunmetal-invar-observer] RUNTIME stage=create " .. state_line())
end)

script.on_load(function() reload_pending = true end)
script.on_event(defines.events.on_tick, function()
  if not reload_pending then return end
  reload_pending = false
  log("[mir-f210-current-ba-gunmetal-invar-observer] RUNTIME stage=reload " .. state_line())
end)
