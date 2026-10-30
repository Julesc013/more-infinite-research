-- Finite F200 Space Age + BobTech contract. These rows bind only the named
-- 2.0.77 Bob/Angel tuple from the independent published capture: 23 science
-- vectors, its direct prerequisite witnesses, and 247 named recipe effects.
-- They do not reconstruct a foreign technology tree or scan for a profile.
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local M = {}

local function effect(recipe, scale)
  return {recipe=recipe, scale=scale or 1}
end

-- This is a fixed captured F200 profile list, not a productivity-eligibility
-- discovery pass. Its named rows include the independently captured
-- acid-neutralisation and fish-breeding routes even though those foreign
-- prototypes do not advertise the generic productivity flag.
local function exact_binding(family, weight, recipes)
  return {family=family, weight=weight, recipes=recipes, include_recycling=true,
    allow_shared_input_output=true}
end

local function tuning()
  return {base_cost=8000, effect_percent=10, enabled=true, growth_factor=2,
    linear_increment=0, max_level=0, research_time=60}
end

-- Each key is a named captured vector. The selector maps only the authored
-- Base/Space Age vector identities that this profile consumes.
M.science = {
  science_bob_angel_f200_automation_logistic_chemical_military_utility_space = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "space-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production = {"automation-science-pack", "logistic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_agricultural = {"automation-science-pack", "logistic-science-pack", "agricultural-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_agricultural_cryogenic = {"automation-science-pack", "logistic-science-pack", "agricultural-science-pack", "cryogenic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_agricultural_military = {"automation-science-pack", "logistic-science-pack", "agricultural-science-pack", "military-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_agricultural_space = {"automation-science-pack", "logistic-science-pack", "agricultural-science-pack", "space-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_cryogenic = {"automation-science-pack", "logistic-science-pack", "cryogenic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_electromagnetic = {"automation-science-pack", "logistic-science-pack", "electromagnetic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_metallurgic = {"automation-science-pack", "logistic-science-pack", "metallurgic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_metallurgic_space = {"automation-science-pack", "logistic-science-pack", "metallurgic-science-pack", "space-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_military_agricultural = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "agricultural-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_military_electromagnetic = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "electromagnetic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_military_metallurgic_space = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "metallurgic-science-pack", "space-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_military_space = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "space-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_military_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "bob-advanced-logistic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_space = {"automation-science-pack", "logistic-science-pack", "space-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_space_agricultural = {"automation-science-pack", "logistic-science-pack", "space-science-pack", "agricultural-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_space_cryogenic = {"automation-science-pack", "logistic-science-pack", "space-science-pack", "cryogenic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_utility_military_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "bob-advanced-logistic-science-pack"},
  science_bob_angel_f200_automation_logistic_chemical_production_utility_space = {"automation-science-pack", "logistic-science-pack", "bob-advanced-logistic-science-pack", "space-science-pack"},
  science_bob_angel_f200_utility_military_agricultural = {"military-science-pack", "agricultural-science-pack"},
  science_bob_angel_f200_utility_military_agricultural_cryogenic = {"military-science-pack", "agricultural-science-pack", "cryogenic-science-pack"},
  science_bob_angel_f200_utility_military_agricultural_electromagnetic = {"military-science-pack", "agricultural-science-pack", "electromagnetic-science-pack"},
}

M.science_rewrites = {
  science_automation_logistic_chemical_production = "science_bob_angel_f200_automation_logistic_chemical_production",
  science_automation_logistic_chemical_production_agricultural = "science_bob_angel_f200_automation_logistic_chemical_production_agricultural",
  science_automation_logistic_chemical_production_agricultural_cryogenic = "science_bob_angel_f200_automation_logistic_chemical_production_agricultural_cryogenic",
  science_automation_logistic_chemical_production_agricultural_military = "science_bob_angel_f200_automation_logistic_chemical_production_agricultural_military",
  science_automation_logistic_chemical_production_agricultural_space = "science_bob_angel_f200_automation_logistic_chemical_production_agricultural_space",
  science_automation_logistic_chemical_production_cryogenic = "science_bob_angel_f200_automation_logistic_chemical_production_cryogenic",
  science_automation_logistic_chemical_production_electromagnetic = "science_bob_angel_f200_automation_logistic_chemical_production_electromagnetic",
  science_automation_logistic_chemical_production_metallurgic = "science_bob_angel_f200_automation_logistic_chemical_production_metallurgic",
  science_automation_logistic_chemical_production_metallurgic_space = "science_bob_angel_f200_automation_logistic_chemical_production_metallurgic_space",
  science_automation_logistic_chemical_production_military_agricultural = "science_bob_angel_f200_automation_logistic_chemical_production_military_agricultural",
  science_automation_logistic_chemical_production_military_electromagnetic = "science_bob_angel_f200_automation_logistic_chemical_production_military_electromagnetic",
  science_automation_logistic_chemical_production_military_metallurgic_space = "science_bob_angel_f200_automation_logistic_chemical_production_military_metallurgic_space",
  science_automation_logistic_chemical_production_military_space = "science_bob_angel_f200_automation_logistic_chemical_production_military_space",
  science_automation_logistic_chemical_production_military_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium = "science_bob_angel_f200_automation_logistic_chemical_production_military_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium",
  science_automation_logistic_chemical_production_space = "science_bob_angel_f200_automation_logistic_chemical_production_space",
  science_automation_logistic_chemical_production_space_agricultural = "science_bob_angel_f200_automation_logistic_chemical_production_space_agricultural",
  science_automation_logistic_chemical_production_space_cryogenic = "science_bob_angel_f200_automation_logistic_chemical_production_space_cryogenic",
  science_utility_military_agricultural = "science_bob_angel_f200_utility_military_agricultural",
  science_utility_military_agricultural_cryogenic = "science_bob_angel_f200_utility_military_agricultural_cryogenic",
  science_utility_military_agricultural_electromagnetic = "science_bob_angel_f200_utility_military_agricultural_electromagnetic",
}

M.water_prerequisites = {
  research_bullets=true, research_character_crafting_speed=true, research_character_mining_speed=true,
  research_character_reach=true, research_character_walking_speed=true,
  research_flamethrower_shooting_speed=true, research_grenades=true, research_heavy_ammo=true,
  research_inventory_capacity=true, research_rocket_shooting_speed=true, research_rockets=true,
  research_science_pack_productivity=true, research_walls=true,
}

M.omit = {research_oil_cracking_productivity=true}

M.additions = {
  -- The retained F200 setting descriptor exposes a five-percent default, while
  -- the published combined row applies its independently captured two-percent
  -- armor route. Keep that profile-local ratio explicit rather than changing
  -- the shared setting identity or its declared default.
  {key="research_armor_components", family="research_armor_components", kind="productivity", science="science_automation_logistic_chemical_production_military_metallurgic_space", prerequisites={"automation-science-pack", "logistic-science-pack", "military-science-pack", "metallurgic-science-pack", "space-science-pack"}, effects={effect("bob-mech-armor-plate", 0.4)}, icon="__base__/graphics/technology/power-armor.png", icon_size=256, overlay=OVERLAY, localised_name={"technology-name.more-infinite-research.research_armor_components", {"technology-name.power-armor"}}, localised_description={"technology-description.more-infinite-research.recipe_productivity"}, order="p[research_armor_components]", tuning=tuning(), setting_order="b-100-armor-component-productivity-stream-research_armor_components-"},
  {key="research_plastic", family="research_plastic", kind="productivity", science="science_automation_logistic_chemical_production_agricultural", prerequisites={"automation-science-pack", "logistic-science-pack", "agricultural-science-pack"}, effects={effect("angels-solid-plastic")}, icon="__space-age__/graphics/technology/plastics-productivity.png", icon_size=256, overlay=OVERLAY, localised_name={"technology-name.more-infinite-research.research_plastic", {"item-name.plastic-bar"}}, localised_description={"technology-description.more-infinite-research.recipe_productivity"}, order="p[research_plastic]", tuning=tuning(), setting_order="b-100-plastic-productivity-stream-research_plastic-"},
  {key="research_steel", family="research_steel", kind="productivity", science="science_automation_logistic_chemical_production", prerequisites={"automation-science-pack", "logistic-science-pack"}, effects={effect("angels-plate-steel"), effect("angels-plate-steel-2")}, icon="__space-age__/graphics/technology/steel-plate-productivity.png", icon_size=256, overlay=OVERLAY, localised_name={"technology-name.more-infinite-research.research_steel", {"item-name.steel-plate"}}, localised_description={"technology-description.more-infinite-research.recipe_productivity"}, order="p[research_steel]", tuning=tuning(), setting_order="b-100-steel-plate-productivity-stream-research_steel-"},
}

-- Finite published presentation references, never an icon lookup policy.
M.definition_overrides = {
  research_advanced_circuit={icon="__bobelectronics__/graphics/icons/technology/advanced-electronics.png", icon_size=128},
  research_copper={icon="__angelssmeltinggraphics__/graphics/icons/plate-copper.png", icon_size=32},
  research_copper_cable={icon="__angelssmeltinggraphics__/graphics/icons/wire-copper.png", icon_size=32},
  research_inserters={icon="__boblogistics__/graphics/icons/technology/long-inserters.png", icon_size=128},
  research_iron={icon="__angelssmeltinggraphics__/graphics/icons/plate-iron.png", icon_size=32},
  research_iron_sticks={icon="__angelssmeltinggraphics__/graphics/icons/rod-iron.png", icon_size=32},
  research_mining_drill={icon="__bobmining__/graphics/icons/electric-mining-drill-1.png", icon_size=64, localised_name={"technology-name.more-infinite-research.research_mining_drill", {"item-name.electric-mining-drill"}}},
  research_sulfuric_acid_productivity={icons={{icon="__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-base.png", icon_size=330, scale=0.09696969696969697, shift={3.5,0}, tint={a=0.7,b=0.25,g=0.25,r=0.25}}, {icon="__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-top.png", icon_size=330, scale=0.09696969696969697, shift={3.5,0}, tint={a=1,b=0.18823529411764706,g=1,r=1}}, {icon="__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-mid.png", icon_size=330, scale=0.09696969696969697, shift={3.5,0}, tint={a=1,b=0.9529411764705882,g=0.9529411764705882,r=0.9529411764705882}}, {icon="__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-bot.png", icon_size=330, scale=0.09696969696969697, shift={3.5,0}, tint={a=1,b=0.04313725490196079,g=0.04313725490196079,r=0.7764705882352941}}, {icon="__angelspetrochemgraphics__/graphics/icons/molecules/sulfuric-acid.png", icon_size=72, scale=0.20833333333333334, shift={-10,-10}}, {icon=OVERLAY, icon_size=128, scale=0.5, shift={50,50}, floating=true}}},
  research_tungsten={icon="__angelssmeltinggraphics__/graphics/icons/plate-tungsten.png", icon_size=32},
  research_walls={localised_name={"technology-name.more-infinite-research.research_walls", {"item-name.stone-wall"}}},
}

M.continuation_overrides = {
  braking_force={science="science_bob_angel_f200_automation_logistic_chemical_production_utility_space"},
  laser_shooting_speed={science="science_bob_angel_f200_automation_logistic_chemical_military_utility_space", effects={{type="gun-speed", ammo_category="laser", scale=1}, {type="gun-speed", ammo_category="bob-laser-rifle", scale=1}}},
  research_speed={science="science_bob_angel_f200_automation_logistic_chemical_production_utility_military_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium"},
  weapon_shooting_speed={science="science_bob_angel_f200_automation_logistic_chemical_military_utility_space"},
}

local INSERTER_EFFECT_ORDER = {
  "burner-inserter", "inserter", "fast-inserter", "long-handed-inserter",
  "bob-express-bulk-inserter", "bob-red-bulk-inserter", "bob-turbo-bulk-inserter", "bulk-inserter",
  "stack-inserter", "bob-express-inserter", "bob-steam-inserter", "bob-turbo-inserter",
}

-- The bounded collector remains responsible for admission and effect values.
-- This captured profile retains one non-lexical published presentation order
-- within equal-weight inserter routes, so reorder only the already-admitted
-- generated row after exact identity/multiplicity checks.
function M.apply_effect_order(technologies)
  local target
  for _, technology in ipairs(technologies or {}) do
    if technology.name == "recipe-prod-research_inserters-1" then
      if target ~= nil then error("MIR F200 combined Bob/Angel has duplicate inserter technology", 2) end
      target = technology
    end
  end
  if type(target) ~= "table" or type(target.effects) ~= "table" then
    error("MIR F200 combined Bob/Angel lacks inserted inserter effects", 2)
  end
  local by_recipe = {}
  for _, row in ipairs(target.effects) do
    if type(row) ~= "table" or row.type ~= "change-recipe-productivity" or type(row.recipe) ~= "string"
      or by_recipe[row.recipe] ~= nil then
      error("MIR F200 combined Bob/Angel inserter effects changed", 2)
    end
    by_recipe[row.recipe] = row
  end
  local ordered = {}
  for index, recipe in ipairs(INSERTER_EFFECT_ORDER) do
    if by_recipe[recipe] == nil then error("MIR F200 combined Bob/Angel missing inserter route " .. recipe, 2) end
    ordered[index], by_recipe[recipe] = by_recipe[recipe], nil
  end
  if next(by_recipe) ~= nil then error("MIR F200 combined Bob/Angel has unexpected inserter route", 2) end
  target.effects = ordered
end

-- The direct Space Age rows stay owned by their existing renderer. The
-- combined profile replaces only its two independently captured science
-- vectors; it neither changes the scripted runtime effects nor generalises a
-- Space Age selector.
function M.scripted_effect_bindings()
  return {
    agriculture={prerequisites={"automation-science-pack", "logistic-science-pack", "agricultural-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack"}, ingredients={{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"agricultural-science-pack", 1}, {"electromagnetic-science-pack", 1}, {"cryogenic-science-pack", 1}}},
    spoilage={prerequisites={"automation-science-pack", "logistic-science-pack", "space-science-pack", "agricultural-science-pack", "cryogenic-science-pack"}, ingredients={{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"space-science-pack", 1}, {"agricultural-science-pack", 1}, {"cryogenic-science-pack", 1}}},
  }
end

-- Static product witnesses from the published capture. The existing bounded
-- collector validates these exact names before Generator publication.
local PRODUCT_BINDINGS = {
  exact_binding("research_advanced_circuit",1,{"advanced-circuit"}), exact_binding("research_armor_components",0.4,{"bob-mech-armor-plate"}),
  exact_binding("research_artificial_soil",1,{"artificial-jellynut-soil","artificial-yumako-soil"}), exact_binding("research_artificial_soil",0.5,{"overgrowth-jellynut-soil","overgrowth-yumako-soil"}),
  exact_binding("research_bacteria_cultivation",1,{"copper-bacteria-cultivation","iron-bacteria-cultivation"}), exact_binding("research_batteries",1,{"battery"}),
  exact_binding("research_belts",1,{"splitter","transport-belt","underground-belt"}), exact_binding("research_belts",0.5,{"fast-splitter","fast-transport-belt","fast-underground-belt"}), exact_binding("research_belts",0.2,{"express-splitter","express-transport-belt","express-underground-belt"}), exact_binding("research_belts",0.1,{"turbo-splitter","turbo-transport-belt","turbo-underground-belt"}), exact_binding("research_belts",0.05,{"bob-basic-splitter","bob-basic-transport-belt","bob-basic-underground-belt","bob-ultimate-splitter","bob-ultimate-transport-belt","bob-ultimate-underground-belt"}),
  exact_binding("research_bioflux",1,{"bioflux"}), exact_binding("research_breeding",1,{"angels-alien-fish-0-raw","angels-biter-big-breeding","angels-biter-medium-breeding","angels-biter-small-breeding","angels-puffer-breeding-12","angels-puffer-breeding-13","angels-puffer-breeding-14","angels-puffer-breeding-15","angels-puffer-breeding-23","biter-egg","fish-breeding","pentapod-egg"}),
  exact_binding("research_bullets",1,{"bob-better-shotgun-shell","bob-bullet-magazine","firearm-magazine","shotgun-shell"}), exact_binding("research_bullets",0.5,{"bob-ap-bullet-magazine","bob-shotgun-ap-shell","piercing-rounds-magazine","piercing-shotgun-shell"}), exact_binding("research_bullets",0.2,{"bob-shotgun-uranium-shell","uranium-rounds-magazine"}), exact_binding("research_bullets",0.1,{"bob-acid-bullet-magazine","bob-electric-bullet-magazine","bob-flame-bullet-magazine","bob-he-bullet-magazine","bob-plasma-bullet-magazine","bob-poison-bullet-magazine","bob-shotgun-acid-shell","bob-shotgun-electric-shell","bob-shotgun-explosive-shell","bob-shotgun-flame-shell","bob-shotgun-plasma-shell","bob-shotgun-poison-shell"}),
  exact_binding("research_capture_robot_rockets",1,{"capture-robot-rocket"}), exact_binding("research_carbon",0.5,{"burnt-spoilage"}), exact_binding("research_carbon",0.2,{"coal-synthesis"}), exact_binding("research_carbon_fiber",1,{"carbon-fiber"}),
  exact_binding("research_concrete",1,{"stone-brick"}), exact_binding("research_concrete",0.5,{"angels-concrete","concrete","concrete-from-molten-iron","hazard-concrete"}), exact_binding("research_concrete",0.2,{"refined-concrete","refined-hazard-concrete"}),
  exact_binding("research_copper",1,{"angels-plate-copper","angels-plate-copper-2","casting-copper","copper-plate"}), exact_binding("research_copper_cable",1,{"angels-wire-copper-2","casting-copper-cable","copper-cable"}),
  exact_binding("research_electric_energy",1,{"accumulator","solar-panel"}), exact_binding("research_electric_engine",1,{"electric-engine-unit"}), exact_binding("research_electronic_circuit",1,{"electronic-circuit"}), exact_binding("research_engine",1,{"engine-unit"}), exact_binding("research_explosives",1,{"angels-solid-nitroglycerin","angels-solid-trinitrotoluene","explosives"}), exact_binding("research_flying_robot_frame",1,{"flying-robot-frame"}),
  exact_binding("research_furnace",2,{"stone-furnace"}), exact_binding("research_furnace",1,{"steel-furnace"}), exact_binding("research_furnace",0.5,{"electric-furnace"}), exact_binding("research_furnace",0.2,{"foundry"}), exact_binding("research_gears",1,{"casting-iron-gear-wheel","iron-gear-wheel"}),
  exact_binding("research_grenades",1,{"grenade"}), exact_binding("research_grenades",0.5,{"cluster-grenade"}), exact_binding("research_heavy_ammo",1,{"cannon-shell"}), exact_binding("research_heavy_ammo",0.5,{"explosive-cannon-shell"}), exact_binding("research_heavy_ammo",0.2,{"explosive-uranium-cannon-shell","uranium-cannon-shell"}), exact_binding("research_heavy_ammo",0.1,{"artillery-shell","bob-atomic-artillery-shell","bob-distractor-artillery-shell","bob-explosive-artillery-shell","bob-fire-artillery-shell","bob-poison-artillery-shell","bob-scatter-cannon-shell","railgun-ammo"}),
  exact_binding("research_holmium",1,{"holmium-plate"}), exact_binding("research_ice",1,{"ammoniacal-solution-separation"}),
  exact_binding("research_inserters",1,{"burner-inserter","inserter"}), exact_binding("research_inserters",0.5,{"fast-inserter","long-handed-inserter"}), exact_binding("research_inserters",0.2,{"bob-express-bulk-inserter","bob-red-bulk-inserter","bob-turbo-bulk-inserter","bulk-inserter"}), exact_binding("research_inserters",0.1,{"bob-express-inserter","bob-steam-inserter","bob-turbo-inserter","stack-inserter"}),
  exact_binding("research_iron",1,{"angels-plate-iron","angels-plate-iron-2","casting-iron","iron-plate"}), exact_binding("research_iron_sticks",1,{"casting-iron-stick","iron-stick"}), exact_binding("research_landfill",1,{"angels-solid-mud-landfill","landfill"}), exact_binding("research_landfill",0.5,{"foundation"}), exact_binding("research_lithium",1,{"lithium-plate"}), exact_binding("research_lithium",0.5,{"lithium"}), exact_binding("research_lubricant_productivity",1,{"angels-liquid-fish-oil-refining","angels-mineral-oil-lubricant","biolubricant"}),
  exact_binding("research_mining_drill",2,{"burner-mining-drill"}), exact_binding("research_mining_drill",1,{"electric-mining-drill"}), exact_binding("research_mining_drill",0.5,{"big-mining-drill"}), exact_binding("research_mining_drill",0.25,{"bob-steam-mining-drill"}),
  exact_binding("research_modules",1,{"angels-bio-yield-module","bob-pollution-clean-module-1","bob-pollution-create-module-1","efficiency-module","productivity-module","quality-module","speed-module"}), exact_binding("research_modules",0.5,{"angels-bio-yield-module-2","bob-pollution-clean-module-2","bob-pollution-create-module-2","efficiency-module-2","productivity-module-2","quality-module-2","speed-module-2"}), exact_binding("research_modules",0.2,{"angels-bio-yield-module-3","bob-pollution-clean-module-3","bob-pollution-create-module-3","efficiency-module-3","productivity-module-3","quality-module-3","speed-module-3"}), exact_binding("research_modules",0.1,{"angels-bio-yield-module-4","angels-bio-yield-module-5","bob-efficiency-module-4","bob-efficiency-module-5","bob-pollution-clean-module-4","bob-pollution-clean-module-5","bob-pollution-create-module-4","bob-pollution-create-module-5","bob-productivity-module-4","bob-productivity-module-5","bob-quality-module-4","bob-quality-module-5","bob-speed-module-4","bob-speed-module-5"}),
  exact_binding("research_molten_metals",1,{"molten-copper-from-lava","molten-iron-from-lava"}), exact_binding("research_nutrients",1,{"nutrients-from-bioflux","nutrients-from-biter-egg","nutrients-from-yumako-mash"}), exact_binding("research_oil_processing_productivity",1,{"simple-coal-liquefaction"}), exact_binding("research_plastic",1,{"angels-solid-plastic"}), exact_binding("research_platform",1,{"ice-platform"}), exact_binding("research_platform",0.5,{"space-platform-foundation"}), exact_binding("research_quantum_processor",1,{"quantum-processor"}), exact_binding("research_rails",1,{"rail"}), exact_binding("research_rails",0.5,{"rail-support"}), exact_binding("research_rails",0.2,{"rail-ramp"}),
  exact_binding("research_rockets",1,{"bob-rocket","rocket"}), exact_binding("research_rockets",0.5,{"bob-explosive-rocket","explosive-rocket"}), exact_binding("research_rockets",0.2,{"angels-atomic-bomb","angels-atomic-bomb-2","atomic-bomb"}), exact_binding("research_rockets",0.1,{"bob-acid-rocket","bob-electric-rocket","bob-flame-rocket","bob-piercing-rocket","bob-plasma-rocket","bob-poison-rocket"}),
  exact_binding("research_science_pack_productivity",1,{"agricultural-science-pack","angels-desert-garden-a","angels-desert-garden-cultivating-a","angels-swamp-garden-a","angels-swamp-garden-cultivating-a","angels-temperate-garden-a","angels-temperate-garden-cultivating-a","automation-science-pack","bob-advanced-logistic-science-pack","bob-alien-science-pack","bob-alien-science-pack-blue","bob-alien-science-pack-green","bob-alien-science-pack-orange","bob-alien-science-pack-purple","bob-alien-science-pack-red","bob-alien-science-pack-yellow","bob-science-pack-gold","chemical-science-pack","cryogenic-science-pack","electromagnetic-science-pack","logistic-science-pack","metallurgic-science-pack","military-science-pack","production-science-pack","promethium-science-pack","space-science-pack","utility-science-pack"}),
  exact_binding("research_steel",1,{"angels-plate-steel","angels-plate-steel-2"}), exact_binding("research_sulfur",1,{"angels-solid-sodium-sulfate-separation","angels-solid-sulfur","angels-yellow-waste-water-purification","biosulfur"}), exact_binding("research_sulfuric_acid_productivity",1,{"acid-neutralisation","angels-liquid-sulfuric-acid"}), exact_binding("research_supercapacitor",1,{"supercapacitor"}), exact_binding("research_superconductor",1,{"superconductor"}), exact_binding("research_thruster_fuel_productivity",1,{"advanced-thruster-fuel","thruster-fuel"}), exact_binding("research_thruster_oxidizer_productivity",1,{"advanced-thruster-oxidizer","thruster-oxidizer"}), exact_binding("research_tungsten",1,{"angels-plate-tungsten","tungsten-carbide"}), exact_binding("research_walls",1,{"stone-wall"}), exact_binding("research_walls",0.5,{"gate"}),
}

local PRODUCT_FAMILIES = {}
for _, binding in ipairs(PRODUCT_BINDINGS) do PRODUCT_FAMILIES[binding.family] = true end

function M.product_bindings()
  local out = {}
  for index, binding in ipairs(PRODUCT_BINDINGS) do
    local recipes = {}
    for recipe_index, recipe in ipairs(binding.recipes) do recipes[recipe_index] = recipe end
    out[index] = exact_binding(binding.family, binding.weight, recipes)
  end
  return out
end

function M.required_product_targets()
  local out = {}
  for _, binding in ipairs(PRODUCT_BINDINGS) do
    local recipes = out[binding.family] or {}
    out[binding.family] = recipes
    for _, recipe in ipairs(binding.recipes) do recipes[#recipes + 1] = recipe end
  end
  for _, recipes in pairs(out) do table.sort(recipes) end
  return out
end

function M.exact_product_target_families()
  local out = {}; for family in pairs(PRODUCT_FAMILIES) do out[family] = true end; return out
end

function M.replacement_product_target_families()
  local out = {}
  for family in pairs(PRODUCT_FAMILIES) do
    -- These three authored F200 bodies already carry the published baseline
    -- order and scale. The exact collector admits only their named additional
    -- routes without reordering the retained effects.
    if family ~= "research_furnace" and family ~= "research_inserters" and family ~= "research_mining_drill" then out[family] = true end
  end
  return out
end

local REQUIRED_TECHNOLOGIES = {"bob-tankotron", "braking-force-6", "braking-force-7", "laser-shooting-speed-6", "laser-shooting-speed-7", "research-speed-5", "research-speed-6", "weapon-shooting-speed-5", "weapon-shooting-speed-6"}
local REQUIRED_LABS = {"lab", "biolab", "bob-lab-2", "bob-lab-alien"}

local function require_table(group, name, label)
  local row = type(group) == "table" and group[name] or nil
  if type(row) ~= "table" then error("MIR F200 combined Bob/Angel preflight missing " .. label .. " " .. name, 3) end
  return row
end

local function has_recipe_product(recipe, name)
  for _, result in ipairs(recipe.results or {}) do
    if type(result) == "table" and (result.type == nil or result.type == "item") and result.name == name then return true end
  end
  return false
end

local function contains(values, name)
  for _, value in ipairs(values or {}) do if value == name then return true end end
  return false
end

function M.preflight(raw)
  if type(raw) ~= "table" then error("MIR F200 combined Bob/Angel preflight requires data.raw", 2) end
  for _, binding in ipairs(PRODUCT_BINDINGS) do
    for _, name in ipairs(binding.recipes) do require_table(raw.recipe, name, "recipe") end
  end
  for _, name in ipairs(REQUIRED_TECHNOLOGIES) do require_table(raw.technology, name, "technology") end
  for _, name in ipairs(REQUIRED_LABS) do
    local lab = require_table(raw.lab, name, "lab")
    if type(lab.inputs) ~= "table" then error("MIR F200 combined Bob/Angel preflight lab inputs changed: " .. name, 2) end
  end
  local armor = raw.recipe["bob-mech-armor-plate"]
  if armor.enabled ~= false or armor.allow_productivity ~= true or not has_recipe_product(armor, "bob-mech-armor-plate") then error("MIR F200 combined Bob/Angel preflight armor route changed", 2) end
  local tankotron, unlocked = raw.technology["bob-tankotron"], false
  for _, effect_row in ipairs(tankotron.effects or {}) do
    if type(effect_row) == "table" and effect_row.type == "unlock-recipe" and effect_row.recipe == "bob-mech-armor-plate" then unlocked = true end
  end
  if not unlocked or not contains(tankotron.prerequisites, "bob-tungsten-processing") then error("MIR F200 combined Bob/Angel preflight armor owner changed", 2) end
end

return M
