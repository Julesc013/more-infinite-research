if settings.startup["mir-upgrade-archetype"].value ~= "automatic-family-creation" then return end

local source = data.raw["assembling-machine"] and data.raw["assembling-machine"]["assembling-machine-2"]
if not source then error("MIR upgrade matrix requires assembling-machine-2") end

local entity = table.deepcopy(source)
entity.name = "mir-upgrade-auto-assembler"
entity.minable = {mining_time = 0.1, result = "mir-upgrade-auto-assembler"}
entity.next_upgrade = nil

data:extend({
  entity,
  {
    type = "item",
    name = "mir-upgrade-auto-assembler",
    icon = "__base__/graphics/icons/assembling-machine-2.png",
    icon_size = 64,
    subgroup = "production-machine",
    order = "zzz-mir-upgrade-auto-assembler",
    place_result = "mir-upgrade-auto-assembler",
    stack_size = 50
  },
  {
    type = "recipe",
    name = "mir-upgrade-auto-assembler-recipe",
    enabled = true,
    ingredients = {{type = "item", name = "electronic-circuit", amount = 1}},
    results = {{type = "item", name = "mir-upgrade-auto-assembler", amount = 1}},
    allow_productivity = true
  },
  {
    type = "mod-data",
    name = "more-infinite-research-compatibility-pack",
    data = {packs = {[
      "mir-upgrade-automatic-family"
    ] = {
      schema = 2,
      id = "mir-upgrade-automatic-family",
      applicability = {mods = {{id = "mir-fixture-assert-upgrade-3-1-9-to-3-2-0", version = "= 0.1.0"}}},
      aliases = {},
      exact = {includes = {}, excludes = {}},
      family_hints = {},
      science_roles = {},
      owner_claims = {},
      risk_overrides = {},
      family_authorizations = {{
        family = "assembling-machine-manufacturing",
        stream = "research_auto_assembling_machine",
        action = "generate",
        evidence = {"upgrade-matrix-automatic-family"},
        claim_boundary = "fixture-only",
        promotion_authorization_id = "mir.reviewed.upgrade-automatic-family-v1",
        trust_class = "mir-reviewed",
        provider_version = "family-rule-v3"
      }},
      candidate_seeds = {{
        recipe = "mir-upgrade-auto-assembler-recipe",
        item = "mir-upgrade-auto-assembler",
        family = "assembling-machine-manufacturing",
        stream = "research_auto_assembling_machine",
        change = 0.01,
        evidence = {"upgrade-matrix-automatic-family"}
      }},
      targets = {factorio_lines = {"2.1"}},
      evidence = {fixtures = {"upgrade-matrix-automatic-family"}, real_mod = {}},
      claim = {level = "fixture-only", public = false}
    }}}
  }
})
