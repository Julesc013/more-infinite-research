local technology = data.raw.technology["casting-mk02"]
if not technology or not data.raw.recipe["casting-gear"] then
  error("MIR Py ordering fixture setup failed")
end

data.raw.recipe["casting-gear"] = nil
local retained = {}
for _, effect in ipairs(technology.effects or {}) do
  if not (effect.type == "unlock-recipe" and effect.recipe == "casting-gear") then
    table.insert(retained, effect)
  end
end
technology.effects = retained