local generation_plan = require("prototypes.mir.planner.generation_plan")
local technology_effects = require("prototypes.mir.integrity.technology_effects")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")
local ownership_facts = require("prototypes.mir.planner.effect_ownership.facts")

local M = {}

function M.admit_stream_artifact(stream_artifact)
  for _, row in ipairs(stream_artifact.rows or {}) do
    hard_gate_authority.assert_total(row.gates)
    for _, gate in pairs(row.gates) do
      if gate_contract.is_trusted(gate) then gate_contract.assert_trusted(gate)
      else gate_contract.verify_untrusted(gate) end
    end
    if row.technology_design then
      if technology_design.is_trusted(row.technology_design) then
        technology_design.assert_trusted(row.technology_design)
      else
        technology_design.verify_untrusted(row.technology_design)
      end
    end
  end
  return stream_artifact
end

function M.operations(operations)
  local technology_names, manifest_ids, effects, effect_values = {}, {}, {}, {}
  local planned_overlaps = {}
  local material_stage_overlaps = {}
  local weapon_speed_overlaps = {}
  for _, operation in ipairs(operations) do
    if operation.operation == "emit_stream" or operation.operation == "emit_base_extension" then
      if technology_names[operation.technology_name] then
        error("CompilationPlan contains technology-name collision: " .. operation.technology_name, 2)
      end
      technology_names[operation.technology_name] = operation.operation
      if manifest_ids[operation.manifest_id] then
        error("CompilationPlan contains manifest collision: " .. operation.manifest_id, 2)
      end
      manifest_ids[operation.manifest_id] = operation.operation
    end
  end

  for _, operation in ipairs(operations) do
    if operation.stage_kind == "material-continuation"
        and technology_names[operation.staged_parent_technology] ~= "emit_stream" then
      error("CompilationPlan material continuation lacks its generated legacy owner: "
        .. tostring(operation.technology_name), 2)
    end
  end

  for _, operation in ipairs(operations) do
    local expected_effects = operation.effects or (operation.technology and operation.technology.effects) or {}
    technology_effects.assert_effects_allowed(expected_effects, "CompilationPlan " .. tostring(operation.technology_name))
    for _, effect in ipairs(expected_effects) do
      local identity = generation_plan.effect_identity(effect)
      if identity ~= "" then
        if effects[identity] then
          if not material_stage_overlaps[identity] and ownership_facts.material_stage_pair(
              effects[identity], operation, effect_values[identity], effect) then
            material_stage_overlaps[identity] = true
            table.insert(planned_overlaps, {
              identity = identity,
              owners = {effects[identity].technology_name, operation.technology_name},
              policy = "material-stage-same-qualified-recipe"
            })
          elseif not weapon_speed_overlaps[identity]
            and ownership_facts.weapon_speed_overlap_pair(
              effects[identity], operation, effect_values[identity], effect)
            and (ownership_facts.retained_overlap(operation, identity)
              or ownership_facts.retained_overlap(effects[identity], identity)) then
            weapon_speed_overlaps[identity] = true
            table.insert(planned_overlaps, {
              identity = identity,
              owners = {effects[identity].technology_name, operation.technology_name},
              policy = "weapon-speed-overlap-retained"
            })
          else
            error("CompilationPlan contains duplicate direct-effect identity: " .. identity, 2)
          end
        end
        if not effects[identity] then
          effects[identity] = operation
          effect_values[identity] = effect
        end
      end
    end
  end
  return {
    valid = true,
    operation_count = #operations,
    technology_count = (function() local count = 0; for _ in pairs(technology_names) do count = count + 1 end; return count end)(),
    manifest_count = (function() local count = 0; for _ in pairs(manifest_ids) do count = count + 1 end; return count end)(),
    effect_count = (function() local count = 0; for _ in pairs(effects) do count = count + 1 end; return count end)(),
    planned_overlap_count = #planned_overlaps,
    planned_overlaps = planned_overlaps
  }
end

return M
