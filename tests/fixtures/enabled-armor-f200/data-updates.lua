-- Change only the activation flag before MIR's final-fixes preflight.
local recipe = data.raw.recipe and data.raw.recipe["bob-mech-armor-plate"]
assert(type(recipe) == "table" and recipe.enabled == false,
  "MIR armor activation fixture requires the qualified locked recipe")
recipe.enabled = true
log("[MIR_ARMOR_ACTIVATION] bob-mech-armor-plate enabled=true")
