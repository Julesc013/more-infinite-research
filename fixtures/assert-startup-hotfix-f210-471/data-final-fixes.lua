local iron = assert(data.raw.technology["recipe-prod-research_iron-1"], "MIR iron research was lost")
local pack, effect = false, false
for _, ingredient in ipairs(iron.unit.ingredients) do
  if (ingredient.name or ingredient[1]) == "automation-science-pack" then pack = true end
end
for _, entry in ipairs(iron.effects) do
  if entry.type == "change-recipe-productivity" and entry.recipe == "iron-plate" and entry.change > 0 then effect = true end
end
assert(pack and effect, "The startup repair lost required science or the positive iron effect")
assert(data.raw.technology["mir471-unrelated-infinite-61"].max_level == "infinite", "Foreign research was altered")
assert(data.raw.technology["mir471-seed-owner"].effects[1].recipe == "z-mir471-seeded-science", "Seed ownership was lost")
log("[mir471] representative startup research, science, effects and foreign ownership retained")
