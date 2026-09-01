local deepcopy = require("prototypes.mir.core.deepcopy")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function copy_rows_preserving_gates(raw_rows)
  local rows = {}
  for index, source in ipairs(raw_rows or {}) do
    local row = {}
    for key, value in pairs(source) do
      if key == "gates" then
        row.gates = {}
        for gate_name, gate in pairs(value or {}) do row.gates[gate_name] = gate end
      else
        row[key] = deepcopy(value)
      end
    end
    rows[index] = row
  end
  return rows
end

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
    out[name] = gate_contract.not_applicable(
      "effect-ownership",
      "candidate-retains-materializing-effect",
      fingerprint.of({effect_identity = identity, gate = name}),
      {"effect-ownership:" .. tostring(identity)}
    )
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
  local rows = copy_rows_preserving_gates(raw_rows)
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

local function copy_operation_preserving_authority(source)
  local operation = {}
  for key, value in pairs(source or {}) do
    if key == "gates" then
      operation.gates = {}
      for gate_name, gate in pairs(value or {}) do operation.gates[gate_name] = gate end
    elseif key == "technology_design" then
      operation.technology_design = value
    else
      operation[key] = deepcopy(value)
    end
  end
  return operation
end

local function operation_effects(operation)
  if operation.operation == "native_owner_binding" then return operation.effects or {} end
  return (operation.technology and operation.technology.effects) or {}
end

local function operation_owner(operation)
  return operation.technology_name or operation.stream_key or operation.manifest_id
end

local function operation_rank(operation)
  if operation.operation == "native_owner_binding" then return 0 end
  if operation.operation == "emit_stream" then return 1 end
  if operation.operation == "emit_base_extension" then return 2 end
  return 3
end

local function operation_claim_less(left, right)
  local left_rank, right_rank = operation_rank(left.operation), operation_rank(right.operation)
  if left_rank ~= right_rank then return left_rank < right_rank end
  if tostring(left.operation.stream_key) ~= tostring(right.operation.stream_key) then
    return tostring(left.operation.stream_key) < tostring(right.operation.stream_key)
  end
  if tostring(left.operation.manifest_id) ~= tostring(right.operation.manifest_id) then
    return tostring(left.operation.manifest_id) < tostring(right.operation.manifest_id)
  end
  if tostring(left.operation.technology_name) ~= tostring(right.operation.technology_name) then
    return tostring(left.operation.technology_name) < tostring(right.operation.technology_name)
  end
  return left.operation_index < right.operation_index
end

local function retained_overlap(operation, identity)
  return type(operation.planned_overlap_identities) == "table"
    and operation.planned_overlap_identities[identity] == true
end

local function refresh_base_operation(operation)
  operation.technology_design = technology_design.from_base_extension_operation(operation)
  operation.technology = technology_design.prototype_projection(
    operation.technology_design, {validated = true})
  operation.technology.type = "technology"
  return operation
end

-- GenerationPlan ownership has already reconciled fixed, automatic, and
-- adopted stream rows. This second pass owns the combined CompilationPlan
-- boundary, where base continuations join those rows for the first time.
-- Same-operation duplicates deliberately remain untouched so the final
-- CompilationPlan validator continues to fail closed.
function M.resolve_operations(raw_operations)
  local operations, claims_by_identity = {}, {}
  for operation_index, source in ipairs(raw_operations or {}) do
    local operation = copy_operation_preserving_authority(source)
    operations[operation_index] = operation
    for position, effect in ipairs(operation_effects(operation)) do
      local identity = generation_plan.effect_identity(effect)
      if identity ~= "" then
        claims_by_identity[identity] = claims_by_identity[identity] or {}
        table.insert(claims_by_identity[identity], {
          operation = operation,
          operation_index = operation_index,
          position = position,
          effect = effect,
          identity = identity,
          owner = operation_owner(operation)
        })
      end
    end
  end

  local winners, decisions = {}, {}
  local conflict_count, retained_overlap_count = 0, 0
  for identity, claims in pairs(claims_by_identity) do
    local operation_indexes, operation_count, retain = {}, 0, false
    for _, claim in ipairs(claims) do
      if not operation_indexes[claim.operation_index] then
        operation_indexes[claim.operation_index] = true
        operation_count = operation_count + 1
      end
      if retained_overlap(claim.operation, identity) then retain = true end
    end
    if operation_count > 1 and retain then
      retained_overlap_count = retained_overlap_count + 1
    elseif operation_count > 1 then
      table.sort(claims, operation_claim_less)
      local winner = claims[1]
      winners[identity] = winner
      local losing_operations, losers = {}, {}
      for _, claim in ipairs(claims) do
        if claim.operation_index ~= winner.operation_index
          and not losing_operations[claim.operation_index] then
          losing_operations[claim.operation_index] = true
          conflict_count = conflict_count + 1
          table.insert(losers, {
            operation = claim.operation.operation,
            stream_key = claim.operation.stream_key,
            manifest_id = claim.operation.manifest_id,
            technology_name = claim.operation.technology_name
          })
        end
      end
      table.sort(losers, function(left, right)
        return fingerprint.canonical(left) < fingerprint.canonical(right)
      end)
      table.insert(decisions, {
        identity = identity,
        winner = {
          operation = winner.operation.operation,
          stream_key = winner.operation.stream_key,
          manifest_id = winner.operation.manifest_id,
          technology_name = winner.operation.technology_name
        },
        losers = losers
      })
    end
  end
  table.sort(decisions, function(left, right) return left.identity < right.identity end)

  local resolved, omitted = {}, {}
  for operation_index, operation in ipairs(operations) do
    local original, kept, lost = operation_effects(operation), {}, {}
    for _, effect in ipairs(original) do
      local identity = generation_plan.effect_identity(effect)
      local winner = identity ~= "" and winners[identity] or nil
      if not winner or winner.operation_index == operation_index then
        table.insert(kept, effect)
      else
        table.insert(lost, {
          identity = identity,
          recipe = effect.recipe,
          requested_change = effect.change or effect.modifier,
          winner_operation = winner.operation.operation,
          winner_stream = winner.operation.stream_key,
          winner_manifest_id = winner.operation.manifest_id,
          winner_owner = winner.owner,
          winner_change = winner.effect.change or winner.effect.modifier,
          reason = "covered_by_planned_operation"
        })
      end
    end

    if #lost > 0 then
      operation.effect_ownership = {
        schema = 1,
        policy = "combined-compilation-plan-v1",
        lost = lost,
        resolution_fingerprint = fingerprint.of({
          operation = operation.operation,
          manifest_id = operation.manifest_id,
          technology_name = operation.technology_name,
          retained_effects = kept,
          lost = lost
        })
      }
      if operation.operation ~= "emit_base_extension" then
        error("Combined CompilationPlan ownership unexpectedly changed a non-base operation: "
          .. tostring(operation.technology_name), 2)
      end
      operation.technology.effects = kept
      if #kept == 0 and #original > 0 then
        operation.gates = non_materializing_gates(lost[1].identity)
        refresh_base_operation(operation)
        table.insert(omitted, operation)
      else
        operation.gates.owner_conflict_free = gate_contract.passed(
          "effect-ownership",
          {"effect-ownership:combined-plan-resolved", operation.effect_ownership.resolution_fingerprint}
        )
        refresh_base_operation(operation)
        table.insert(resolved, operation)
      end
    else
      table.insert(resolved, operation)
    end
  end

  local omitted_projection = {}
  for _, operation in ipairs(omitted) do
    table.insert(omitted_projection, {
      operation = operation.operation,
      key = operation.key,
      stream_key = operation.stream_key,
      manifest_id = operation.manifest_id,
      technology_name = operation.technology_name,
      design_fingerprint = operation.technology_design
        and operation.technology_design.design_fingerprint,
      effect_ownership = operation.effect_ownership
    })
  end
  table.sort(omitted_projection, function(left, right)
    return fingerprint.canonical(left) < fingerprint.canonical(right)
  end)
  local summary = {
    schema = 1,
    policy = "combined-compilation-plan-v1",
    conflict_count = conflict_count,
    omitted_operation_count = #omitted,
    retained_overlap_count = retained_overlap_count,
    decisions = decisions,
    omitted_operations = omitted_projection
  }
  summary.resolution_fingerprint = fingerprint.of({
    policy = summary.policy,
    conflict_count = summary.conflict_count,
    omitted_operation_count = summary.omitted_operation_count,
    retained_overlap_count = summary.retained_overlap_count,
    decisions = summary.decisions,
    omitted_operations = summary.omitted_operations
  })
  return resolved, summary, omitted
end

return M
