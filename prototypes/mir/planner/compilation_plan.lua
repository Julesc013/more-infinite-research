local deepcopy = require("prototypes.mir.core.deepcopy")
local base_extensions = require("prototypes.mir.emit.base_extensions")
local stream_executor = require("prototypes.mir.emit.stream_executor")
local stream_compiler = require("prototypes.mir.planner.stream_compiler")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_safety = require("prototypes.mir.emit.effect_safety")
local effective_settings = require("prototypes.mir.settings.effective")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local technology_graph = require("prototypes.mir.planner.technology_graph")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local compiler_evidence = require("prototypes.mir.domain.evidence.compiler_evidence")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local public_artifacts = require("prototypes.mir.report.public_compiler_artifacts")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")

local M = {}
local normalized_base_operation

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
    if row.action == "skip" then
      row.technology_design = nil
    elseif not row.technology_design or (rebuild_design_by_index and rebuild_design_by_index[index]) then
      row.technology_design = technology_design.from_generation_row(row)
    end
    plan:add_owned_derived(row)
  end
  return plan:finalize():artifact_view()
end

local function sanitize_stream_artifact(stream_artifact)
  local rows, removed_count, skipped_count = {}, 0, 0
  for _, source_row in ipairs(stream_artifact.rows or {}) do
    local row = copy_row_with_design_view(source_row)
    if row.action == "emit" then
      local kept, removed = effect_safety.sanitize_effects(
        row.fields.effects,
        "CompilationPlan " .. tostring(row.technology_name),
        "generated"
      )
      row.fields.effects = kept
      removed_count = removed_count + #removed
      if #removed > 0 then
        row.effect_integrity = {removed = removed, remaining_effect_count = #kept}
        if #kept == 0 then
          row.action = "skip"
          row.reason = "no_valid_effect_targets"
          row.gates.effect_valid = {
            passed = false,
            status = "failed",
            evidence = {"effect-contracts:all-targets-missing"},
            reason = "no_valid_effect_targets"
          }
          skipped_count = skipped_count + 1
        else
          row.gates.effect_valid = {
            passed = true,
            status = "passed",
            evidence = {"effect-contracts:sanitized", "effect-contracts:remaining=" .. tostring(#kept)}
          }
        end
      else
        row.gates.effect_valid = {
          passed = true,
          status = "passed",
          evidence = {"effect-contracts:all-targets-exist"}
        }
      end
      -- Rebuild only when sanitation changed prototype semantics, ensuring the
      -- preliminary graph and final operation both consume the retained set.
      -- Zero-removal rows need only one qualification refresh after graph proof.
      if #removed > 0 then
        row.technology_design = row.action == "emit"
          and technology_design.from_generation_row(row) or nil
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

local function sanitize_base_operations(base_plan)
  local operations, removed_count, skipped_count = {}, 0, 0
  for _, source_operation in ipairs(base_plan or {}) do
    local operation = normalized_base_operation(source_operation)
    local kept, removed = effect_safety.sanitize_effects(
      (operation.technology and operation.technology.effects) or {},
      "CompilationPlan " .. tostring(operation.technology_name),
      "generated"
    )
    removed_count = removed_count + #removed
    if operation.technology then operation.technology.effects = kept end
    if #kept > 0 or #removed == 0 then
      table.insert(operations, operation)
    else
      skipped_count = skipped_count + 1
    end
  end
  return operations, {
    removed_effect_count = removed_count,
    skipped_base_extension_count = skipped_count
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
        row.gates.prerequisites_acyclic = deepcopy(rejection)
        row.gates.progression_safe = deepcopy(rejection)
      else
        row.gates.prerequisites_acyclic = graph_summary.proofs[row.technology_name] or {
          passed = false,
          status = "failed",
          evidence = {"technology-graph:missing-proof"},
          reason = "missing_graph_proof"
        }
        row.technology_design = technology_design.with_qualification(
          row.technology_design,
          row,
          {validated = true, share_immutable = true}
        )
      end
    elseif row.action == "adopt" then
      row.gates.prerequisites_acyclic = {
        passed = true,
        status = "not-applicable",
        evidence = {"decision:non-materializing-row"}
      }
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
    local rejection = graph_summary.rejected[operation.technology_name]
    if rejection then
      table.insert(rejected, {
        technology_name = operation.technology_name,
        manifest_id = operation.manifest_id,
        code = rejection.code,
        evidence = deepcopy(rejection.evidence)
      })
    else
      table.insert(accepted, operation)
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
  out.technology_design = technology_design.from_base_extension_operation(out)
  out.technology = technology_design.prototype_projection(out.technology_design, {validated = true})
  out.technology.type = "technology"
  return out
end

local function apply_weapon_overlap_policy(operation, stream_operations, stream_rows)
  if operation.key ~= "weapon-shooting-speed" then return operation end
  local mode = effective_settings.get("mir-adjust-vanilla-weapon-speed-techs") or target_line.weapon_overlap_default()
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
    effect_safety.assert_effects_allowed(expected_effects, "CompilationPlan " .. tostring(operation.technology_name))
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
  if type(stream_plan.artifact) == "function" then
    stream_artifact = stream_plan:artifact()
  elseif compiler_inputs and compiler_inputs.stream_plan_trusted then
    stream_artifact = stream_plan
  else
    stream_artifact = deepcopy(stream_plan)
  end
  if not stream_artifact or stream_artifact.schema ~= 3 then error("CompilationPlan requires GenerationPlan schema 3", 2) end
  local stream_effect_integrity
  stream_artifact, stream_effect_integrity = sanitize_stream_artifact(stream_artifact)
  local operations = materialized_stream_operations(stream_artifact, {include_design = false})
  local stream_operations = deepcopy(operations)
  local normalized_base, base_effect_integrity = sanitize_base_operations(base_plan)
  local finalized_base = {}
  for _, operation in ipairs(normalized_base) do
    local normalized = apply_weapon_overlap_policy(operation, stream_operations, stream_artifact.rows)
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
    source_fingerprints = source_fingerprints,
    input_sanitation_ledger = deepcopy((compiler_inputs or {}).input_sanitation_ledger),
    operations = operations,
    stream_plan = stream_artifact,
    base_extension_operations = normalized_base,
    validation_summary = validation_summary
  }
  artifact.compilation_fingerprint = fingerprint.of(compilation_material(artifact))
  artifact.qualification_fingerprint = fingerprint.of(qualification_material(artifact))
  artifact.semantic_fingerprint = artifact.qualification_fingerprint
  artifact.fingerprint = artifact.compilation_fingerprint
  return attach_run_evidence(artifact)
end

function M.compile(context)
  context = context or compiler_context.current()
  compiler_context.activate(context)
  local latest = context:state_view("compilation_plan")
  if latest then return latest end
  telemetry.start_phase("planning")
  local stream_plan = stream_compiler.compile_view(context)
  local base_plan = base_extensions.plan_all()
  latest = M.finalize(stream_plan, base_plan, {
    input_sanitation_ledger = context:artifact("input_sanitation_ledger"),
    stream_plan_trusted = true
  })
  context:set_state("compilation_plan", latest)
  stream_compiler.accept_artifact(latest.stream_plan, context, {trusted = true})
  telemetry.finish_phase("planning")
  return latest
end

function M.apply_streams(context)
  local plan = M.compile(context)
  stream_executor.apply(plan.stream_plan)
end

function M.publish(context)
  local plan = M.compile(context)
  local mod_data = require("prototypes.mir.emit.mod_data")
  local include_internal = diagnostics.enabled()
  local public_plan = public_artifacts.generation_plan(plan.stream_plan)
  telemetry.count("generation_plan_rows", #(plan.stream_plan.rows or {}))
  telemetry.count("generation_plan_public_bytes", #fingerprint.canonical(public_plan))
  local technology_design_count = 0
  local technology_design_canonical_bytes = 0
  for _, row in ipairs(plan.stream_plan.rows or {}) do
    if row.technology_design then
      technology_design_count = technology_design_count + 1
      if include_internal then
        technology_design_canonical_bytes = technology_design_canonical_bytes
          + #fingerprint.canonical(row.technology_design)
      end
    end
  end
  telemetry.count("technology_design_count", technology_design_count)
  telemetry.count("technology_design_canonical_bytes", technology_design_canonical_bytes)
  mod_data.emit_generation_plan(public_plan)
  if include_internal then
    telemetry.count("generation_plan_internal_bytes", #fingerprint.canonical(plan.stream_plan))
    mod_data.emit_internal_generation_plan(plan.stream_plan)
  end
  local input_ledger = deepcopy(plan.input_sanitation_ledger)
  local output_ledger = context and context:artifact("output_sanitation_ledger") or nil
  local evidence_input = {
    compilation_plan_schema = plan.schema,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    input_sanitation_ledger = input_ledger,
    output_sanitation_ledger = output_ledger
  }
  if target_line.feature_enabled("productivity_family_adoption") then
    require("prototypes.mir.emit.transactions.productivity_family_adoption").emit_mod_data()
  end
  require("prototypes.mir.report.coverage").publish(context, {include_internal = include_internal})
  telemetry.observe_max("context_state_keys", context and context:state_key_count() or 0)
  evidence_input.telemetry = telemetry.snapshot()
  local public_evidence = public_artifacts.compiler_evidence(evidence_input)
  local internal_evidence = include_internal and compiler_evidence.build(evidence_input) or nil
  require("prototypes.mir.emit.compiler_evidence_adapter").publish(public_evidence, internal_evidence)
  return true
end

function M.apply_base_extensions(context)
  local plan = M.compile(context)
  base_extensions.apply_plan(plan.base_extension_operations)
end

function M.snapshot(context)
  local plan = M.compile(context)
  local snapshot = {
    schema = plan.schema,
    fingerprint = plan.fingerprint,
    compilation_fingerprint = plan.compilation_fingerprint,
    qualification_fingerprint = plan.qualification_fingerprint,
    semantic_fingerprint = plan.semantic_fingerprint,
    source_fingerprints = plan.source_fingerprints,
    input_sanitation_ledger = plan.input_sanitation_ledger,
    operations = plan.operations,
    stream_plan = plan.stream_plan,
    base_extension_operations = plan.base_extension_operations,
    validation_summary = plan.validation_summary
  }
  attach_run_evidence(snapshot)
  return deepcopy(snapshot)
end

function M.assert_output(context)
  -- CompilationPlan construction owns TechnologyDesign validation and keeps the
  -- artifact context-local. The final assertion still compares every planned
  -- projection with live prototype output, but does not deep-copy or revalidate that trusted
  -- internal artifact. Public artifact validation remains strict by default.
  return require("prototypes.mir.planner.output_validator").assert_compilation_artifact(
    M.compile(context),
    {designs_validated = true}
  )
end

return M
