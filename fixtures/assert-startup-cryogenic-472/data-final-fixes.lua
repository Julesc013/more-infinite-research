local owner = assert(data.raw.technology["cryogenic-science-pack"])
assert(owner.unit.ingredients[1][1] == "mir472-native-science", "Native cryogenic science was rewritten")
local function reaches(name, wanted, seen)
  if name == wanted then return true end
  if seen[name] then return false end
  seen[name] = true
  for _, prerequisite in ipairs((data.raw.technology[name] or {}).prerequisites or {}) do
    if reaches(prerequisite, wanted, seen) then return true end
  end
  return false
end
local retained = 0
for name, technology in pairs(data.raw.technology) do
  if name:find("recipe-prod-research_", 1, true) == 1 then
    for _, ingredient in ipairs((technology.unit or {}).ingredients or {}) do
      if (ingredient.name or ingredient[1]) == "cryogenic-science-pack" then
        assert(reaches(name, "cryogenic-science-pack", {}), "Cryogenic unlock prerequisite was lost")
        retained = retained + 1
        break
      end
    end
  end
end
assert(retained > 0, "MIR cryogenic science research was removed")
log("[mir472] cryogenic science, native owner and generated prerequisite retained count=" .. retained)
