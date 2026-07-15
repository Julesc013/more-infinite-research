local tech = data.raw.technology and data.raw.technology["recipe-prod-research_science_pack_productivity-1"]
local found = false

for _, effect in ipairs((tech and tech.effects) or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == "mir-fixture-science-pack" then
    found = true
    break
  end
end

if not found then
  error("MIR validation failed: mir-fixture-science-pack did not receive science-pack productivity.")
end
