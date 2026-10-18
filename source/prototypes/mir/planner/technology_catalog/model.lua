local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local gate_contract = require("prototypes.mir.domain.technology.gate")

local M = {}

M.SCHEMA = 4
M.PHASES = {preselection = true, final = true}
M.ALTERNATIVE_EVALUATION_MODES = {
  ["full-diagnostics"] = true,
  ["player-selected-primary-plus-required-fallbacks"] = true
}
M.authority = trusted_record.new("TechnologyCatalog")

function M.alternative_id(design, action)
  local target = design.materialization.target or design.technology_id or design.candidate_id
  return tostring(action) .. ":" .. design.materialization.kind .. ":" .. tostring(target)
end

function M.selection_key(row)
  return tostring(row.stream_key) .. ":" .. tostring(row.manifest_id or row.stream_key)
end

function M.safe_diagnostic_row(diagnostic_design)
  return {action = "diagnose", gates = diagnostic_design.gates}
end

function M.constructed_diagnostic_evaluation(alternative)
  return {
    state = "constructed",
    alternative_id = alternative.alternative_id,
    design_fingerprint = alternative.design_fingerprint,
    qualification_fingerprint = alternative.qualification_fingerprint
  }
end

function M.deferred_diagnostic_evaluation(primary)
  return {
    state = "deferred-primary-qualified",
    primary_alternative_id = primary.alternative_id,
    primary_design_fingerprint = primary.design_fingerprint,
    primary_qualification_fingerprint = primary.qualification_fingerprint
  }
end

function M.deferred_rejected_diagnostic_evaluation(primary, selection_key, reason)
  return {
    state = "deferred-initial-skip-rejected-primary",
    selection_key = selection_key,
    reason = reason,
    primary_alternative_id = primary.alternative_id,
    primary_design_fingerprint = primary.design_fingerprint,
    primary_qualification_fingerprint = primary.qualification_fingerprint
  }
end

function M.alternative_evaluation(mode, evaluated_alternatives, deferred_diagnostic_alternatives,
  deferred_rejected_diagnostic_alternatives)
  local deferred_qualified = deferred_diagnostic_alternatives or 0
  local deferred_rejected = deferred_rejected_diagnostic_alternatives or 0
  return {
    mode = mode,
    complete = deferred_qualified + deferred_rejected == 0,
    evaluated_alternatives = evaluated_alternatives or 0,
    deferred_diagnostic_alternatives = deferred_qualified + deferred_rejected,
    deferred_rejected_diagnostic_alternatives = deferred_rejected
  }
end

function M.final_qualification_row(row)
  local copy = {}
  for key, value in pairs(row) do copy[key] = value end
  copy.gates = {}
  for gate_name, gate in pairs(row.gates or {}) do copy.gates[gate_name] = gate end
  if copy.action ~= "emit" and copy.action ~= "adopt" then
    copy.gates = copy.gates or {}
    for gate_name, gate in pairs(copy.gates) do
      if gate.status == "pending" or gate.status == "superseded" then
        copy.gates[gate_name] = gate_contract.not_applicable(
          "technology-catalog:final-rejected-alternative",
          "rejected-alternative-reaches-gate",
          fingerprint.of({selection_key = M.selection_key(row), gate = gate_name, reason = copy.reason}),
          {"technology-catalog:unreached-after-rejection:" .. gate_name}
        )
      end
    end
  end
  return copy
end

function M.alternative_record(design, qualification, action, disposition)
  return {
    alternative_id = M.alternative_id(design, action),
    action = action,
    disposition = disposition,
    materialization = design.materialization,
    technology_design = design,
    design_fingerprint = design.design_fingerprint,
    prototype_fingerprint = design.prototype_fingerprint,
    qualification_fingerprint = qualification.qualification_fingerprint,
    qualification_decision = qualification.decision
  }
end

function M.trust_identity(catalog)
  return {
    schema = catalog.schema,
    phase = catalog.phase,
    preselection_catalog_fingerprint = catalog.preselection_catalog_fingerprint,
    selection_fingerprint = catalog.selection_fingerprint,
    catalog_fingerprint = catalog.catalog_fingerprint
  }
end

function M.trust_identity_unchanged(catalog, registered)
  return catalog.schema == registered.schema
    and catalog.phase == registered.phase
    and catalog.preselection_catalog_fingerprint == registered.preselection_catalog_fingerprint
    and catalog.selection_fingerprint == registered.selection_fingerprint
    and catalog.catalog_fingerprint == registered.catalog_fingerprint
end

function M.preselection_material(catalog)
  return {
    schema = catalog.schema,
    candidate_catalog_fingerprint = catalog.candidate_catalog_fingerprint,
    qualification_catalog_fingerprint = catalog.qualification_catalog_fingerprint,
    alternative_qualifications = catalog.alternative_qualifications,
    alternative_evaluation = catalog.alternative_evaluation,
    context_fingerprint = catalog.context_fingerprint,
    mutation_authority = catalog.mutation_authority,
    selection_authority = catalog.selection_authority,
    phase = catalog.phase,
    generation_plan_fingerprint = catalog.generation_plan_fingerprint,
    compilation_plan_fingerprint = catalog.compilation_plan_fingerprint,
    base_candidates = catalog.base_candidates
  }
end

function M.candidate_catalog_material(candidates)
  local out = {}
  for _, candidate in ipairs(candidates or {}) do
    local alternatives = {}
    for _, alternative in ipairs(candidate.alternatives or {}) do
      table.insert(alternatives, {
        alternative_id = alternative.alternative_id,
        action = alternative.action,
        disposition = alternative.disposition,
        design_fingerprint = alternative.design_fingerprint,
        prototype_fingerprint = alternative.prototype_fingerprint,
        qualification_fingerprint = alternative.qualification_fingerprint,
        qualification_decision = alternative.qualification_decision
      })
    end
    table.insert(out, {
      candidate_id = candidate.candidate_id,
      candidate_fingerprint = candidate.candidate_fingerprint,
      selection_key = candidate.selection_key,
      alternatives = alternatives,
      diagnostic_evaluation = candidate.diagnostic_evaluation
    })
  end
  return out
end

function M.qualification_catalog_material(qualifications)
  local out = {}
  for _, qualification in ipairs(qualifications or {}) do
    table.insert(out, {
      candidate_id = qualification.candidate_id,
      design_fingerprint = qualification.design_fingerprint,
      qualification_fingerprint = qualification.qualification_fingerprint,
      decision = qualification.decision
    })
  end
  return out
end

function M.catalog_material(catalog)
  return {
    preselection_catalog_fingerprint = catalog.preselection_catalog_fingerprint,
    current_selections = catalog.current_selections,
    selection_fingerprint = catalog.selection_fingerprint
  }
end

return M
