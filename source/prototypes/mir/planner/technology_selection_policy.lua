local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local ACTION_RANK = {adopt = 10, emit = 20, diagnose = 90}

local function deferred_rejected_primary(candidate, row)
  local evaluation = candidate.diagnostic_evaluation or {}
  if row.action ~= "skip" or evaluation.state ~= "deferred-initial-skip-rejected-primary"
    or evaluation.selection_key ~= candidate.selection_key
    or evaluation.reason ~= row.reason then
    return nil
  end
  for _, alternative in ipairs(candidate.alternatives or {}) do
    if alternative.alternative_id == evaluation.primary_alternative_id
      and alternative.action == "reject"
      and alternative.disposition == "rejected"
      and alternative.qualification_decision == "rejected"
      and alternative.design_fingerprint == evaluation.primary_design_fingerprint
      and alternative.qualification_fingerprint == evaluation.primary_qualification_fingerprint then
      return alternative, evaluation
    end
  end
  return nil
end

local function selected_alternative(candidate, requested_action, allow_proposals)
  local qualified = {}
  for _, alternative in ipairs(candidate.alternatives or {}) do
    if alternative.qualification_decision == "qualified"
      or (allow_proposals and alternative.qualification_decision == "proposal") then
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

local function select(catalog, rows, allow_proposals)
  local rows_by_key = {}
  for _, row in ipairs(rows or {}) do
    rows_by_key[tostring(row.stream_key) .. ":" .. tostring(row.manifest_id or row.stream_key)] = row
  end
  local selections = {}
  -- Selection records are constructed locally. The only value copied from a
  -- planning row is reason; record whether it is scalar so the catalog can
  -- safely reuse the fingerprint captured before this function's defensive
  -- selection copy. Non-scalar reasons retain the existing returned-copy hash.
  local returned_copy_equivalent = true
  for _, candidate in ipairs(catalog.candidates or {}) do
    local row = rows_by_key[candidate.selection_key]
    if not row then error("SelectionPolicy candidate lacks a planning row: " .. candidate.selection_key, 2) end
    local requested = (row.action == "emit" or row.action == "adopt") and row.action or "diagnose"
    local selected = selected_alternative(candidate, requested, allow_proposals)
    local deferred_rejection
    if not selected then selected, deferred_rejection = deferred_rejected_primary(candidate, row) end
    if not selected then error("SelectionPolicy candidate has no qualified alternative: " .. candidate.candidate_id, 2) end
    -- Read once at the original selection-construction boundary. A foreign row
    -- may have a metatable, so do not add a second __index observation.
    local reason = row.reason
    if reason ~= nil and type(reason) ~= "string" then returned_copy_equivalent = false end
    local selection = {
      selection_key = candidate.selection_key,
      candidate_id = candidate.candidate_id,
      alternative_id = selected.alternative_id,
      action = selected.action,
      reason = reason,
      design_fingerprint = selected.design_fingerprint,
      qualification_fingerprint = selected.qualification_fingerprint,
      policy = "stable-owner-promoted-diagnostic-v1"
    }
    if deferred_rejection then
      selection.deferred_rejection = {
        state = deferred_rejection.state,
        selection_key = deferred_rejection.selection_key,
        reason = deferred_rejection.reason,
        primary_alternative_id = deferred_rejection.primary_alternative_id,
        primary_design_fingerprint = deferred_rejection.primary_design_fingerprint,
        primary_qualification_fingerprint = deferred_rejection.primary_qualification_fingerprint
      }
    end
    table.insert(selections, selection)
  end
  table.sort(selections, function(left, right) return left.candidate_id < right.candidate_id end)
  return deepcopy(selections), fingerprint.of(selections), returned_copy_equivalent
end

function M.select_prequalification(catalog, rows)
  return select(catalog, rows, true)
end

function M.select_final(catalog, rows)
  return select(catalog, rows, false)
end

function M.select(catalog, rows)
  -- Preserve all results from the chosen producer: the catalog consumes the
  -- first defensive copy and, when safe, its companion fingerprint.
  if catalog.phase == "final" then return M.select_final(catalog, rows) end
  return M.select_prequalification(catalog, rows)
end

function M.assert_generation_projection(selections, rows)
  local by_key = {}
  for _, selection in ipairs(selections or {}) do by_key[selection.selection_key] = selection end
  for _, row in ipairs(rows or {}) do
    local key = tostring(row.stream_key) .. ":" .. tostring(row.manifest_id or row.stream_key)
    local selection = by_key[key]
    if not selection then error("SelectionPolicy projection lacks a selection: " .. key, 2) end
    local projected = (selection.action == "diagnose" or selection.action == "reject")
      and "skip" or selection.action
    if projected ~= row.action then
      error("SelectionPolicy projection differs from GenerationPlan: " .. key
        .. " selected=" .. tostring(selection.action) .. " row=" .. tostring(row.action), 2)
    end
    if row.technology_design and selection.design_fingerprint ~= row.technology_design.design_fingerprint
      and row.action ~= "skip" then
      error("SelectionPolicy design differs from GenerationPlan: " .. key, 2)
    end
    if selection.action == "reject" and (row.action ~= "skip"
      or type(selection.deferred_rejection) ~= "table"
      or selection.deferred_rejection.selection_key ~= key
      or selection.deferred_rejection.reason ~= row.reason) then
      error("SelectionPolicy deferred rejection differs from GenerationPlan: " .. key, 2)
    end
  end
  local row_count = #(rows or {})
  if #selections ~= row_count then
    error("SelectionPolicy selection count differs from GenerationPlan.", 2)
  end
  return true
end

function M.assert_compilation_projection(selections, rows, operations)
  local operation_by_stream = {}
  for _, operation in ipairs(operations or {}) do
    if operation.stream_key then
      if operation_by_stream[operation.stream_key] then
        error("SelectionPolicy compilation projection has duplicate stream operation: " .. operation.stream_key, 2)
      end
      operation_by_stream[operation.stream_key] = operation
    end
  end
  for _, row in ipairs(rows or {}) do
    local operation = operation_by_stream[row.stream_key]
    if row.action == "emit" or row.action == "adopt" then
      if not operation or not row.technology_design
        or not operation.technology_design
        or operation.technology_design.design_fingerprint ~= row.technology_design.design_fingerprint then
        error("SelectionPolicy compilation projection differs for stream: " .. tostring(row.stream_key), 2)
      end
    elseif operation then
      error("SelectionPolicy rejected row reached CompilationPlan: " .. tostring(row.stream_key), 2)
    end
  end
  return true
end

return M
