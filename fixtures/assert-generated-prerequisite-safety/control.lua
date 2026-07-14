local function generated_technology_names(force)
  local names = {}
  for technology_name, _ in pairs(force.technologies) do
    if string.match(technology_name, "^recipe%-prod%-research_") then
      table.insert(names, technology_name)
    end
  end
  table.sort(names)
  return names
end

script.on_init(function()
  local force = game.forces.player
  force.research_all_technologies()

  for _, technology_name in ipairs(generated_technology_names(force)) do
    local technology = force.technologies[technology_name]
    for _, prerequisite in pairs(technology.prerequisites or {}) do
      if not prerequisite.enabled or not prerequisite.researched then
        error("MIR validation failed: generated technology " .. technology_name
          .. " remains blocked by " .. prerequisite.name .. " after research_all_technologies().")
      end
    end
  end
end)
