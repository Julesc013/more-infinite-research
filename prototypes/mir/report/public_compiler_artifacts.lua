local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local artifact_budget = require("prototypes.mir.domain.compiler.public_artifact_budget")

local M = {}
local SAMPLE_LIMIT = artifact_budget.sample_limit()

local function append_sample(out, value)
  if #out < SAMPLE_LIMIT then table.insert(out, value) end
end

function M.assert_byte_budget(artifact)
  local budget = artifact_budget.limit(artifact and artifact.kind)
  local bytes = #fingerprint.canonical(artifact)
  if bytes > budget then
    error("MIR public artifact exceeds its hard byte budget: " .. artifact.kind
      .. " bytes=" .. bytes .. " budget=" .. budget, 2)
  end
  return bytes, budget
end

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
    local public_row = {
      schema = 1,
      stream_id = row.stream_key,
      action = row.action,
      reason = row.reason or row.action,
      technology_id = row.technology_name or (row.adoption and row.adoption.owner),
      effect_count = #identities,
      effect_identities = identities,
      subject_fingerprint = design.subject_fingerprint,
      qualification_fingerprint = design.qualification_fingerprint,
      decision_fingerprint = fingerprint.of({
        stream_id = row.stream_key,
        action = row.action,
        reason = row.reason or row.action,
        technology_id = row.technology_name or (row.adoption and row.adoption.owner),
        gates = row.gates
      })
    }
    table.insert(rows, public_row)
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

function M.technology_catalog(catalog, provider_resolution)
  if type(catalog) ~= "table" or catalog.schema ~= 3
    or type(catalog.catalog_fingerprint) ~= "string" then
    error("TechnologyCatalog public projection requires the final schema-3 catalog.", 2)
  end
  local selected, samples = {}, {rejected = {}, review_required = {}}
  local reason_histogram = {}
  local alternative_count, rejected_count, review_count = 0, 0, 0
  for _, selection in ipairs(catalog.current_selections or {}) do
    table.insert(selected, {
      candidate_id = selection.candidate_id,
      alternative_id = selection.alternative_id,
      action = selection.action,
      design_fingerprint = selection.design_fingerprint,
      qualification_fingerprint = selection.qualification_fingerprint
    })
  end
  for _, candidate in ipairs(catalog.candidates or {}) do
    alternative_count = alternative_count + #(candidate.alternatives or {})
  end
  for _, qualification in ipairs(catalog.qualifications or {}) do
    local decision = qualification.qualification_decision or qualification.decision
    local reasons = qualification.rejection_reasons or qualification.reasons or {}
    if decision == "rejected" then
      rejected_count = rejected_count + 1
      append_sample(samples.rejected, {
        candidate_id = qualification.candidate_id,
        design_fingerprint = qualification.design_fingerprint,
        reasons = deepcopy(reasons)
      })
    elseif decision == "proposal" or decision == "review-required" then
      review_count = review_count + 1
      append_sample(samples.review_required, {
        candidate_id = qualification.candidate_id,
        design_fingerprint = qualification.design_fingerprint,
        reasons = deepcopy(reasons)
      })
    end
    for _, reason in ipairs(reasons) do
      reason_histogram[tostring(reason)] = (reason_histogram[tostring(reason)] or 0) + 1
    end
  end
  local provider_decisions = (provider_resolution or {}).decisions or {}
  local provider_summary = {decision_count = #provider_decisions, review_required_count = 0, providers = {}}
  local provider_ids = {}
  for _, decision in ipairs(provider_decisions) do
    if decision.final_state == "review-required" or decision.risk_disposition == "REVIEW_REQUIRED" then
      provider_summary.review_required_count = provider_summary.review_required_count + 1
    end
    if decision.provider_id then provider_ids[decision.provider_id] = true end
  end
  for provider_id in pairs(provider_ids) do table.insert(provider_summary.providers, provider_id) end
  table.sort(provider_summary.providers)
  local public = {
    schema = 1,
    kind = "mir-technology-catalog-public",
    technology_catalog_schema = catalog.schema,
    catalog_fingerprint = catalog.catalog_fingerprint,
    counts = {
      candidates = #(catalog.candidates or {}),
      alternatives = alternative_count,
      selected = #selected,
      rejected = rejected_count,
      review_required = review_count
    },
    selected = selected,
    reason_histogram = reason_histogram,
    provider_summary = provider_summary,
    samples = samples,
    truncation = {
      sample_limit = SAMPLE_LIMIT,
      rejected = rejected_count > #samples.rejected,
      review_required = review_count > #samples.review_required
    }
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
        == output_summary.sanitized_target_inventory_fingerprint,
    compiler_result = input.compiler_result and {
      schema = input.compiler_result.schema,
      result_phase = input.compiler_result.result_phase,
      result_fingerprint = input.compiler_result.result_fingerprint,
      planned_result_fingerprint = input.compiler_result.planned_result_fingerprint,
      status = input.compiler_result.status,
      dimensions = deepcopy(input.compiler_result.dimensions),
      execution_evidence = deepcopy(input.compiler_result.execution_evidence)
    } or nil,
    mutation_journal = input.mutation_journal and {
      schema = input.mutation_journal.schema,
      plan_fingerprint = input.mutation_journal.plan_fingerprint,
      journal_fingerprint = input.mutation_journal.journal_fingerprint,
      required_operation_count = input.mutation_journal.required_operation_count,
      terminal_counts = deepcopy(input.mutation_journal.terminal_counts),
      missing_operation_count = input.mutation_journal.missing_operation_count,
      duplicate_operation_count = input.mutation_journal.duplicate_operation_count,
      undeclared_operation_count = input.mutation_journal.undeclared_operation_count,
      out_of_plan_operation_count = input.mutation_journal.out_of_plan_operation_count,
      complete = input.mutation_journal.complete
    } or nil
  }
  public.evidence_fingerprint = fingerprint.of(public)
  return public
end

return M
