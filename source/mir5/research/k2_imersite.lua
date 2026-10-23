-- Shared, immutable K2SO Imersite identity contract. Runtime consumes only this
-- bounded metadata; data-stage construction remains in research.modern.
return {
  schema = 1,
  profile = "k2so-f210",
  storage_key = "mir_k2_imersite_state",
  stream = "research_material_imersite",
  effect = {type = "change-recipe-productivity", recipe = "kr-imersite-powder", change = 0.02},
  early = {
    id = "recipe-prod-research_material_imersite-1",
    family = "research_material_imersite",
    first_level = 1,
    last_level = 3,
    order = "p[research_material_imersite]",
  },
  continuation = {
    id = "recipe-prod-research_material_imersite-4",
    family = "research_material_imersite__continuation",
    first_level = 4,
    order = "p[research_material_imersite__continuation]",
  },
  carriers = {
    {
      id = "mir-k2-imersite-staged-state-1",
      source_id = "recipe-prod-research_material_imersite-1",
      initial_level = 1,
      kind = "early",
    },
    {
      id = "mir-k2-imersite-continuation-state-4",
      source_id = "recipe-prod-research_material_imersite-4",
      initial_level = 4,
      kind = "continuation",
    },
  },
}
