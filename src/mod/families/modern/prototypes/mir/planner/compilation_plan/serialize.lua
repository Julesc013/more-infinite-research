local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

function M.operation(operation)
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
    planned_policy = operation.planned_policy,
    planned_overlap_identities = operation.planned_overlap_identities,
    effect_ownership = operation.effect_ownership
  }
end

function M.compilation(artifact)
  local operations, rejected = {}, {}
  for _, operation in ipairs(artifact.operations or {}) do
    table.insert(operations, M.operation(operation))
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

function M.qualification(artifact)
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

return M
