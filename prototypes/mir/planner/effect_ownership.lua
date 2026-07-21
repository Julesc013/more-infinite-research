local deepcopy = require("prototypes.mir.core.deepcopy")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}

local function effects_for(row)
  if row.action == "emit" then return row.fields and row.fields.effects or {} end
  if row.action == "adopt" then return row.adoption and row.adoption.effects or {} end
  return {}
end

local function owner_name(row)
  if row.action == "adopt" then return row.adoption and row.adoption.owner or row.stream_key end
  return row.technology_name or row.stream_key
end

local function action_rank(row)
  if row.action == "adopt" then return 0 end
  return 1
end

local function source_rank(row)
  if row.source == "fixed-stream" then return 0 end
  if row.source == "family-rule" then return 2 end
  return 1
end

local function claim_less(a, b)
  local a_explicit = tonumber(a.row.spec and a.row.spec.effect_claim_priority) or 100
  local b_explicit = tonumber(b.row.spec and b.row.spec.effect_claim_priority) or 100
  if a_explicit ~= b_explicit then return a_explicit < b_explicit end
  if action_rank(a.row) ~= action_rank(b.row) then return action_rank(a.row) < action_rank(b.row) end
  if source_rank(a.row) ~= source_rank(b.row) then return source_rank(a.row) < source_rank(b.row) end
  if a.row.stream_key ~= b.row.stream_key then return a.row.stream_key < b.row.stream_key end
  if tostring(a.row.manifest_id) ~= tostring(b.row.manifest_id) then
    return tostring(a.row.manifest_id) < tostring(b.row.manifest_id)
  end
  return a.position < b.position
end

local function non_materializing_gates(identity)
  local names = {
    "target_supported", "effect_valid", "owner_conflict_free", "science_compatible",
    "lab_compatible", "prerequisites_acyclic", "loop_safe", "progression_safe",
    "migration_safe", "output_identity_safe"
  }
  local out = {}
  for _, name in ipairs(names) do
    out[name] = {
      passed = true,
      status = "not-applicable",
      evidence = {"effect-ownership:" .. tostring(identity)}
    }
  end
  return out
end

local function convert_empty_row_to_skip(row, first_identity)
  row.action = "skip"
  row.reason = "covered_by_planned_stream"
  row.gates = non_materializing_gates(first_identity)
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
  local rows = deepcopy(raw_rows or {})
  local claims_by_identity = {}
  local materializing_counts = {}

  for row_index, row in ipairs(rows) do
    local effects = effects_for(row)
    materializing_counts[row_index] = #effects
    for position, effect in ipairs(effects) do
      local identity = generation_plan.effect_identity(effect)
      if identity ~= "" then
        local claim = {
          row = row,
          row_index = row_index,
          position = position,
          effect = effect,
          identity = identity,
          owner = owner_name(row)
        }
        claims_by_identity[identity] = claims_by_identity[identity] or {}
        table.insert(claims_by_identity[identity], claim)
      end
    end
  end

  local winners, conflict_count = {}, 0
  for identity, claims in pairs(claims_by_identity) do
    table.sort(claims, claim_less)
    winners[identity] = claims[1]
    for _, claim in ipairs(claims) do
      if claim.row_index ~= claims[1].row_index then
        conflict_count = conflict_count + 1
      end
    end
  end

  for row_index, row in ipairs(rows) do
    local original = effects_for(row)
    local kept, lost, won = {}, {}, {}
    for position, effect in ipairs(original) do
      local identity = generation_plan.effect_identity(effect)
      local winner = identity ~= "" and winners[identity] or nil
      if not winner or winner.row_index == row_index then
        table.insert(kept, effect)
        if identity ~= "" and claims_by_identity[identity] and #claims_by_identity[identity] > 1 then
          table.insert(won, {identity = identity, owner = owner_name(row)})
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
