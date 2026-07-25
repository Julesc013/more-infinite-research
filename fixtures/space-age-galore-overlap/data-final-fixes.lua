local recipe_name = "vgal-coal-crushing"
local owners = {}

for technology_name, technology in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      table.insert(owners, technology_name)
    end
  end
end

table.sort(owners)
if #owners ~= 1 then
  error("MIR Galore overlap regression expected exactly one planned owner for " .. recipe_name
    .. ", found " .. tostring(#owners) .. ": " .. table.concat(owners, ","))
end
if owners[1] ~= "recipe-prod-research_carbon-1" then
  error("MIR Galore overlap regression selected an unstable owner for " .. recipe_name .. ": " .. owners[1])
end
