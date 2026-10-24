local function reaches(name, wanted, seen)
  if name == wanted then return true end
  if seen[name] then return false end
  seen[name] = true
  for _, prerequisite in ipairs((data.raw.technology[name] or {}).prerequisites or {}) do
    if reaches(prerequisite, wanted, seen) then return true end
  end
  return false
end
local retained, effects = 0, 0
for name, technology in pairs(data.raw.technology) do
  if name:find("recipe-prod-research_", 1, true) == 1 then
    for _, ingredient in ipairs((technology.unit or {}).ingredients or {}) do
      if (ingredient.name or ingredient[1]) == "planetary-data" then
        assert((ingredient.amount or ingredient[2]) > 0, "Planetary-data quantity was lost")
        assert(reaches(name, "mir473-seeded-planetary-owner", {}), "The independently seeded native gate was lost")
        assert(not reaches(name, "mir473-circular-planetary-owner", {}), "A circular alternative became a required gate")
        retained = retained + 1
        for _, effect in ipairs(technology.effects or {}) do
          if effect.type == "change-recipe-productivity" and effect.change > 0 then effects = effects + 1 end
        end
        break
      end
    end
  end
end
assert(retained > 0 and effects > 0, "Planetary-data research or positive effects were removed")
assert(data.raw.technology["mir473-circular-planetary-owner"].unit.ingredients[1][1] == "planetary-data",
  "Foreign circular research was mutated")
log("[mir473] planetary-data research, quantities and native seed prerequisites retained count=" .. retained .. " effects=" .. effects)
