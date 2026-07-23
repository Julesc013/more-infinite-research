local operator_dsl = require("prototypes.mir.families.operator_dsl")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_risk_facts = require("prototypes.mir.index.recipe_risk_facts")

local M = {}

function M.evaluate(rule, candidate)
  local fact = recipe_facts.view(candidate.recipe)
  local risk_fact = recipe_risk_facts.view(candidate.recipe)
  local risk_disposition, risk_blocker = recipe_risk_facts.primary_disposition(risk_fact)
  local eligible, blocker = operator_dsl.eligibility(rule.operators, fact, candidate.item, risk_fact)
  if risk_disposition ~= "PASS" then blocker = risk_blocker; eligible = false end
  return {
    fact = fact,
    risk_fact = risk_fact,
    risk_disposition = risk_disposition,
    risk_blocker = risk_blocker,
    eligible = eligible,
    blocker = blocker
  }
end

return M
