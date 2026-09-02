local facts = require("prototypes.mir.planner.effect_ownership.facts")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}

local function convert_empty_row_to_skip(row, first_identity)
  row.action = "skip"
  row.reason = "covered_by_planned_stream"
  row.gates = facts.non_materializing_gates(first_identity)
  row.technology_name = nil
  row.fields = nil
  row.adoption = nil
  row.direct_effects = nil
  row.overlap_effects = nil
  row.diagnostics = row.diagnostics or {key = row.stream_key}
  row.diagnostics.status = "skipped"
  row.diagnostics.reason = row.reason
  row.diagnostics.effects = "0"
end

function M.resolve(raw_rows, options)
  options = options or {}
  local rows = facts.copy_rows_preserving_gates(raw_rows)
  local claims_by_identity = {}
  local materializing_counts = {}

  for row_index, row in ipairs(rows) do
    local effects = facts.effects_for(row)
    materializing_counts[row_index] = #effects
    for position, effect in ipairs(effects) do
      local identity = facts.effect_identity(effect)
      if identity ~= "" then
        local claim = {
          row = row,
          row_index = row_index,
          position = position,
          effect = effect,
          identity = identity,
          owner = facts.owner_name(row)
        }
        claims_by_identity[identity] = claims_by_identity[identity] or {}
        table.insert(claims_by_identity[identity], claim)
      end
    end
  end

  local winners, conflict_count = {}, 0
  for identity, claims in pairs(claims_by_identity) do
    table.sort(claims, facts.claim_less)
    winners[identity] = claims[1]
    for _, claim in ipairs(claims) do
      if claim.row_index ~= claims[1].row_index then
        conflict_count = conflict_count + 1
      end
    end
  end

  for row_index, row in ipairs(rows) do
    local original = facts.effects_for(row)
    local kept, lost, won = {}, {}, {}
    for _, effect in ipairs(original) do
      local identity = facts.effect_identity(effect)
      local winner = identity ~= "" and winners[identity] or nil
      if not winner or winner.row_index == row_index then
        table.insert(kept, effect)
        if identity ~= "" and claims_by_identity[identity] and #claims_by_identity[identity] > 1 then
          table.insert(won, {identity = identity, owner = facts.owner_name(row)})
        end
      else
        table.insert(lost, {
          identity = identity,
          recipe = effect.recipe,
          requested_change = effect.change or effect.modifier,
          winner_stream = winner.row.stream_key,
          winner_owner = winner.owner,
          winner_change = winner.effect.change or winner.effect.modifier,
          reason = "covered_by_planned_stream"
        })
      end
    end

    if #lost > 0 or #won > 0 then
      row.effect_ownership = {won = won, lost = lost}
    end
    if row.action == "emit" and row.fields then row.fields.effects = kept end
    if row.action == "adopt" and row.adoption then
      row.adoption = native_owner_contract.refresh_effects(row.adoption, kept)
    end
    if row.diagnostics and materializing_counts[row_index] > 0 then row.diagnostics.effects = tostring(#kept) end
    if row.action ~= "adopt" and materializing_counts[row_index] > 0 and #kept == 0 then
      convert_empty_row_to_skip(row, lost[1] and lost[1].identity or "none")
    end
  end

  table.sort(rows, function(a, b)
    if a.stream_key ~= b.stream_key then return a.stream_key < b.stream_key end
    if a.action ~= b.action then return a.action < b.action end
    return tostring(a.manifest_id) < tostring(b.manifest_id)
  end)
  if not options.defer_design_refresh then
    for _, row in ipairs(rows) do
      if row.action == "emit" then row.technology_design = technology_design.from_generation_row(row) end
    end
  end
  return rows, {conflict_count = conflict_count}
end

return M
