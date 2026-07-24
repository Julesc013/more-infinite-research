local deepcopy = require("prototypes.mir.core.deepcopy")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_effects = require("prototypes.mir.integrity.technology_effects")
local technology_graph = require("prototypes.mir.planner.technology_graph")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local safety_qualification = require("prototypes.mir.domain.technology.safety_qualification")
local technology_catalog = require("prototypes.mir.planner.technology_catalog")
local compiler_input = require("prototypes.mir.domain.compiler.compiler_input")
local compiler_result = require("prototypes.mir.domain.compiler.compiler_result")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")
local compilation_snapshot_contract = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot_adapter = require("prototypes.mir.pipeline.policy_snapshot_adapter")
local environment_adapter = require("prototypes.mir.platform.factorio.environment_identity")
local effect_target_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory")

local M = {}
local normalized_base_operation

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

local function default_compiler_input(stream_artifact, base_plan, sanitation_ledger)
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

local function copy_row_with_design_view(source_row)
  local row = {}
  for key, value in pairs(source_row) do
    row[key] = key == "technology_design" and value or deepcopy(value)
  end
  return row
end

local function copy_operation_without_design(source_operation)
  local operation = {}
  for key, value in pairs(source_operation) do
    if key ~= "technology_design" then operation[key] = deepcopy(value) end
  end
  return operation
end

local function rebuild_stream_artifact(stream_artifact, rows, rebuild_design_by_index)
  local plan = generation_plan.new({source_fingerprints = stream_artifact.source_fingerprints})
  for index, row in ipairs(rows) do
    if not row.technology_design or (rebuild_design_by_index and rebuild_design_by_index[index]) then
      row.technology_design = technology_design.from_generation_row(row)
    end
    plan:add_owned_derived(row)
  end
  return plan:finalize():artifact_view()
end

local function sanitize_stream_artifact(stream_artifact, target_inventory)
  local rows, removed_count, skipped_count = {}, 0, 0
  for _, source_row in ipairs(stream_artifact.rows or {}) do
    local row = copy_row_with_design_view(source_row)
    if row.action == "emit" then
      local kept, removed = technology_effects.sanitize_effects(
        row.fields.effects,
        "CompilationPlan " .. tostring(row.technology_name),
        "generated",
        target_inventory
      )
      row.fields.effects = kept
      removed_count = removed_count + #removed
      if #removed > 0 then
        row.effect_integrity = {removed = removed, remaining_effect_count = #kept}
        if #kept == 0 then
          row.action = "skip"
          row.reason = "no_valid_effect_targets"
          row.gates.effect_valid = gate_contract.failed(
            "effect-contracts",
            "no_valid_effect_targets",
            {"effect-contracts:all-targets-missing"}
          )
          skipped_count = skipped_count + 1
        else
          row.gates.effect_valid = gate_contract.passed(
            "effect-contracts",
            {"effect-contracts:sanitized", "effect-contracts:remaining=" .. tostring(#kept)}
          )
        end
      else
        row.gates.effect_valid = gate_contract.passed(
          "effect-contracts",
          {"effect-contracts:all-targets-exist"}
        )
      end
      -- Rebuild only when sanitation changed prototype semantics, ensuring the
      -- preliminary graph and final operation both consume the retained set.
      -- Zero-removal rows need only one qualification refresh after graph proof.
      if #removed > 0 then
        row.technology_design = technology_design.from_generation_row(row)
      end
    end
    table.insert(rows, row)
  end
  return {
    schema = 3,
    source_fingerprints = stream_artifact.source_fingerprints,
    rows = rows
  }, {
    removed_effect_count = removed_count,
    skipped_stream_count = skipped_count
  }
end

local function sanitize_base_operations(base_plan, target_inventory)
  local operations, removed_count, skipped_count, rejected_candidates = {}, 0, 0, {}
  for _, source_operation in ipairs(base_plan or {}) do
    local operation = normalized_base_operation(source_operation)
    local kept, removed = technology_effects.sanitize_effects(
      (operation.technology and operation.technology.effects) or {},
      "CompilationPlan " .. tostring(operation.technology_name),
      "generated",
      target_inventory
    )
    removed_count = removed_count + #removed
    if operation.technology then operation.technology.effects = kept end
    if #kept > 0 or #removed == 0 then
      operation.gates.effect_valid = gate_contract.passed(
        "effect-contracts",
        {#removed > 0 and "effect-contracts:sanitized" or "effect-contracts:all-targets-exist"}
      )
      operation.technology_design = technology_design.from_base_extension_operation(operation)
      table.insert(operations, operation)
    else
      skipped_count = skipped_count + 1
      operation.gates.effect_valid = gate_contract.failed(
        "effect-contracts", "no_valid_effect_targets", {"effect-contracts:all-targets-missing"})
      operation.technology_design = technology_design.from_base_extension_operation(operation)
      table.insert(rejected_candidates, {
        candidate_id = "base-continuation/" .. tostring(operation.key),
        key = operation.key,
        action = "reject",
        reason = "no_valid_effect_targets",
        gates = deepcopy(operation.gates),
        technology_design = deepcopy(operation.technology_design),
        candidate_fingerprint = fingerprint.of({key = operation.key, reason = "no_valid_effect_targets",
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

local function apply_graph_decisions(stream_artifact, graph_summary)
  local rows = {}
  for _, source_row in ipairs(stream_artifact.rows or {}) do
    table.insert(rows, copy_row_with_design_view(source_row))
  end
  for _, row in ipairs(rows) do
    if row.action == "emit" then
      local rejection = graph_summary.rejected[row.technology_name]
      if rejection then
        row.action = "skip"
        row.reason = rejection.code
        row.graph_integrity = deepcopy(rejection)
        if row.diagnostics then
          row.diagnostics.status = "skipped"
          row.diagnostics.reason = rejection.code
        end
        row.gates.prerequisites_acyclic = gate_contract.failed(
          "technology-graph",
          rejection.code,
          rejection.evidence
        )
        row.gates.progression_safe = gate_contract.failed(
          "technology-graph",
          rejection.code,
          rejection.evidence
        )
        row.technology_design = technology_design.from_generation_row(row)
      else
        local proof = graph_summary.proofs[row.technology_name]
        row.gates.prerequisites_acyclic = proof and deepcopy(proof) or gate_contract.failed(
          "technology-graph",
          "missing_graph_proof",
          {"technology-graph:missing-proof"}
        )
        row.gates.progression_safe = deepcopy(row.gates.prerequisites_acyclic)
        row.gates.output_identity_safe = gate_contract.passed(
          "generation-plan",
          {"generation-plan:unique-output-identity"}
        )
        row.technology_design = technology_design.with_qualification(
          row.technology_design,
          row,
          {validated = true, share_immutable = true}
        )
      end
    elseif row.action == "adopt" then
      row.gates.effect_valid = gate_contract.passed(
        "native-owner-binding",
        {"native-owner-binding:expected-output-validated"}
      )
      row.gates.prerequisites_acyclic = gate_contract.not_applicable(
        "technology-graph",
        "native-owner-patch-changes-prerequisites",
        row.adoption.input_fingerprint,
        {"native-owner-binding:prerequisites-unchanged"}
      )
      row.gates.progression_safe = gate_contract.not_applicable(
        "technology-graph",
        "native-owner-patch-changes-progression",
        row.adoption.input_fingerprint,
        {"native-owner-binding:progression-unchanged"}
      )
      row.gates.output_identity_safe = gate_contract.passed(
        "generation-plan",
        {"generation-plan:unique-owner-identity"}
      )
      row.technology_design = technology_design.with_qualification(
        row.technology_design,
        row,
        {validated = true, share_immutable = true}
      )
    end
  end
  return rebuild_stream_artifact(stream_artifact, rows)
end

local function apply_base_graph_decisions(base_operations, graph_summary)
  local accepted, rejected = {}, {}
  for _, operation in ipairs(base_operations or {}) do
    local updated = deepcopy(operation)
    local rejection = graph_summary.rejected[operation.technology_name]
    if rejection then
      updated.gates.prerequisites_acyclic = gate_contract.failed(
        "technology-graph", rejection.code, deepcopy(rejection.evidence))
      updated.gates.progression_safe = deepcopy(updated.gates.prerequisites_acyclic)
      updated.technology_design = technology_design.from_base_extension_operation(updated)
      table.insert(rejected, {
        candidate_id = "base-continuation/" .. tostring(operation.key),
        key = operation.key,
        technology_name = operation.technology_name,
        manifest_id = operation.manifest_id,
        action = "reject",
        reason = rejection.code,
        code = rejection.code,
        evidence = deepcopy(rejection.evidence),
        gates = deepcopy(updated.gates),
        technology_design = deepcopy(updated.technology_design),
        candidate_fingerprint = fingerprint.of({key = operation.key, reason = rejection.code,
          gates = updated.gates})
      })
    else
      local proof = graph_summary.proofs[operation.technology_name]
      updated.gates.prerequisites_acyclic = proof and deepcopy(proof) or gate_contract.failed(
        "technology-graph", "missing_graph_proof", {"technology-graph:missing-proof"})
      updated.gates.progression_safe = deepcopy(updated.gates.prerequisites_acyclic)
      updated.technology_design = technology_design.from_base_extension_operation(updated)
      updated.technology = technology_design.prototype_projection(updated.technology_design, {validated = true})
      updated.technology.type = "technology"
      table.insert(accepted, updated)
    end
  end
  return accepted, rejected
end

local function materialized_stream_operations(artifact, options)
  options = options or {}
  local out = {}
  for _, row in ipairs(artifact.rows or {}) do
    if row.action == "emit" then
      if not row.technology_design then
        error("CompilationPlan emitted row lacks TechnologyDesign schema 2: " .. tostring(row.stream_key), 2)
      end
      local design = row.technology_design
      local qualification = safety_qualification.from_design(design, row, nil, {validated = true})
      if qualification.decision ~= "qualified"
        and not (options.virtual_projection and qualification.decision == "proposal") then
        error("CompilationPlan cannot emit a design without complete structural safety qualification: "
          .. tostring(row.stream_key), 2)
      end
      table.insert(out, {
        schema = 2,
        operation = "emit_stream",
        stream_key = row.stream_key,
        manifest_id = row.manifest_id,
        technology_name = row.technology_name,
        technology_design = options.include_design == false and nil or deepcopy(design),
        technology = technology_design.prototype_shape(design, {validated = true}),
        registry = {kind = "stream", key = row.stream_key}
      })
    elseif row.action == "adopt" then
      local qualification = safety_qualification.from_design(row.technology_design, row, nil, {validated = true})
      if qualification.decision ~= "qualified"
        and not (options.virtual_projection and qualification.decision == "proposal") then
        error("CompilationPlan cannot patch an owner without complete structural safety qualification: "
          .. tostring(row.stream_key), 2)
      end
      table.insert(out, {
        schema = 2,
        operation = "native_owner_binding",
        binding_operation = row.adoption.operation,
        stream_key = row.stream_key,
        manifest_id = row.manifest_id,
        technology_name = row.adoption.owner,
        technology_design = options.include_design == false and nil or deepcopy(row.technology_design),
        effects = deepcopy(row.adoption.effects),
        configured_fields = deepcopy(row.adoption.configured_fields),
        input_fingerprint = row.adoption.input_fingerprint,
        output_fingerprint = row.adoption.output_fingerprint,
        expected_snapshot = deepcopy(row.adoption.expected_snapshot)
      })
    end
  end
  return out
end

normalized_base_operation = function(operation)
  local out = deepcopy(operation)
  out.schema = 2
  out.manifest_id = out.manifest_id or ("base-extension:" .. tostring(out.key) .. ":" .. tostring(out.technology_name))
  out.registry = {kind = "base_extension", key = out.key}
  if type(out.gates) ~= "table" or next(out.gates) == nil then out.gates = default_base_gates(out) end
  hard_gate_authority.assert_total(out.gates)
  out.technology_design = technology_design.from_base_extension_operation(out)
  out.technology = technology_design.prototype_projection(out.technology_design, {validated = true})
  out.technology.type = "technology"
  return out
end

local function apply_weapon_overlap_policy(operation, stream_operations, stream_rows, mode)
  if operation.key ~= "weapon-shooting-speed" then return operation end
  if mode == "off" then
    operation.planned_policy = "weapon-speed-overlap-retained"
    return operation
  end
  local strip = {}
  if mode == "always" then
    strip.rocket = true
    strip["cannon-shell"] = true
  else
    for _, stream_operation in ipairs(stream_operations) do
      for _, effect in ipairs((stream_operation.technology and stream_operation.technology.effects) or {}) do
        if effect.type == "gun-speed" and (effect.ammo_category == "rocket" or effect.ammo_category == "cannon-shell") then
          strip[effect.ammo_category] = true
        end
      end
    end
    -- An exact external infinite owner suppresses the MIR stream but still
    -- takes over the same category. Preserve that finalized skip decision in
    -- the base-operation plan so the later mutation and output validator use
    -- one authority.
    for _, row in ipairs(stream_rows or {}) do
      if row.action == "skip" and row.reason == "covered_by_existing_infinite_native_modifier" then
        for _, effect in ipairs((row.spec and row.spec.direct_effects) or {}) do
          if effect.type == "gun-speed" and (effect.ammo_category == "rocket" or effect.ammo_category == "cannon-shell") then
            strip[effect.ammo_category] = true
          end
        end
      end
    end
  end
  local filtered = {}
  for _, effect in ipairs(operation.technology.effects or {}) do
    if not (effect.type == "gun-speed" and strip[effect.ammo_category]) then table.insert(filtered, effect) end
  end
  operation.technology.effects = filtered
  operation.planned_policy = "weapon-speed-overlap"
  return operation
end

local function validate_operations(operations)
  local technology_names, manifest_ids, effects = {}, {}, {}
  local planned_overlaps = {}
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
    local expected_effects = operation.effects or (operation.technology and operation.technology.effects) or {}
    technology_effects.assert_effects_allowed(expected_effects, "CompilationPlan " .. tostring(operation.technology_name))
    for _, effect in ipairs(expected_effects) do
      local identity = generation_plan.effect_identity(effect)
      if identity ~= "" then
        if effects[identity] then
          if operation.planned_policy == "weapon-speed-overlap-retained"
            or effects[identity].planned_policy == "weapon-speed-overlap-retained" then
            table.insert(planned_overlaps, {
              identity = identity,
              owners = {effects[identity].technology_name, operation.technology_name},
              policy = "weapon-speed-overlap-retained"
            })
          else
            error("CompilationPlan contains duplicate direct-effect identity: " .. identity, 2)
          end
        end
        effects[identity] = effects[identity] or operation
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

local function compilation_operation_material(operation)
  if operation.operation == "emit_stream" then
    return {
      operation = operation.operation,
      stream_key = operation.stream_key,
      manifest_id = operation.manifest_id,
      technology_name = operation.technology_name,
      design_fingerprint = operation.technology_design.design_fingerprint,
      prototype_fingerprint = operation.technology_design.prototype_fingerprint,
      registry = operation.registry
    }
  end
  if operation.operation == "native_owner_binding" then
    return {
      operation = operation.operation,
      binding_operation = operation.binding_operation,
      stream_key = operation.stream_key,
      manifest_id = operation.manifest_id,
      technology_name = operation.technology_name,
      configured_fields = operation.configured_fields,
      input_fingerprint = operation.input_fingerprint,
      output_fingerprint = operation.output_fingerprint
    }
  end
  return {
    operation = operation.operation,
    manifest_id = operation.manifest_id,
    technology_name = operation.technology_name,
    technology = operation.technology,
    registry = operation.registry,
    planned_policy = operation.planned_policy
  }
end

local function compilation_material(artifact)
  local operations, rejected = {}, {}
  for _, operation in ipairs(artifact.operations or {}) do
    table.insert(operations, compilation_operation_material(operation))
  end
  for _, row in ipairs((artifact.stream_plan and artifact.stream_plan.rows) or {}) do
    if row.action == "skip" then
      table.insert(rejected, {
        stream_key = row.stream_key,
        manifest_id = row.manifest_id,
        reason = row.reason,
        qualification_fingerprint = row.technology_design and row.technology_design.qualification_fingerprint
      })
    end
  end
  return {
    schema = artifact.schema,
    input_fingerprint = artifact.compiler_input and artifact.compiler_input.input_fingerprint,
    source_fingerprints = artifact.source_fingerprints,
    operations = operations,
    rejected_operations = rejected
  }
end

local function qualification_material(artifact)
  return {
    schema = artifact.schema,
    compilation_fingerprint = artifact.compilation_fingerprint,
    input_sanitation_fingerprint = fingerprint.of(artifact.input_sanitation_ledger or {}),
    stream_plan = {
      schema = artifact.stream_plan.schema,
      plan_fingerprint = artifact.stream_plan.plan_fingerprint
    },
    technology_catalog_fingerprint = artifact.technology_catalog_fingerprint,
    validation_summary = artifact.validation_summary
  }
end

local function attach_run_evidence(artifact)
  artifact.telemetry = telemetry.snapshot()
  artifact.telemetry_fingerprint = fingerprint.of(artifact.telemetry)
  artifact.run_fingerprint = fingerprint.of({
    qualification_fingerprint = artifact.qualification_fingerprint,
    telemetry_fingerprint = artifact.telemetry_fingerprint
  })
  artifact.run = {
    schema = 1,
    telemetry = deepcopy(artifact.telemetry),
    telemetry_fingerprint = artifact.telemetry_fingerprint,
    run_fingerprint = artifact.run_fingerprint
  }
  return artifact
end

function M.finalize(stream_plan, base_plan, compiler_inputs)
  local stream_artifact
  local planned_base_candidates = deepcopy((compiler_inputs and compiler_inputs.base_candidates) or {})
  if type(stream_plan.artifact) == "function" then
    stream_artifact = stream_plan:artifact()
  elseif compiler_inputs and compiler_inputs.stream_plan_trusted then
    stream_artifact = stream_plan
  else
    stream_artifact = deepcopy(stream_plan)
  end
  if not stream_artifact or stream_artifact.schema ~= 3 then error("CompilationPlan requires GenerationPlan schema 3", 2) end
  local exact_input = compiler_inputs and compiler_inputs.compiler_input
    or default_compiler_input(stream_artifact, base_plan, (compiler_inputs or {}).input_sanitation_ledger)
  compiler_input.validate(exact_input)
  local stream_effect_integrity
  local target_inventory = compiler_inputs and compiler_inputs.effect_target_inventory
    or effect_target_inventory.capture()
  stream_artifact, stream_effect_integrity = sanitize_stream_artifact(stream_artifact, target_inventory)
  -- This projection is input to the authoritative graph evaluator, not an
  -- emission authorization. Pending graph gates remain explicit proposals.
  local operations = materialized_stream_operations(
    stream_artifact, {include_design = false, virtual_projection = true})
  local stream_operations = deepcopy(operations)
  local normalized_base, base_effect_integrity = sanitize_base_operations(base_plan, target_inventory)
  local finalized_base = {}
  for _, operation in ipairs(normalized_base) do
    local normalized = apply_weapon_overlap_policy(
      operation, stream_operations, stream_artifact.rows, exact_input.policy_snapshot.weapon_overlap_mode)
    normalized = normalized_base_operation(normalized)
    table.insert(finalized_base, normalized)
    table.insert(operations, copy_operation_without_design(normalized))
  end
  normalized_base = finalized_base
  validate_operations(operations)
  local graph_summary = technology_graph.validate_operations(operations)
  stream_artifact = apply_graph_decisions(stream_artifact, graph_summary)
  local graph_rejected_base
  normalized_base, graph_rejected_base = apply_base_graph_decisions(normalized_base, graph_summary)
  operations = materialized_stream_operations(stream_artifact)
  for _, operation in ipairs(normalized_base) do
    table.insert(operations, deepcopy(operation))
  end
  table.sort(operations, function(a, b)
    if a.technology_name ~= b.technology_name then return a.technology_name < b.technology_name end
    if a.operation ~= b.operation then return a.operation < b.operation end
    return tostring(a.manifest_id) < tostring(b.manifest_id)
  end)
  local validation_summary = validate_operations(operations)
  local rejected_operations = stream_effect_integrity.skipped_stream_count
    + base_effect_integrity.skipped_base_extension_count
    + graph_summary.rejected_planned_technology_count
  telemetry.count("candidate_operations", #operations + rejected_operations)
  telemetry.count("accepted_operations", #operations)
  telemetry.count("rejected_operations", rejected_operations)
  validation_summary.effect_integrity = {
    streams = stream_effect_integrity,
    base_extensions = base_effect_integrity
  }
  graph_summary.rejected_base_extensions = graph_rejected_base
  validation_summary.technology_graph = graph_summary
  local source_fingerprints = deepcopy(stream_artifact.source_fingerprints or {})
  source_fingerprints.base_extensions = fingerprint.of(normalized_base)
  local artifact = {
    schema = 2,
    compiler_input = compiler_input.snapshot(exact_input),
    source_fingerprints = source_fingerprints,
    input_sanitation_ledger = deepcopy((compiler_inputs or {}).input_sanitation_ledger),
    operations = operations,
    stream_plan = stream_artifact,
    base_extension_operations = normalized_base,
    validation_summary = validation_summary
  }
  artifact.compilation_fingerprint = fingerprint.of(compilation_material(artifact))
  local base_candidates_by_id = {}
  for _, candidate in ipairs(planned_base_candidates) do base_candidates_by_id[candidate.candidate_id] = candidate end
  for _, candidate in ipairs(base_effect_integrity.rejected_candidates or {}) do
    base_candidates_by_id[candidate.candidate_id] = candidate
  end
  for _, candidate in ipairs(graph_rejected_base or {}) do
    base_candidates_by_id[candidate.candidate_id] = candidate
  end
  for _, operation in ipairs(normalized_base) do
    local candidate_id = "base-continuation/" .. tostring(operation.key)
    base_candidates_by_id[candidate_id] = {
      schema = 1,
      candidate_id = candidate_id,
      key = operation.key,
      action = "create",
      technology_name = operation.technology_name,
      design_fingerprint = operation.technology_design.design_fingerprint,
      technology_design = deepcopy(operation.technology_design),
      gates = deepcopy(operation.gates),
      candidate_fingerprint = fingerprint.of({key = operation.key, technology_name = operation.technology_name,
        design_fingerprint = operation.technology_design.design_fingerprint, gates = operation.gates})
    }
  end
  local final_base_candidates = {}
  for _, candidate in pairs(base_candidates_by_id) do table.insert(final_base_candidates, candidate) end
  table.sort(final_base_candidates, function(left, right) return left.candidate_id < right.candidate_id end)
  artifact.technology_catalog = technology_catalog.finalize(
    stream_artifact.rows,
    source_fingerprints,
    operations,
    {
      generation_plan_fingerprint = stream_artifact.plan_fingerprint,
      compilation_plan_fingerprint = artifact.compilation_fingerprint,
      trusted_designs = true,
      base_candidates = final_base_candidates
    }
  )
  artifact.technology_catalog_fingerprint = artifact.technology_catalog.catalog_fingerprint
  telemetry.count("technology_catalog_candidates", #artifact.technology_catalog.candidates)
  telemetry.count("technology_catalog_alternatives", #artifact.technology_catalog.alternative_qualifications)
  telemetry.count("technology_catalog_canonical_bytes", #fingerprint.canonical(artifact.technology_catalog))
  artifact.qualification_fingerprint = fingerprint.of(qualification_material(artifact))
  artifact.semantic_fingerprint = artifact.qualification_fingerprint
  artifact.fingerprint = artifact.compilation_fingerprint
  local operation_fingerprints = {}
  for _, operation in ipairs(operations) do
    table.insert(operation_fingerprints, fingerprint.of(compilation_operation_material(operation)))
  end
  table.sort(operation_fingerprints)
  local rejected_candidates = {}
  for _, row in ipairs(stream_artifact.rows or {}) do
    if row.action == "skip" then
      table.insert(rejected_candidates, {
        candidate_id = row.technology_design.candidate_id,
        design_fingerprint = row.technology_design.design_fingerprint,
        reason = row.reason
      })
    end
  end
  for _, candidate in ipairs(final_base_candidates) do
    if candidate.action == "reject" then table.insert(rejected_candidates, {
      candidate_id = candidate.candidate_id,
      design_fingerprint = candidate.design_fingerprint,
      reason = candidate.reason,
      candidate_class = "base-continuation"
    }) end
  end
  local accepted_candidates = {}
  for _, selection in ipairs(artifact.technology_catalog.current_selections or {}) do
    if selection.action ~= "diagnose" then table.insert(accepted_candidates, deepcopy(selection)) end
  end
  for _, candidate in ipairs(final_base_candidates) do
    if candidate.action == "create" then table.insert(accepted_candidates, {
      candidate_id = candidate.candidate_id,
      design_fingerprint = candidate.design_fingerprint,
      action = candidate.action,
      candidate_class = "base-continuation"
    }) end
  end
  table.sort(accepted_candidates, function(left, right)
    return tostring(left.candidate_id) < tostring(right.candidate_id)
  end)
  table.sort(rejected_candidates, function(left, right)
    return tostring(left.candidate_id) < tostring(right.candidate_id)
  end)

  local provider_claims, review_required_candidates = {}, {}
  for _, decision in ipairs(exact_input.compilation_snapshot.provider_inputs.decisions or {}) do
    local projection = {
      provider_id = decision.provider_id,
      provider_version = decision.provider_version,
      candidate_family = decision.candidate_family,
      subject = {prototype_type = decision.prototype_type, prototype_name = decision.prototype_name},
      target_stream = decision.target_stream,
      final_state = decision.final_state,
      claim_fingerprint = decision.claim_fingerprint,
      decision_fingerprint = decision.decision_fingerprint,
      risk_fingerprint = decision.risk_fingerprint,
      risk_disposition = decision.risk_disposition
    }
    table.insert(provider_claims, projection)
    if decision.final_state == "review-required" or decision.risk_disposition == "REVIEW_REQUIRED" then
      table.insert(review_required_candidates, deepcopy(projection))
    end
  end
  table.sort(provider_claims, function(left, right)
    if tostring(left.claim_fingerprint) ~= tostring(right.claim_fingerprint) then
      return tostring(left.claim_fingerprint) < tostring(right.claim_fingerprint)
    end
    return tostring(left.provider_id) < tostring(right.provider_id)
  end)
  table.sort(review_required_candidates, function(left, right)
    return tostring(left.claim_fingerprint) < tostring(right.claim_fingerprint)
  end)

  local design_by_candidate = {}
  for _, candidate in ipairs(artifact.technology_catalog.candidates or {}) do
    for _, alternative in ipairs(candidate.alternatives or {}) do
      design_by_candidate[candidate.candidate_id .. "/" .. alternative.alternative_id] = alternative.technology_design
    end
  end
  local quality_dispositions, promotion_dispositions = {}, {}
  local promotion_blocked = false
  for _, selection in ipairs(artifact.technology_catalog.current_selections or {}) do
    if selection.action ~= "diagnose" then
      local design = design_by_candidate[selection.candidate_id .. "/" .. selection.alternative_id] or {}
      local identity = design.identity or {}
      local released = identity.identity_state == "released"
      local profile_id = selection.action == "adopt"
        and "existing-stream-attachment-v1" or "process-family-experimental-v1"
      table.insert(quality_dispositions, {
        candidate_id = selection.candidate_id,
        design_fingerprint = selection.design_fingerprint,
        profile_id = profile_id,
        status = released and "NOT_APPLICABLE_EXISTING_RELEASED_ID" or "INCOMPLETE",
        profile_authority_fingerprint = exact_input.policy_snapshot.quality_profile_fingerprint
      })
      table.insert(promotion_dispositions, {
        candidate_id = selection.candidate_id,
        design_fingerprint = selection.design_fingerprint,
        identity_state = identity.identity_state,
        status = released and "NOT_APPLICABLE_ALREADY_RELEASED" or "INELIGIBLE_MISSING_ADMISSION"
      })
      if not released then promotion_blocked = true end
    end
  end
  for _, candidate in ipairs(final_base_candidates) do
    if candidate.action == "create" then
      local identity = (candidate.technology_design or {}).identity or {}
      local released = identity.identity_state == "released"
      table.insert(quality_dispositions, {
        candidate_id = candidate.candidate_id,
        design_fingerprint = candidate.design_fingerprint,
        profile_id = "base-continuation-v1",
        status = released and "NOT_APPLICABLE_EXISTING_RELEASED_ID" or "INCOMPLETE",
        profile_authority_fingerprint = exact_input.policy_snapshot.quality_profile_fingerprint
      })
      table.insert(promotion_dispositions, {
        candidate_id = candidate.candidate_id,
        design_fingerprint = candidate.design_fingerprint,
        identity_state = identity.identity_state,
        status = released and "NOT_APPLICABLE_ALREADY_RELEASED" or "INELIGIBLE_MISSING_ADMISSION"
      })
      if not released then promotion_blocked = true end
    end
  end
  table.sort(quality_dispositions, function(left, right) return left.candidate_id < right.candidate_id end)
  table.sort(promotion_dispositions, function(left, right) return left.candidate_id < right.candidate_id end)

  local sanitation_dispositions = {}
  local sanitation = artifact.input_sanitation_ledger or {}
  if #sanitation > 0 then
    sanitation_dispositions = deepcopy(sanitation)
  else
    for key, value in pairs(sanitation) do
      table.insert(sanitation_dispositions, {key = tostring(key), disposition = deepcopy(value)})
    end
    table.sort(sanitation_dispositions, function(left, right) return left.key < right.key end)
  end
  local has_review = #review_required_candidates > 0
  artifact.compiler_result = compiler_result.new({
    input_fingerprint = exact_input.input_fingerprint,
    technology_catalog_fingerprint = artifact.technology_catalog_fingerprint,
    generation_plan_fingerprint = stream_artifact.plan_fingerprint,
    compilation_plan_fingerprint = artifact.compilation_fingerprint,
    qualification_fingerprint = artifact.qualification_fingerprint,
    operation_fingerprints = operation_fingerprints,
    accepted_candidates = accepted_candidates,
    rejected_candidates = rejected_candidates,
    review_required_candidates = review_required_candidates,
    provider_claims = provider_claims,
    base_continuations = final_base_candidates,
    quality_dispositions = quality_dispositions,
    promotion_dispositions = promotion_dispositions,
    sanitation_dispositions = sanitation_dispositions,
    dimensions = {
      execution = "PLANNED",
      safety = "QUALIFIED",
      review = has_review and "REQUIRED" or "NOT_REQUIRED",
      promotion = promotion_blocked and "BLOCKED" or "NOT_APPLICABLE",
      release = promotion_blocked and "BLOCKED" or (has_review and "REVIEW_REQUIRED" or "ELIGIBLE")
    }
  })
  return attach_run_evidence(artifact)
end

return M
