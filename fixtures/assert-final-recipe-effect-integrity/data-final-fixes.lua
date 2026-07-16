local removed_recipe = "kr-copper-cable-from-copper-ore"
local copper_cable_technology = "recipe-prod-research_copper_cable-1"

if data.raw.recipe[removed_recipe] then
  error("MIR final recipe effect fixture failed: Space Exploration recipe removal did not run")
end

local copper_cable = data.raw.technology[copper_cable_technology]
if not copper_cable then
  error("MIR final recipe effect fixture failed: missing " .. copper_cable_technology)
end

local found_base_copper_cable = false
local found_external_valid_unlock = false
for technology_name, technology in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" or effect.type == "unlock-recipe" then
      if effect.recipe == removed_recipe then
        error("MIR final recipe effect fixture failed: "
          .. technology_name
          .. " references removed recipe "
          .. removed_recipe)
      end
      if not data.raw.recipe[effect.recipe] then
        error("MIR final recipe effect fixture failed: "
          .. technology_name
          .. " references missing recipe "
          .. tostring(effect.recipe))
      end
      if technology_name == copper_cable_technology and effect.recipe == "copper-cable" then
        found_base_copper_cable = true
      end
      if technology_name == "mir-fixture-external-dangling-unlock"
        and effect.type == "unlock-recipe"
        and effect.recipe == "copper-cable" then
        found_external_valid_unlock = true
      end
    end
  end
end

if not found_base_copper_cable then
  error("MIR final recipe effect fixture failed: valid base copper cable productivity was not retained")
end
if not found_external_valid_unlock then
  error("MIR final recipe effect fixture failed: valid external unlock effect was not retained")
end
