-- The current science facade admits only declared sources. These fixture packs
-- deliberately exercise competing raw recipes/unlockers, so the fixture must
-- state the approved source rather than ask the product to rank alternatives.
local catalogue = require("__more-infinite-research__.prototypes.mir.streams.registry")
local bindings = catalogue.shared.science_bindings
bindings["mir-fixture-prerequisite-science-pack"] = {
  recipe = "mir-fixture-prerequisite-science-pack",
  technology = "mir-fixture-custom-unlocker-a",
  allow_initial = false
}
bindings["mir-fixture-alternate-route-science-pack"] = {
  recipe = "mir-fixture-alternate-route-early",
  technology = "mir-fixture-z-early-route-unlocker",
  allow_initial = false
}

local anchor = data.raw.technology and data.raw.technology["worker-robots-storage-3"]
if not anchor then
  error("MIR generated prerequisite safety fixture requires worker-robots-storage-3.")
end

anchor.enabled = false

local automation_science = data.raw.technology and data.raw.technology["automation-science-pack"]
if not automation_science then
  error("MIR generated prerequisite safety fixture requires automation-science-pack technology.")
end

automation_science.enabled = false

local automation_science_recipe = data.raw.recipe and data.raw.recipe["automation-science-pack"]
if not automation_science_recipe then
  error("MIR generated prerequisite safety fixture requires automation-science-pack recipe.")
end

automation_science_recipe.enabled = true
