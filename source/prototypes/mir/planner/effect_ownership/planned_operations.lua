local facts = require("prototypes.mir.planner.effect_ownership.facts")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

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
function M.resolve(raw_operations)
  local operations, claims_by_identity = {}, {}
  for operation_index, source in ipairs(raw_operations or {}) do
    local operation = facts.copy_operation_preserving_authority(source)
    operations[operation_index] = operation
    for position, effect in ipairs(facts.operation_effects(operation)) do
      local identity = facts.effect_identity(effect)
      if identity ~= "" then
        claims_by_identity[identity] = claims_by_identity[identity] or {}
        table.insert(claims_by_identity[identity], {
          operation = operation,
          operation_index = operation_index,
          position = position,
          effect = effect,
          identity = identity,
          owner = facts.operation_owner(operation)
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
      if facts.retained_overlap(claim.operation, identity) then retain = true end
    end
    if operation_count > 1 and retain then
      retained_overlap_count = retained_overlap_count + 1
    elseif operation_count > 1 then
      table.sort(claims, facts.operation_claim_less)
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
    local original, kept, lost = facts.operation_effects(operation), {}, {}
    for _, effect in ipairs(original) do
      local identity = facts.effect_identity(effect)
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
        operation.gates = facts.non_materializing_gates(lost[1].identity)
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
