local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function claim_material(row)
  return {
    schema = 1,
    subject = {prototype_type = row.prototype_type, prototype_name = row.prototype_name},
    recipe = row.recipe,
    item = row.item,
    target_stream = row.target_stream,
    candidate_family = row.candidate_family,
    semantic_partition = row.partition_key,
    effect = {type = "change-recipe-productivity", change = row.change},
    action = row.final_state,
    policy = {
      scope = row.policy_scope,
      promotion_class = row.promotion_class,
      compatibility_pack = row.compatibility_pack,
      target_support = row.target_support
    },
    evidence = row.evidence,
    risk = {
      fingerprint = row.risk_fingerprint,
      hard_flags = row.risk_hard_flags,
      review_flags = row.risk_review_flags,
      disposition = row.risk_disposition
    }
  }
end

function M.fingerprint(row)
  return fingerprint.of(claim_material(row))
end

function M.bind(row)
  row.claim_fingerprint = M.fingerprint(row)
  return row
end

function M.arbitrate(claims)
  local rows = deepcopy(claims or {})
  table.sort(rows, function(left, right)
    if left.claim_fingerprint ~= right.claim_fingerprint then
      return left.claim_fingerprint < right.claim_fingerprint
    end
    if left.provider_id ~= right.provider_id then return left.provider_id < right.provider_id end
    return left.decision_fingerprint < right.decision_fingerprint
  end)
  local streams, claim_fingerprints = {}, {}
  for _, row in ipairs(rows) do
    if row.claim_fingerprint ~= M.fingerprint(row) then error("Provider claim fingerprint is invalid.", 2) end
    streams[row.target_stream] = true
    claim_fingerprints[row.claim_fingerprint] = true
  end
  local stream_count, fingerprint_count = 0, 0
  for _ in pairs(streams) do stream_count = stream_count + 1 end
  for _ in pairs(claim_fingerprints) do fingerprint_count = fingerprint_count + 1 end
  if stream_count > 1 then return {status = "REVIEW_REQUIRED", code = "ambiguous_family_attachment", claims = rows} end
  if fingerprint_count > 1 then
    return {status = "REVIEW_REQUIRED", code = "conflicting_same_stream_claim", claims = rows}
  end
  local providers, evidence, decisions = {}, {}, {}
  for _, row in ipairs(rows) do
    table.insert(providers, row.provider_id)
    table.insert(evidence, deepcopy(row.evidence))
    table.insert(decisions, row.decision_fingerprint)
  end
  table.sort(providers)
  table.sort(decisions)
  local first = rows[1]
  return {
    status = "PASS",
    claims = rows,
    attachment = {
      recipe = first.recipe,
      change = first.change,
      rule = first.rule,
      provider_id = providers[1],
      provider_ids = providers,
      provider_evidence = evidence,
      target_stream = first.target_stream,
      risk_fingerprint = first.risk_fingerprint,
      claim_fingerprint = first.claim_fingerprint,
      decision_fingerprint = first.decision_fingerprint,
      duplicate_decision_fingerprints = decisions
    }
  }
end

return M
