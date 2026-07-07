local C = require("prototypes.mir.streams.registry")
local deepcopy = require("prototypes.mir.core.deepcopy")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local recipes = require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")
local icons = require("prototypes.mir.emit.icon_builder")
local costs = require("prototypes.mir.planner.costs")
local prerequisites = require("prototypes.mir.planner.prerequisites")

local U = {}

U.item_prototype = lookup.item_prototype
U.fluid_prototype = lookup.fluid_prototype
U.technology_exists = lookup.technology_exists
U.ammo_category_exists = lookup.ammo_category_exists
U.is_space_age = lookup.is_space_age
U.mod_exists = lookup.mod_exists

U.all_lab_inputs = science.all_lab_inputs
U.science_pack_exists = science.science_pack_exists
U.any_lab_accepts_all = science.any_lab_accepts_all
U.valid_research_ingredients = science.valid_research_ingredients
U.best_lab_compatible_ingredients = science.best_lab_compatible_ingredients
U.pack_list_all = science.pack_list_all
U.pack_list_official = science.pack_list_official
U.is_official_science_pack = science.is_official_science_pack
U.space_age_progression_packs_for = science.space_age_progression_packs_for
U.official_progression_packs_for = science.official_progression_packs_for
U.mod_progression_packs_for = science.mod_progression_packs_for
U.pack_list_for_extension = science.pack_list_for_extension
U.prereq_tech_for_science_pack = science.prereq_tech_for_science_pack
U.end_game_science_pack = science.end_game_science_pack

U.apply_science_pack_ingredient_policy = science_selector.apply_science_pack_ingredient_policy
U.pick_science_for_stream = science_selector.pick_science_for_stream

U.icons_for_stream = icons.icons_for_stream
U.effect_icons_for_stream = icons.effect_icons_for_stream
U.matches_stream_recipe_filter = recipes.matches_stream_recipe_filter

U.enabled_for = costs.enabled_for
U.base_cost_for = costs.base_cost_for
U.growth_factor_for = costs.growth_factor_for
U.research_time_for = costs.research_time_for
U.max_level_for = costs.max_level_for

U.build_prereqs_for = prerequisites.build_for
U.append_end_game_gate_prerequisite = prerequisites.append_end_game_gate_prerequisite

function U.recipes_for_stream(spec)
  return recipes.recipes_for_stream(spec, C.shared.per_level_default)
end

function U.deepcopy(value)
  return deepcopy(value)
end

return U
