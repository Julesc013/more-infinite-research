-- Explicit product groups recovered from the published MIR 4 productivity
-- declarations.  These are data-only binding facts for product_targets; no
-- historical stream loader or prototype discovery is imported here.
--
-- `weight` is group.change / the canonical family default below, so it
-- multiplies the current family effect-percent.  Bindings remain in published group order: product_targets
-- admits the first matching group for a family after that group passes its own
-- exclusions.  Unsupported selector forms are recorded below rather than
-- approximated through wider product matching.
local M = {
  schema = 1,
  first_admitted_group = "declaration-order",
  default_flags = {
    include_hidden = false,
    include_recycling = false,
    allow_shared_input_output = false,
    reject_explicit_productivity_denial = false,
  },
  -- Historical settings and the published Base/SA oracle use 20% for only
  -- these two families. Every other binding in this file uses the 10% default.
  canonical_effect_percent = {
    research_furnace = 0.20,
    research_mining_drill = 0.20,
  },

  base = {
    bindings = {
      {family = "research_copper", weight = 1, products = {{type = "item", name = "copper-plate"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_iron", weight = 1, products = {{type = "item", name = "iron-plate"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_steel", weight = 1, products = {{type = "item", name = "steel-plate"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_gears", weight = 1, products = {{type = "item", name = "iron-gear-wheel"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_iron_sticks", weight = 1, products = {{type = "item", name = "iron-stick"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_copper_cable", weight = 1, products = {{type = "item", name = "copper-cable"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_electronic_circuit", weight = 1, products = {{type = "item", name = "electronic-circuit"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_advanced_circuit", weight = 1, products = {{type = "item", name = "advanced-circuit"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_processing_unit", weight = 1, products = {{type = "item", name = "processing-unit"}}},
      {family = "research_plastic", weight = 1, products = {{type = "item", name = "plastic-bar"}}},
      {family = "research_sulfur", weight = 1, products = {{type = "item", name = "sulfur"}}, exclude_ingredient_patterns = {"asteroid"}},
      {family = "research_batteries", weight = 1, products = {{type = "item", name = "battery"}}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_explosives", weight = 1, products = {{type = "item", name = "explosives"}}},
      {family = "research_engine", weight = 1, products = {{type = "item", name = "engine-unit"}}},
      {family = "research_electric_engine", weight = 1, products = {{type = "item", name = "electric-engine-unit"}}},
      {family = "research_flying_robot_frame", weight = 1, products = {{type = "item", name = "flying-robot-frame"}}},
      {family = "research_low_density_structure", weight = 1, products = {{type = "item", name = "low-density-structure"}}},
      {family = "research_rocket_fuel", weight = 1, products = {{type = "item", name = "rocket-fuel"}}},
      {family = "research_lubricant_productivity", weight = 1, products = {{type = "fluid", name = "lubricant"}}, exclude_recipe_patterns = {"^empty%-.*%-barrel$"}},

      {family = "research_grenades", weight = 1, products = {{type = "item", name = "grenade"}}},
      {family = "research_grenades", weight = 0.5, products = {{type = "item", name = "cluster-grenade"}}},
      {family = "research_walls", weight = 1, products = {{type = "item", name = "stone-wall"}}},
      {family = "research_walls", weight = 0.5, products = {{type = "item", name = "gate"}}},
      {family = "research_landfill", weight = 1, products = {{type = "item", name = "landfill"}}, exclude_recipe_patterns = {"^atan%-landfill%-from%-ash$", "^atan%-foundation%-from%-ash$"}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_landfill", weight = 0.5, products = {{type = "item", name = "foundation"}}, exclude_recipe_patterns = {"^atan%-landfill%-from%-ash$", "^atan%-foundation%-from%-ash$"}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_rails", weight = 1, products = {{type = "item", name = "rail"}}},
      {family = "research_rails", weight = 0.5, products = {{type = "item", name = "rail-support"}}},
      {family = "research_rails", weight = 0.2, products = {{type = "item", name = "rail-ramp"}}},
      {family = "research_concrete", weight = 1, products = {{type = "item", name = "stone-brick"}}, exclude_recipe_patterns = {"^atan%-stone%-brick%-from%-ash$"}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_concrete", weight = 0.5, products = {{type = "item", name = "concrete"}, {type = "item", name = "hazard-concrete"}}, exclude_recipe_patterns = {"^atan%-stone%-brick%-from%-ash$"}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_concrete", weight = 0.2, products = {{type = "item", name = "refined-concrete"}, {type = "item", name = "refined-hazard-concrete"}}, exclude_recipe_patterns = {"^atan%-stone%-brick%-from%-ash$"}, exclude_ingredient_patterns = {"scrap"}},
      {family = "research_furnace", weight = 1, products = {{type = "item", name = "stone-furnace"}}},
      {family = "research_furnace", weight = 0.5, products = {{type = "item", name = "steel-furnace"}}},
      {family = "research_furnace", weight = 0.25, products = {{type = "item", name = "electric-furnace"}}},
      {family = "research_furnace", weight = 0.1, products = {{type = "item", name = "foundry"}, {type = "item", name = "industrial-furnace"}}},
      {family = "research_mining_drill", weight = 1, products = {{type = "item", name = "burner-mining-drill"}}},
      {family = "research_mining_drill", weight = 0.5, products = {{type = "item", name = "electric-mining-drill"}}},
      {family = "research_mining_drill", weight = 0.25, products = {{type = "item", name = "big-mining-drill"}}},
      {family = "research_electric_energy", weight = 1, products = {{type = "item", name = "solar-panel"}, {type = "item", name = "accumulator"}}},
      {family = "research_electric_energy", weight = 0.5, products = {{type = "item", name = "advanced-solar"}, {type = "item", name = "advanced-accumulator"}, {type = "item", name = "se-space-solar-panel"}, {type = "item", name = "se-space-accumulator"}, {type = "item", name = "solar-matrix"}, {type = "item", name = "accumulator-v2"}}},
      {family = "research_electric_energy", weight = 0.2, products = {{type = "item", name = "elite-solar"}, {type = "item", name = "elite-accumulator"}, {type = "item", name = "se-space-solar-panel-2"}, {type = "item", name = "se-space-accumulator-2"}}},
      {family = "research_electric_energy", weight = 0.1, products = {{type = "item", name = "ultimate-solar"}, {type = "item", name = "ultimate-accumulator"}, {type = "item", name = "se-space-solar-panel-3"}}},
      {family = "research_bullets", weight = 1, products = {{type = "item", name = "firearm-magazine"}, {type = "item", name = "shotgun-shell"}, {type = "item", name = "bob-bullet-magazine"}, {type = "item", name = "bob-better-shotgun-shell"}}},
      {family = "research_bullets", weight = 0.5, products = {{type = "item", name = "piercing-rounds-magazine"}, {type = "item", name = "piercing-shotgun-shell"}, {type = "item", name = "bob-ap-bullet-magazine"}, {type = "item", name = "bob-shotgun-ap-shell"}}},
      {family = "research_bullets", weight = 0.2, products = {{type = "item", name = "uranium-rounds-magazine"}, {type = "item", name = "uranium-shotgun-shell"}, {type = "item", name = "bob-shotgun-uranium-shell"}}},
      {family = "research_bullets", weight = 0.1, products = {{type = "item", name = "bob-he-bullet-magazine"}, {type = "item", name = "bob-flame-bullet-magazine"}, {type = "item", name = "bob-acid-bullet-magazine"}, {type = "item", name = "bob-poison-bullet-magazine"}, {type = "item", name = "bob-electric-bullet-magazine"}, {type = "item", name = "bob-plasma-bullet-magazine"}, {type = "item", name = "bob-shotgun-electric-shell"}, {type = "item", name = "bob-shotgun-explosive-shell"}, {type = "item", name = "bob-shotgun-flame-shell"}, {type = "item", name = "bob-shotgun-acid-shell"}, {type = "item", name = "bob-shotgun-poison-shell"}, {type = "item", name = "bob-shotgun-plasma-shell"}}},
      {family = "research_heavy_ammo", weight = 1, products = {{type = "item", name = "cannon-shell"}}},
      {family = "research_heavy_ammo", weight = 0.5, products = {{type = "item", name = "explosive-cannon-shell"}}},
      {family = "research_heavy_ammo", weight = 0.2, products = {{type = "item", name = "uranium-cannon-shell"}, {type = "item", name = "explosive-uranium-cannon-shell"}}},
      {family = "research_heavy_ammo", weight = 0.1, products = {{type = "item", name = "artillery-shell"}, {type = "item", name = "railgun-ammo"}, {type = "item", name = "bob-scatter-cannon-shell"}, {type = "item", name = "bob-poison-artillery-shell"}, {type = "item", name = "bob-fire-artillery-shell"}, {type = "item", name = "bob-explosive-artillery-shell"}, {type = "item", name = "bob-distractor-artillery-shell"}, {type = "item", name = "bob-atomic-artillery-shell"}}},
      {family = "research_rockets", weight = 1, products = {{type = "item", name = "rocket"}, {type = "item", name = "bob-rocket"}}},
      {family = "research_rockets", weight = 0.5, products = {{type = "item", name = "explosive-rocket"}, {type = "item", name = "bob-explosive-rocket"}}},
      {family = "research_rockets", weight = 0.2, products = {{type = "item", name = "atomic-bomb"}}},
      {family = "research_rockets", weight = 0.1, products = {{type = "item", name = "plutonium-bomb"}, {type = "item", name = "bob-piercing-rocket"}, {type = "item", name = "bob-electric-rocket"}, {type = "item", name = "bob-acid-rocket"}, {type = "item", name = "bob-flame-rocket"}, {type = "item", name = "bob-poison-rocket"}, {type = "item", name = "bob-plasma-rocket"}}},
      {family = "research_belts", weight = 1, products = {{type = "item", name = "transport-belt"}, {type = "item", name = "underground-belt"}, {type = "item", name = "splitter"}, {type = "item", name = "loader"}, {type = "item", name = "aai-loader"}, {type = "item", name = "basic-loader"}}},
      {family = "research_belts", weight = 0.5, products = {{type = "item", name = "fast-transport-belt"}, {type = "item", name = "fast-underground-belt"}, {type = "item", name = "fast-splitter"}, {type = "item", name = "fast-loader"}, {type = "item", name = "aai-fast-loader"}}},
      {family = "research_belts", weight = 0.2, products = {{type = "item", name = "express-transport-belt"}, {type = "item", name = "express-underground-belt"}, {type = "item", name = "express-splitter"}, {type = "item", name = "express-loader"}, {type = "item", name = "aai-express-loader"}}},
      {family = "research_belts", weight = 0.1, products = {{type = "item", name = "turbo-transport-belt"}, {type = "item", name = "turbo-underground-belt"}, {type = "item", name = "turbo-splitter"}, {type = "item", name = "turbo-loader"}, {type = "item", name = "aai-turbo-loader"}}},
      {family = "research_belts", weight = 0.05, products = {{type = "item", name = "hyper-transport-belt"}, {type = "item", name = "hyper-underground-belt"}, {type = "item", name = "hyper-splitter"}, {type = "item", name = "hyper-loader"}, {type = "item", name = "aai-hyper-loader"}}},
      {family = "research_inserters", weight = 1, products = {{type = "item", name = "inserter"}, {type = "item", name = "burner-inserter"}}},
      {family = "research_inserters", weight = 0.5, products = {{type = "item", name = "fast-inserter"}, {type = "item", name = "long-handed-inserter"}}},
      {family = "research_inserters", weight = 0.2, products = {{type = "item", name = "bulk-inserter"}}},
      {family = "research_inserters", weight = 0.1, products = {{type = "item", name = "stack-inserter"}}},
    },
    unsupported = {
      {family = "research_explosives", selector = "item_patterns:^bio%-explosives$", disposition = "literal explosives binding retained; pattern route is not approximated"},
      {family = "research_sulfuric_acid_productivity", selector = "recipe_patterns acid-neutralisation/acid-neutralization", disposition = "omitted: a fluid-only binding would widen the published recipe allowlist"},
      {family = "research_oil_processing_productivity", selector = "recipe_patterns", disposition = "omitted: no typed product declaration"},
      {family = "research_oil_cracking_productivity", selector = "recipe_patterns", disposition = "omitted: no typed product declaration"},
      {family = "research_furnace", selector = "item_patterns:^foundry$", disposition = "literal products retained; pattern-only route unrepresented"},
      {family = "research_mining_drill", selector = "item_patterns", disposition = "literal products retained; pattern routes unrepresented"},
      {family = "research_bullets", selector = "item_patterns", disposition = "literal products retained; pattern routes unrepresented"},
      {family = "research_heavy_ammo", selector = "item_patterns", disposition = "literal products retained; pattern routes unrepresented"},
      {family = "research_rockets", selector = "item_patterns", disposition = "literal products retained; pattern routes unrepresented"},
      {family = "research_belts", selector = "item_patterns/place_result_entity_types structural fallback", disposition = "literal products retained; pattern and structural routes unrepresented"},
      {family = "research_inserters", selector = "item_patterns/place_result_entity_types structural fallback", disposition = "literal products retained; pattern and structural routes unrepresented"},
    },
  },

  space_age = {
    bindings = {
      {family = "research_bioflux", weight = 1, products = {{type = "item", name = "bioflux"}}},
      {family = "research_carbon_fiber", weight = 1, products = {{type = "item", name = "carbon-fiber"}}},
      {family = "research_holmium", weight = 1, products = {{type = "item", name = "holmium-plate"}}},
      {family = "research_lithium", weight = 1, products = {{type = "item", name = "lithium-plate"}}},
      {family = "research_platform", weight = 1, products = {{type = "item", name = "ice-platform"}}},
      {family = "research_platform", weight = 0.5, products = {{type = "item", name = "space-platform-foundation"}}},
      {family = "research_quantum_processor", weight = 1, products = {{type = "item", name = "quantum-processor"}}},
      {family = "research_science_pack_productivity", weight = 1, reject_explicit_productivity_denial = true, products = {{type = "item", name = "automation-science-pack"}, {type = "item", name = "logistic-science-pack"}, {type = "item", name = "chemical-science-pack"}, {type = "item", name = "production-science-pack"}, {type = "item", name = "military-science-pack"}, {type = "item", name = "utility-science-pack"}, {type = "item", name = "space-science-pack"}, {type = "item", name = "agricultural-science-pack"}, {type = "item", name = "metallurgic-science-pack"}, {type = "item", name = "electromagnetic-science-pack"}, {type = "item", name = "cryogenic-science-pack"}, {type = "item", name = "promethium-science-pack"}}},
      {family = "research_supercapacitor", weight = 1, products = {{type = "item", name = "supercapacitor"}}},
      {family = "research_superconductor", weight = 1, products = {{type = "item", name = "superconductor"}}},
      {family = "research_thruster_fuel_productivity", weight = 1, products = {{type = "fluid", name = "thruster-fuel"}}, exclude_recipe_patterns = {"^empty%-.*%-barrel$"}},
      {family = "research_thruster_oxidizer_productivity", weight = 1, products = {{type = "fluid", name = "thruster-oxidizer"}}, exclude_recipe_patterns = {"^empty%-.*%-barrel$"}},
      {family = "research_tungsten", weight = 1, products = {{type = "item", name = "tungsten-plate"}, {type = "item", name = "tungsten-carbide"}}},
    },
    unsupported = {
      {family = "research_artificial_soil", selector = "item_patterns", disposition = "omitted: no literal typed product declaration"},
      {family = "research_bacteria_cultivation", selector = "recipe_patterns", disposition = "omitted: no literal typed product declaration"},
      {family = "research_breeding", selector = "by_category_or_match/name_patterns", disposition = "omitted: literal products would widen the published selector"},
      {family = "research_capture_robot_rockets", selector = "recipe_patterns", disposition = "omitted: no literal typed product declaration"},
      {family = "research_carbon", selector = "recipe_patterns", disposition = "omitted: literal carbon would widen the published allowlists"},
      {family = "research_ice", selector = "recipe_patterns", disposition = "omitted: literal ice would widen the published allowlist"},
      {family = "research_lithium", selector = "recipe_patterns:^lithium$", disposition = "literal lithium-plate binding retained; lithium route unrepresented"},
      {family = "research_molten_metals", selector = "recipe_patterns", disposition = "omitted: no literal typed product declaration"},
      {family = "research_nutrients", selector = "recipe_patterns", disposition = "omitted: no literal typed product declaration"},
    },
  },
}

-- Module tiers are a native item-class contract. Index that class once when
-- the authored module family exists, then share the ordinary product pass.
-- No recipe-name convention, technology discovery or module-effect guess.
function M.module_tier_bindings(modules)
  local groups = {}
  for index, weight in ipairs({1, 0.5, 0.2, 0.1}) do
    groups[index] = {family="research_modules", weight=weight, products={}}
  end
  local visited = 0
  for name, prototype in pairs(modules or {}) do
    visited = visited + 1
    local tier = type(prototype) == "table" and prototype.tier
    if type(name) == "string" and name ~= "" and type(tier) == "number"
      and tier > 0 and tier < math.huge and tier % 1 == 0 then
      local products = groups[math.min(4, tier)].products
      products[#products + 1] = {type="item", name=name}
    end
  end
  local out = {}
  for _, group in ipairs(groups) do
    if #group.products > 0 then out[#out + 1] = group end
  end
  return out, visited
end

return M
