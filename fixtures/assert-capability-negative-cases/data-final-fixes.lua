local denied_recipes = {
  ["mir-self-loop-filter-cleaning"] = true,
  ["mir-barrel-return-loop"] = true,
  ["mir-voiding-sink"] = true,
  ["mir-matter-transmutation"] = true,
  ["mir-zero-cap-productivity"] = true,
  ["mir-hidden-internal-recipe"] = true,
  ["mir-loader-like-container"] = true,
  ["mir-drill-like-container"] = true,
  ["mir-hidden-placeable-machine"] = true,
  ["mir-parameter-placeable-machine"] = true,
  ["mir-productivity-disabled-machine"] = true,
  ["mir-zero-cap-placeable-machine"] = true,
  ["mir-recycling-placeable-machine"] = true,
  ["mir-self-return-placeable-machine"] = true,
  ["mir-nondeterministic-placeable-machine"] = true,
  ["mir-ambiguous-placeable-machine"] = true,
  ["mir-voiding-placeable-machine"] = true,
  ["mir-matter-transmutation-placeable-machine"] = true,
  ["mir-recovery-placeable-machine"] = true
}

for tech_name, tech in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(tech.effects or {}) do
    if effect.type == "change-recipe-productivity" and denied_recipes[effect.recipe] then
      error("MIR negative capability validation failed: " .. effect.recipe .. " received productivity from " .. tech_name .. ".")
    end
  end
end

local risk_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_risk_facts")
local family_resolver = require("__more-infinite-research__.prototypes.mir.families.resolver")

local expected_hard = {
  ["mir-hidden-placeable-machine"] = "hidden_internal",
  ["mir-parameter-placeable-machine"] = "parameter_recipe",
  ["mir-productivity-disabled-machine"] = "productivity_disabled",
  ["mir-zero-cap-placeable-machine"] = "zero_productivity_cap",
  ["mir-recycling-placeable-machine"] = "recycling_loop",
  ["mir-self-return-placeable-machine"] = "catalyst_or_self_return",
  ["mir-nondeterministic-placeable-machine"] = "non_deterministic_output",
  ["mir-ambiguous-placeable-machine"] = "ambiguous_placeable_output"
}
local expected_review = {
  ["mir-voiding-placeable-machine"] = "voiding_or_destruction",
  ["mir-matter-transmutation-placeable-machine"] = "matter_or_transmutation",
  ["mir-recovery-placeable-machine"] = "cleaning_or_recovery_loop"
}

local function contains(values, expected)
  for _, value in ipairs(values or {}) do if value == expected then return true end end
  return false
end

local decisions = {}
for _, row in ipairs(family_resolver.snapshot().decisions or {}) do decisions[row.recipe] = row end
for recipe_name, expected in pairs(expected_hard) do
  local risk = risk_facts.view(recipe_name)
  local decision = decisions[recipe_name]
  if not risk or not contains(risk.hard_flags, expected)
    or not decision or decision.risk_fingerprint ~= risk.risk_fingerprint
    or decision.risk_disposition ~= "HARD_REJECTED" or decision.decision ~= "diagnose" then
    error("MIR hard RecipeRiskFact was not enforced by the family planner: " .. recipe_name .. "/" .. expected)
  end
end
for recipe_name, expected in pairs(expected_review) do
  local risk = risk_facts.view(recipe_name)
  local decision = decisions[recipe_name]
  if not risk or not contains(risk.review_flags, expected)
    or not decision or decision.risk_fingerprint ~= risk.risk_fingerprint
    or decision.risk_disposition ~= "REVIEW_REQUIRED" or decision.decision ~= "review-required" then
    error("MIR review RecipeRiskFact did not produce REVIEW_REQUIRED: " .. recipe_name .. "/" .. expected)
  end
end
