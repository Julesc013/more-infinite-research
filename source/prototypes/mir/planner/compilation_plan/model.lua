local deepcopy = require("prototypes.mir.core.deepcopy")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local technology_effects = require("prototypes.mir.integrity.technology_effects")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local compiler_input = require("prototypes.mir.domain.compiler.compiler_input")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")
local compilation_snapshot_contract = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot_adapter = require("prototypes.mir.pipeline.policy_snapshot_adapter")
local environment_adapter = require("prototypes.mir.platform.factorio.environment_identity")
local effect_target_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory")

local M = {}
local shared_planning_gates = {}

function M.shared_planning_gate(key, evaluator, evidence)
  if not shared_planning_gates[key] then
    shared_planning_gates[key] = gate_contract.passed(evaluator, evidence)
  end
  return shared_planning_gates[key]
end

local function default_base_gates(operation)
  local input_fingerprint = fingerprint.of({key = operation.key, technology_name = operation.technology_name})
  local passed = function(evaluator, evidence) return gate_contract.passed(evaluator, {evidence}) end
  return {
    target_supported = passed("target-profile", "base-continuation:target-supported"),
    effect_valid = gate_contract.pending("effect-contracts"),
    owner_conflict_free = passed("base-continuation-planner", "base-continuation:owner-free"),
    science_compatible = passed("science-selector", "base-continuation:science-resolved"),
    lab_compatible = passed("lab-compatibility", "base-continuation:lab-resolved"),
    prerequisites_acyclic = gate_contract.pending("technology-graph"),
    loop_safe = gate_contract.not_applicable(
      "base-continuation-planner", "candidate-transforms-recipe-graph", input_fingerprint,
      {"base-continuation:no-recipe-graph-transformation"}),
    progression_safe = gate_contract.pending("technology-graph"),
    migration_safe = passed("base-continuation-manifest", "base-continuation:stable-chain"),
    output_identity_safe = passed("base-continuation-planner", "base-continuation:output-absent")
  }
end

function M.default_compiler_input(stream_artifact, base_plan, sanitation_ledger)
  local policy = policy_snapshot_adapter.capture()
  local snapshot = compilation_snapshot_contract.new({
    fact_domains = {
      recipes = {}, technologies = {}, items = {}, entities = {}, labs = {}, science_packs = {}
    },
    relationship_indexes = {}, owner_index = {}, graph_input = {},
    effect_target_inventory = effect_target_inventory.capture(),
    provider_inputs = {},
    stream_inputs = {plan = stream_artifact}, base_continuation_inputs = {operations = base_plan or {}},
    source_fingerprints = deepcopy(stream_artifact.source_fingerprints or {})
  })
  local environment = environment_adapter.current({
    effective_settings = policy.effective_settings, policy_snapshot = policy})
  return compiler_input.new({
    source_fingerprints = deepcopy(stream_artifact.source_fingerprints or {}),
    compilation_snapshot = snapshot,
    policy_snapshot = policy,
    runtime_environment = environment,
    input_sanitation_fingerprint = fingerprint.of(sanitation_ledger or {})
  })
end

function M.shallow_copy(source)
  local out = {}
  for key, value in pairs(source or {}) do out[key] = value end
  return out
end

function M.derive_stream_row(source_row)
  local row = {}
  for key, value in pairs(source_row) do
    row[key] = value
  end
  row.gates = M.shallow_copy(source_row.gates)
  if source_row.fields then row.fields = M.shallow_copy(source_row.fields) end
  return row
end

function M.copy_operation_with_design_view(source_operation)
  local operation = {}
  for key, value in pairs(source_operation) do
    if key == "technology_design" or key == "gates" then operation[key] = value
    else operation[key] = deepcopy(value) end
  end
  return operation
end

function M.rebuild_stream_artifact(stream_artifact, rows, rebuild_design_by_index)
  local plan = generation_plan.new({source_fingerprints = stream_artifact.source_fingerprints})
  for index, row in ipairs(rows) do
    if not row.technology_design or (rebuild_design_by_index and rebuild_design_by_index[index]) then
      row.technology_design = technology_design.from_generation_row(row)
    end
    plan:add_owned_derived(row)
  end
  return plan:finalize():artifact_view()
end

-- Prepare a private base-continuation record for policy work.  Binding it to a
-- TechnologyDesign is deliberately separate: effect sanitation changes both
-- the technology projection and the effect gate, so binding before sanitation
-- would construct a design that no later consumer can use.
local function normalized_base_operation_structure(operation)
  local out = M.copy_operation_with_design_view(operation)
  -- An input-plan design describes the pre-sanitization candidate.  Never carry
  -- it into the mutable compilation view: final binding happens only after all
  -- remaining base decisions are known.
  out.technology_design = nil
  out.gates = {}
  for gate_name, gate in pairs(operation.gates or {}) do out.gates[gate_name] = gate end
  out.schema = 2
  out.manifest_id = out.manifest_id or ("base-extension:" .. tostring(out.key) .. ":" .. tostring(out.technology_name))
  out.registry = {kind = "base_extension", key = out.key}
  if type(out.gates) ~= "table" or next(out.gates) == nil then out.gates = default_base_gates(out) end
  hard_gate_authority.assert_total(out.gates)
  if type(out.technology) ~= "table" then
    error("TechnologyDesign base continuation operation is required.", 2)
  end
  return out
end

local function bind_base_operation_design(operation)
  operation.technology_design = technology_design.from_base_extension_operation(operation)
  operation.technology = technology_design.prototype_projection(operation.technology_design, {validated = true})
  operation.technology.type = "technology"
  return operation
end

-- Private compilation-stage view.  It owns the mutable operation structure but
-- deliberately has no TechnologyDesign until a terminal base decision needs one.
-- The source plan remains fully bound for the input snapshot and planned-candidate
-- record; this view is only used after sanitation while policy, ownership, and
-- graph decisions can still change effects or gates.
function M.owned_base_operation(operation)
  return normalized_base_operation_structure(operation)
end

function M.normalized_base_operation(operation)
  local out = M.owned_base_operation(operation)
  return bind_base_operation_design(out)
end

function M.sanitize_base_operations(base_plan, target_inventory)
  local operations, removed_count, skipped_count, rejected_candidates = {}, 0, 0, {}
  for _, source_operation in ipairs(base_plan or {}) do
    -- Sanitize the owned structural copy first, then bind exactly the final
    -- design.  The source plan's validated projection remains untouched.
    local operation = normalized_base_operation_structure(source_operation)
    local kept, removed = technology_effects.sanitize_effects(
      (operation.technology and operation.technology.effects) or {},
      "CompilationPlan " .. tostring(operation.technology_name),
      "generated",
      target_inventory
    )
    removed_count = removed_count + #removed
    if operation.technology then operation.technology.effects = kept end
    if #kept > 0 and technology_effects.has_possible_research_effects(kept) then
      operation.gates.effect_valid = gate_contract.passed(
        "effect-contracts",
        {#removed > 0 and "effect-contracts:sanitized" or "effect-contracts:all-targets-exist"}
      )
      -- The virtual graph and combined ownership resolver consume this owned
      -- structure and its gates/effects only.  Bind the complete design after
      -- their terminal decision, where the public operation is formed.
      table.insert(operations, operation)
    else
      skipped_count = skipped_count + 1
      local reason = #removed > 0 and "no_valid_effect_targets" or "no_base_extension_effects"
      local evidence = #removed > 0 and "effect-contracts:all-targets-missing"
        or "effect-contracts:no-base-effects"
      if #kept > 0 then
        reason = "zero_base_extension_effects"
        evidence = "effect-contracts:zero-base-effect-changes"
      end
      operation.gates.effect_valid = gate_contract.failed(
        "effect-contracts", reason, {evidence})
      bind_base_operation_design(operation)
      table.insert(rejected_candidates, {
        candidate_id = "base-continuation/" .. tostring(operation.key),
        key = operation.key,
        action = "reject",
        reason = reason,
        gates = operation.gates,
        technology_design = operation.technology_design,
        candidate_fingerprint = fingerprint.of({key = operation.key, reason = reason,
          gates = operation.gates})
      })
    end
  end
  return operations, {
    removed_effect_count = removed_count,
    skipped_base_extension_count = skipped_count,
    rejected_candidates = rejected_candidates
  }
end

return M
