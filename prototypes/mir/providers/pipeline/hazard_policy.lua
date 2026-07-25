local M = {}

function M.resolve(classification, pack_decision, hard_blockers, blocker_is_reviewable)
  local eligible = classification.eligible
  local blocker = classification.blocker
  local disposition = classification.risk_disposition
  if pack_decision.action == "attach" and disposition ~= "HARD_REJECTED"
    and (blocker == nil or blocker_is_reviewable(blocker)) then
    eligible, blocker = true, nil
    if disposition == "REVIEW_REQUIRED" then disposition = "EXACT_REVIEWED" end
  elseif pack_decision.action == "diagnose" then
    eligible, blocker = false, pack_decision.reason or blocker
  end
  if disposition == "HARD_REJECTED" then eligible, blocker = false, classification.risk_blocker end
  if blocker and hard_blockers[blocker] then eligible = false end
  return {eligible = eligible, blocker = blocker, risk_disposition = disposition}
end

return M
