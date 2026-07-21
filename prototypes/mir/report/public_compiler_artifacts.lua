local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")

local M = {}

local function sorted_effect_identities(effects)
  local identities = {}
  for _, effect in ipairs(effects or {}) do
    local identity = effect_contracts.identity(effect)
    if identity ~= "" then table.insert(identities, identity) end
  end
  table.sort(identities)
  return identities
end

local function row_effects(row)
  if row.action == "adopt" then return (row.adoption and row.adoption.effects) or {} end
  if row.fields then return row.fields.effects or {} end
  if row.technology_design and row.technology_design.design
    and row.technology_design.design.effects then
    return row.technology_design.design.effects.value or {}
  end
  return {}
end

function M.generation_plan(artifact)
  if type(artifact) ~= "table" or type(artifact.plan_fingerprint) ~= "string" then
    error("GenerationPlan public projection requires a finalized artifact.", 2)
  end
  local rows = {}
  for _, row in ipairs(artifact.rows or {}) do
    local design = row.technology_design or {}
    local identities = sorted_effect_identities(row_effects(row))
    table.insert(rows, {
      schema = 1,
      stream_id = row.stream_key,
      action = row.action,
      reason = row.reason or row.action,
      technology_id = row.technology_name or (row.adoption and row.adoption.owner),
      effect_count = #identities,
      effect_identities = identities,
      subject_fingerprint = design.subject_fingerprint,
      qualification_fingerprint = design.qualification_fingerprint
    })
  end
  local public = {
    schema = 1,
    kind = "mir-generation-plan-public",
    generation_plan_schema = artifact.schema,
    plan_fingerprint = artifact.plan_fingerprint,
    source_fingerprint = fingerprint.of(artifact.source_fingerprints or {}),
    validation_summary = deepcopy(artifact.validation_summary or {}),
    rows = rows
  }
  public.public_fingerprint = fingerprint.of(public)
  return public
end

function M.coverage(artifact)
  if type(artifact) ~= "table" or type(artifact.summary) ~= "table" then
    error("Coverage public projection requires a coverage artifact.", 2)
  end
  local public = {
    schema = 1,
    kind = "mir-coverage-public",
    coverage_report_schema = artifact.schema,
    summary = deepcopy(artifact.summary),
    coverage_fingerprint = fingerprint.of({
      schema = artifact.schema,
      summary = artifact.summary
    })
  }
  public.public_fingerprint = fingerprint.of(public)
  return public
end

local function sanitation_summary(ledger)
  ledger = ledger or {}
  return {
    schema = ledger.schema,
    pass = ledger.pass,
    scanned_technology_count = tonumber(ledger.scanned_technology_count) or 0,
    scanned_effect_count = tonumber(ledger.scanned_effect_count) or 0,
    pruned_effect_count = tonumber(ledger.pruned_effect_count) or 0,
    affected_technology_count = tonumber(ledger.affected_technology_count) or 0,
    generated_technology_count = tonumber(ledger.generated_technology_count) or 0,
    external_technology_count = tonumber(ledger.external_technology_count) or 0,
    emptied_technology_count = tonumber(ledger.emptied_technology_count) or 0,
    sanitized_target_inventory_fingerprint = ledger.sanitized_target_inventory_fingerprint
  }
end

function M.compiler_evidence(input)
  if type(input) ~= "table"
    or type(input.compilation_fingerprint) ~= "string"
    or type(input.qualification_fingerprint) ~= "string"
    or type(input.telemetry) ~= "table" then
    error("CompilerEvidence public projection requires compilation, qualification, and telemetry inputs.", 2)
  end
  local telemetry_fingerprint = fingerprint.of(input.telemetry)
  local input_summary = sanitation_summary(input.input_sanitation_ledger)
  local output_summary = sanitation_summary(input.output_sanitation_ledger)
  local public = {
    schema = 1,
    kind = "mir-compiler-evidence-public",
    compilation_plan_schema = input.compilation_plan_schema,
    compilation_fingerprint = input.compilation_fingerprint,
    qualification_fingerprint = input.qualification_fingerprint,
    semantic_fingerprint = input.qualification_fingerprint,
    telemetry_fingerprint = telemetry_fingerprint,
    run_fingerprint = fingerprint.of({
      qualification_fingerprint = input.qualification_fingerprint,
      telemetry_fingerprint = telemetry_fingerprint
    }),
    counts = deepcopy(input.telemetry.counters or {}),
    phases = deepcopy(input.telemetry.phases or {}),
    input_sanitation = input_summary,
    input_sanitation_fingerprint = fingerprint.of(input.input_sanitation_ledger or {}),
    output_sanitation = output_summary,
    output_sanitation_fingerprint = fingerprint.of(input.output_sanitation_ledger or {}),
    target_inventory_unchanged = type(input_summary.sanitized_target_inventory_fingerprint) == "string"
      and input_summary.sanitized_target_inventory_fingerprint
        == output_summary.sanitized_target_inventory_fingerprint
  }
  public.evidence_fingerprint = fingerprint.of(public)
  return public
end

return M
