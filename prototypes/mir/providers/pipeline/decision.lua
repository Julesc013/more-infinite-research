local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function decision_fingerprint(row)
  local material = deepcopy(row)
  material.decision_fingerprint = nil
  return fingerprint.of(material)
end

function M.build(rule, stream, candidate, classification, pack_decision, change, action)
  local risk_fact = classification.risk_fact
  local promotion_class = pack_decision.kind == "exact-reviewed" and "exact-reviewed"
    or candidate.source == "compatibility-pack-seed" and "promoted"
    or "new-unreviewed"
  local row = {
    schema = 4,
    provider_id = rule.provider_id,
    rule = rule.id,
    source_key = "recipe:" .. candidate.recipe,
    prototype_type = "recipe",
    prototype_name = candidate.recipe,
    capability = rule.capability,
    candidate_family = rule.family,
    recipe = candidate.recipe,
    item = candidate.item,
    target_stream = stream,
    final_state = action,
    decision = action,
    blocker = classification.blocker or rule.blocker,
    change = change,
    policy_scope = "automatic-productivity",
    identity_seed = candidate.identity,
    candidate_fingerprint = candidate.candidate_fingerprint,
    promotion_class = promotion_class,
    diagnostic_provenance = {provider = rule.provider_id, evidence = deepcopy(rule.required_evidence)},
    target_support = deepcopy(rule.targets),
    emission = {adapter = "generation-plan-family-rule", mutates_prototypes = false},
    candidate_source = candidate.source,
    compatibility_pack = candidate.pack or pack_decision.pack,
    evidence = candidate.evidence or pack_decision.evidence,
    risk_fingerprint = risk_fact and risk_fact.risk_fingerprint or "missing",
    risk_hard_flags = deepcopy((risk_fact and risk_fact.hard_flags) or {"recipe_fact_missing"}),
    risk_review_flags = deepcopy((risk_fact and risk_fact.review_flags) or {}),
    risk_disposition = classification.risk_disposition
  }
  row.decision_fingerprint = decision_fingerprint(row)
  return row
end

function M.refresh_fingerprint(row)
  row.decision_fingerprint = decision_fingerprint(row)
  return row
end

return M
