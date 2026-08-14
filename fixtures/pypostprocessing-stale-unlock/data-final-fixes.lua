local technology = data.raw.technology["casting-mk02"]
if not technology or data.raw.recipe["casting-gear"] then
  error("MIR Py ordering fixture did not reproduce the removed casting-gear recipe")
end
if #technology.effects ~= 2 then
  error("MIR Py ordering fixture lost valid sibling effects before late reconstruction")
end

table.insert(technology.effects, 2, {type = "unlock-recipe", recipe = "casting-gear"})

local reconstructed = technology.effects[2]
if #technology.effects ~= 3 or not reconstructed
  or reconstructed.type ~= "unlock-recipe" or reconstructed.recipe ~= "casting-gear" then
  error("MIR Py ordering fixture did not reconstruct the late stale casting-gear unlock")
end
log("[mir-fixture] Py late stale-unlock reconstruction complete")
