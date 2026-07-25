local prototype = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-compatibility-pack"]
if not (prototype and prototype.data and prototype.data.packs) then
  error("MIR semantic family generation fixture is missing the compatibility-pack transport")
end

-- This scenario deliberately exercises reviewed generation. Keep its exact
-- candidate authority in the assertion mod so the shared discovery fixture
-- continues to prove that structurally inferred, unreviewed candidates fail
-- closed when provider cardinality or progression budgets are exceeded.
prototype.data.packs["semantic-family-generate-fixture"] = {
  schema = 2,
  id = "semantic-family-generate-fixture",
  applicability = {
    mods = {{id = "mir-fixture-assert-semantic-family-generate", version = "= 0.1.0"}}
  },
  aliases = {},
  exact = {
    includes = {
      {
        recipe = "assemble-theta",
        item = "opaque-fabrication-device",
        family = "assembling-machine-manufacturing",
        stream = "research_auto_assembling_machine",
        change = 0.02
      },
      {
        recipe = "assemble-zeta",
        item = "opaque-research-device",
        family = "lab-manufacturing",
        stream = "research_auto_lab",
        change = 0.02
      }
    },
    excludes = {}
  },
  family_hints = {},
  science_roles = {},
  owner_claims = {},
  risk_overrides = {},
  family_authorizations = {},
  candidate_seeds = {
    {
      recipe = "assemble-theta",
      item = "opaque-fabrication-device",
      family = "assembling-machine-manufacturing",
      stream = "research_auto_assembling_machine",
      change = 0.02,
      evidence = {"semantic-family-generate"}
    },
    {
      recipe = "assemble-zeta",
      item = "opaque-research-device",
      family = "lab-manufacturing",
      stream = "research_auto_lab",
      change = 0.02,
      evidence = {"semantic-family-generate"}
    }
  },
  targets = {factorio_lines = {"2.1"}},
  evidence = {fixtures = {"semantic-family-generate"}, real_mod = {}},
  claim = {level = "fixture-only", public = false}
}
