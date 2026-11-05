-- Observe final native facts. This is not an emission or process-safety oracle.
local name = "ric-carbonise-marine-biomass"
local recipe = data.raw.recipe and data.raw.recipe[name]
if not recipe then error("[mir5-ric-context] upstream Marine recipe absent") end
local owner = data.raw.technology["recipe-prod-research_material_ric_coke-1"]
log("[MIR5_RIC_DATA] recipe=" .. name
  .. " allow_productivity=" .. tostring(recipe.allow_productivity)
  .. " maximum_productivity=" .. tostring(recipe.maximum_productivity)
  .. " mir_owner_present=" .. tostring(owner ~= nil))
