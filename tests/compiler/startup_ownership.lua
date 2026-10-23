-- Representative foreign-owner controls; no exact reporter closure is implied.
local Context = require("prototypes.mir.pipeline.compiler_context")
local coverage = require("prototypes.mir.policy.native_effect_coverage")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local original = science.technology_is_researchable
local expected = {type = "laboratory-speed", modifier = 0.1}
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function world(effect)
  data.raw = {technology = {
    ["foreign-infinite-61"] = {name = "foreign-infinite-61", type = "technology",
      max_level = "infinite", unit = {count_formula = "100*L", ingredients = {{"unknown-pack", 1}}},
      effects = {effect}}
  }}
end
science.technology_is_researchable = function(name)
  error("unresolved-owner-binding:" .. name)
end
world({type = "mining-drill-productivity-bonus", modifier = 0.1})
Context.with_active(Context.new(), function()
  check(#coverage.identity_owner_names(expected) == 0,
    "An unrelated unresolved infinite technology never enters identity-owner qualification")
  check(#coverage.exact_owner_names(expected) == 0,
    "An unrelated unresolved infinite technology never enters exact-owner qualification")
end)
world(expected)
Context.with_active(Context.new(), function()
  for _, method in ipairs({coverage.identity_owner_names, coverage.exact_owner_names}) do
    local ok, reason = pcall(method, expected)
    check(not ok and tostring(reason):find("unresolved-owner-binding:foreign-infinite-61", 1, true),
      "A genuinely matching unresolved owner keeps its binding failure")
  end
end)
science.technology_is_researchable = function() return true end
Context.with_active(Context.new(), function()
  check(coverage.identity_owner_names(expected)[1] == "foreign-infinite-61",
    "A matching reachable foreign owner remains the owner")
  check(coverage.exact_owner_names(expected)[1] == "foreign-infinite-61",
    "An exact reachable foreign owner remains the owner")
end)
data.raw.technology["foreign-infinite-61"].enabled = false
Context.with_active(Context.new(), function()
  check(#coverage.identity_owner_names(expected) == 0 and #coverage.exact_owner_names(expected) == 0,
    "A disabled foreign owner never supplies coverage")
end)
science.technology_is_researchable = original
return checks
