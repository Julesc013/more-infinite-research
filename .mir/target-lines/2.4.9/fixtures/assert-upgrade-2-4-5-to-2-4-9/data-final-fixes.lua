if mods["more-infinite-research"] == "2.4.9" then
  local contracts = require("__more-infinite-research__.prototypes.mir.integrity.effect_contracts")

  local function expect_valid(label, effect)
    local valid, reason = contracts.target_status(effect)
    if not valid then error(label .. " was rejected: " .. tostring(reason)) end
  end

  local function expect_invalid(label, effect)
    local valid = contracts.target_status(effect)
    if valid then error(label .. " unexpectedly passed") end
  end

  expect_valid("valid recipe target", {type = "unlock-recipe", recipe = "iron-gear-wheel"})
  expect_invalid("missing recipe target", {type = "unlock-recipe", recipe = "mir-missing-recipe"})
  expect_valid("valid planet space-location target", {type = "unlock-space-location", space_location = "nauvis"})
  expect_invalid("missing space-location target", {
    type = "unlock-space-location", space_location = "mir-missing-space-location"
  })
  expect_valid("valid unlock quality", {type = "unlock-quality", quality = "normal"})
  expect_invalid("missing unlock quality", {type = "unlock-quality", quality = "mir-missing-quality"})
  expect_valid("valid turret entity", {type = "turret-attack", turret_id = "gun-turret"})
  expect_invalid("missing turret entity", {type = "turret-attack", turret_id = "mir-missing-turret"})
  expect_valid("implicit normal give-item quality", {type = "give-item", item = "iron-plate"})
  expect_invalid("missing give-item quality", {
    type = "give-item", item = "iron-plate", quality = "mir-missing-quality"
  })

  local normal = contracts.identity({type = "give-item", item = "iron-plate", quality = "normal"})
  local uncommon = contracts.identity({type = "give-item", item = "iron-plate", quality = "uncommon"})
  if normal == uncommon then error("give-item identities did not include quality") end
end
