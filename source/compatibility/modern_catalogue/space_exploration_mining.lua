-- Published MIR 4.7.20002 with Space Exploration named this four-recipe
-- manufacturing vector without K2. F200 and F210 share this small declaration;
-- F200 does not construct the separate F210 SE catalogue. K2:SE keeps its own
-- five-recipe vector. These effects concern drill manufacturing, not ore yield.
local function effect(recipe, scale)
  return {recipe = recipe, scale = scale or 1}
end

local function exact_binding(weight, recipes)
  return {family="research_mining_drill", weight=weight, recipes=recipes, include_recycling=true,
    allow_shared_input_output=true, reject_explicit_productivity_denial=true}
end

return {
  definition_overrides = {
    research_mining_drill = {
      effects = {
        effect("burner-mining-drill"),
        effect("electric-mining-drill", 0.5),
        effect("area-mining-drill", 0.25),
        effect("se-core-miner-drill", 0.25),
      },
    },
  },
  exact_product_bindings = {
    exact_binding(1, {"burner-mining-drill"}),
    exact_binding(0.5, {"electric-mining-drill"}),
    exact_binding(0.25, {"area-mining-drill", "se-core-miner-drill"}),
  },
  exact_product_target_families = {research_mining_drill = true},
  required_product_targets = {
    research_mining_drill = {
      "area-mining-drill",
      "burner-mining-drill",
      "electric-mining-drill",
      "se-core-miner-drill",
    },
  },
}
