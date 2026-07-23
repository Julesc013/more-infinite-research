local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local ACTION_RANK = {adopt = 10, emit = 20, diagnose = 90}

local function selected_alternative(candidate, requested_action)
  local qualified = {}
  for _, alternative in ipairs(candidate.alternatives or {}) do
    if alternative.qualification_decision == "qualified" or alternative.qualification_decision == "proposal" then
      table.insert(qualified, alternative)
    end
  end
  table.sort(qualified, function(left, right)
    local left_requested = left.action == requested_action and 0 or 1
    local right_requested = right.action == requested_action and 0 or 1
    if left_requested ~= right_requested then return left_requested < right_requested end
    local left_rank, right_rank = ACTION_RANK[left.action] or 1000, ACTION_RANK[right.action] or 1000
    if left_rank ~= right_rank then return left_rank < right_rank end
    return left.alternative_id < right.alternative_id
  end)
  return qualified[1]
end

function M.select(catalog, rows)
  local rows_by_key = {}
  for _, row in ipairs(rows or {}) do
    rows_by_key[tostring(row.stream_key) .. ":" .. tostring(row.manifest_id or row.stream_key)] = row
  end
  local selections = {}
  for _, candidate in ipairs(catalog.candidates or {}) do
    local row = rows_by_key[candidate.selection_key]
    if not row then error("SelectionPolicy candidate lacks a planning row: " .. candidate.selection_key, 2) end
    local requested = (row.action == "emit" or row.action == "adopt") and row.action or "diagnose"
    local selected = selected_alternative(candidate, requested)
    if not selected then error("SelectionPolicy candidate has no qualified alternative: " .. candidate.candidate_id, 2) end
    table.insert(selections, {
      selection_key = candidate.selection_key,
      candidate_id = candidate.candidate_id,
      alternative_id = selected.alternative_id,
      action = selected.action,
      reason = row.reason,
      design_fingerprint = selected.design_fingerprint,
      qualification_fingerprint = selected.qualification_fingerprint,
      policy = "stable-owner-promoted-diagnostic-v1"
    })
  end
  table.sort(selections, function(left, right) return left.candidate_id < right.candidate_id end)
  return deepcopy(selections), fingerprint.of(selections)
end

function M.assert_generation_projection(selections, rows)
  local by_key = {}
  for _, selection in ipairs(selections or {}) do by_key[selection.selection_key] = selection end
  for _, row in ipairs(rows or {}) do
    local key = tostring(row.stream_key) .. ":" .. tostring(row.manifest_id or row.stream_key)
    local selection = by_key[key]
    if not selection then error("SelectionPolicy projection lacks a selection: " .. key, 2) end
    local projected = selection.action == "diagnose" and "skip" or selection.action
    if projected ~= row.action then
      error("SelectionPolicy projection differs from GenerationPlan: " .. key
        .. " selected=" .. tostring(selection.action) .. " row=" .. tostring(row.action), 2)
    end
  end
  return true
end

return M
