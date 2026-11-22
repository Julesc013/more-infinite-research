local M = {}

local function saved_levels(progress)
  return type(progress) == "number" and progress > 0 and 1 or 0
end

function M.invested_count(queued, progress)
  -- The saved fraction belongs to the first queued occurrence if present.
  return math.max(queued, saved_levels(progress))
end

function M.remaining_after_cancellation(pending, cancelled, progress)
  -- Cancelling queue entries can leave one invested level in native storage.
  -- Keep that existing obligation without granting a new one.
  return math.max(pending - cancelled, math.min(pending, saved_levels(progress)))
end

return M
