local tech = data.raw.technology and data.raw.technology["recipe-prod-research_mining_drill-1"]
local required = {
  ["omega-drill"] = false,
  ["omega-tau"] = false
}

for _, effect in ipairs((tech and tech.effects) or {}) do
  if effect.type == "change-recipe-productivity" and required[effect.recipe] ~= nil then
    required[effect.recipe] = true
  end
end

local missing = {}
for recipe, found in pairs(required) do
  if not found then
    table.insert(missing, recipe)
  end
end
table.sort(missing)

if #missing > 0 then
  error("MIR validation failed: Omega-style drill recipes did not receive mining drill productivity: " .. table.concat(missing, ", "))
end
