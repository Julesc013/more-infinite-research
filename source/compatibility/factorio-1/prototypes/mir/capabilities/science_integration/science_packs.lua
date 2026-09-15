-- Stable public facade for the decomposed science integration capability.
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
local recipe_unlock_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local technology_researchability = require("prototypes.mir.capabilities.science_integration.technology_researchability")
local pack_production_reachability = require("prototypes.mir.capabilities.science_integration.pack_production_reachability")
local science_selection_policy = require("prototypes.mir.capabilities.science_integration.science_selection_policy")

pack_production_reachability.configure({
  technology_researchability_reason = technology_researchability.reason_with_context
})
technology_researchability.configure({
  pack_production_status = pack_production_reachability.pack_production_status
})
lab_compatibility.configure({
  pack_production_status = pack_production_reachability.pack_production_status
})
science_selection_policy.configure({
  prereq_tech_for_science_pack = pack_production_reachability.prereq_tech_for_science_pack
})

local S = {
  pack_registry = pack_registry,
  lab_compatibility = lab_compatibility,
  recipe_unlock_facts = recipe_unlock_facts,
  technology_researchability = technology_researchability,
  pack_production_reachability = pack_production_reachability,
  science_selection_policy = science_selection_policy
}

S.all_lab_inputs = pack_registry.all_lab_inputs
S.science_pack_exists = pack_registry.science_pack_exists
S.pack_list_all = pack_registry.pack_list_all
S.pack_list_official = pack_registry.pack_list_official
S.is_official_science_pack = pack_registry.is_official_science_pack

S.any_lab_accepts_all = lab_compatibility.any_lab_accepts_all
S.valid_research_ingredients = lab_compatibility.valid_research_ingredients
S.best_lab_compatible_ingredients = lab_compatibility.best_lab_compatible_ingredients

S.space_age_progression_packs_for = science_selection_policy.space_age_progression_packs_for
S.official_progression_packs_for = science_selection_policy.official_progression_packs_for
S.mod_progression_packs_for = science_selection_policy.mod_progression_packs_for
S.end_game_science_pack = science_selection_policy.end_game_science_pack
S.pack_list_for_extension = science_selection_policy.pack_list_for_extension

S.pack_production_status = pack_production_reachability.pack_production_status
S.researchable_unlockers_for_recipe = pack_production_reachability.researchable_unlockers_for_recipe
S.prereq_tech_for_science_pack = pack_production_reachability.prereq_tech_for_science_pack

S.technology_researchability_reason = technology_researchability.technology_researchability_reason
S.technology_is_researchable = technology_researchability.technology_is_researchable
S.technology_is_enabled_and_reachable = technology_researchability.technology_is_enabled_and_reachable

return S
