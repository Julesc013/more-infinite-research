local function validate_force(force)
  force.research_all_technologies()

  for name, technology in pairs(force.technologies) do
    if string.match(name, "^recipe%-prod%-research_") and technology.enabled then
      for _, prerequisite in pairs(technology.prerequisites or {}) do
        if not prerequisite.researched then
          error("MIR generated prerequisite safety validation failed: "
            .. name
            .. " remains blocked by "
            .. prerequisite.name
            .. " after research_all_technologies().")
        end
      end
    end
  end
end

script.on_init(function()
  validate_force(game.forces.player)
end)
