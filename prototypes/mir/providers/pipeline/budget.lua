local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local decision = require("prototypes.mir.providers.pipeline.decision")

local M = {}

local function count(rows, predicate)
  local total = 0
  for _, row in ipairs(rows or {}) do if predicate(row) then total = total + 1 end end
  return total
end

function M.apply(rows, limits, candidate_count, scope, hard_blockers)
  limits = limits or {}
  local attachment_count = count(rows, function(row) return row.final_state == "attach" end)
  local new_count = count(rows, function(row)
    return row.final_state == "attach" and row.promotion_class == "new-unreviewed"
  end)
  local review_count = count(rows, function(row) return row.final_state == "review-required" end)
  local retained_count = attachment_count - new_count
  -- Growth is meaningful only against a retained reviewed/released baseline;
  -- first discovery is governed by the absolute and new-member budgets.
  local growth_percent = retained_count == 0 and 0 or (new_count * 100 / retained_count)
  local semantic_clusters = {}
  for _, row in ipairs(rows) do if row.item then semantic_clusters[row.item] = true end end
  local semantic_cluster_count = 0
  for _ in pairs(semantic_clusters) do semantic_cluster_count = semantic_cluster_count + 1 end
  local reasons = {}
  local function exceeds(value, maximum, reason)
    if maximum ~= nil and value > maximum then table.insert(reasons, reason) end
  end
  exceeds(candidate_count, limits.maximum_candidates, "provider_candidate_cardinality_exceeded")
  exceeds(attachment_count, limits.maximum_attachments, "provider_attachment_cardinality_exceeded")
  exceeds(review_count, limits.maximum_review_required, "provider_review_cardinality_exceeded")
  exceeds(new_count, limits.maximum_new_attachments, "provider_new_attachment_budget_exceeded")
  exceeds(new_count, limits.maximum_unreviewed, "provider_unreviewed_budget_exceeded")
  exceeds(growth_percent, limits.maximum_growth_percent, "provider_growth_percent_budget_exceeded")
  exceeds(semantic_cluster_count, limits.maximum_semantic_clusters, "provider_semantic_cluster_budget_exceeded")
  exceeds(1, limits.maximum_progression_span, "provider_progression_span_budget_exceeded")
  local budget = {
    schema = 2,
    scope = deepcopy(scope or {}),
    candidate_count = candidate_count,
    attachment_count = attachment_count,
    new_unreviewed_count = new_count,
    retained_reviewed_or_promoted_count = retained_count,
    growth_percent = growth_percent,
    review_required_count = review_count,
    semantic_cluster_count = semantic_cluster_count,
    progression_span = 1,
    limits = deepcopy(limits),
    status = #reasons > 0 and "REVIEW_REQUIRED" or "PASS",
    reasons = reasons
  }
  budget.cardinality_fingerprint = fingerprint.of(budget)
  for _, row in ipairs(rows) do
    if budget.status == "REVIEW_REQUIRED" and row.promotion_class == "new-unreviewed"
      and row.final_state == "attach" and not hard_blockers[row.blocker] then
      row.final_state = "review-required"
      row.decision = "review-required"
      row.blocker = reasons[1]
      row.risk_disposition = "REVIEW_REQUIRED"
    end
    row.cardinality = deepcopy(budget)
    decision.refresh_fingerprint(row)
  end
  return budget
end

return M
