local target = "kr-copper-cable-from-copper-ore"
local mir_technology = "recipe-prod-research_copper_cable-1"

if not data.raw.recipe[target] then
  error("MIR Space Exploration ordering fixture setup failed: missing recipe " .. target)
end
if data.raw.technology[mir_technology] then
  error("MIR loaded before Space Exploration finalized its recipe removals")
end

data.raw.recipe[target] = nil
