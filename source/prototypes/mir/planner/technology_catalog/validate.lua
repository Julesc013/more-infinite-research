local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_candidate = require("prototypes.mir.domain.technology.technology_candidate")
local technology_qualification = require("prototypes.mir.domain.technology.technology_qualification")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local safety_qualification = require("prototypes.mir.domain.technology.safety_qualification")
local indexer = require("prototypes.mir.planner.technology_catalog.index")
local model = require("prototypes.mir.planner.technology_catalog.model")

local M = {}

local function nonnegative_integer(value)
  return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function verify_exact_fields(value, allowed, label)
  for key in pairs(value) do
    if not allowed[key] then
      error("TechnologyCatalog " .. label .. " contains an unknown field: " .. tostring(key), 3)
    end
  end
end

local function verify_evaluation_shape(evaluation)
  if type(evaluation) ~= "table"
    or not model.ALTERNATIVE_EVALUATION_MODES[evaluation.mode]
    or type(evaluation.complete) ~= "boolean"
    or not nonnegative_integer(evaluation.evaluated_alternatives)
    or not nonnegative_integer(evaluation.deferred_diagnostic_alternatives)
    or not nonnegative_integer(evaluation.deferred_rejected_diagnostic_alternatives)
    or evaluation.deferred_rejected_diagnostic_alternatives > evaluation.deferred_diagnostic_alternatives then
    error("TechnologyCatalog alternative evaluation state is invalid.", 3)
  end
  verify_exact_fields(evaluation, {
    mode = true, complete = true,
    evaluated_alternatives = true, deferred_diagnostic_alternatives = true,
    deferred_rejected_diagnostic_alternatives = true
  }, "alternative evaluation state")
end

local function nonempty_string(value)
  return type(value) == "string" and value ~= ""
end

local function verify_diagnostic_evaluation(catalog, indexes, candidate)
  local evaluation = candidate.diagnostic_evaluation
  if type(evaluation) ~= "table" or type(evaluation.state) ~= "string" then
    error("TechnologyCatalog candidate diagnostic evaluation is invalid: "
      .. tostring(candidate.candidate_id), 3)
  end
  if evaluation.state == "constructed" then
    verify_exact_fields(evaluation, {
      state = true, alternative_id = true, design_fingerprint = true, qualification_fingerprint = true
    }, "constructed diagnostic evaluation")
    if not nonempty_string(evaluation.alternative_id)
      or not nonempty_string(evaluation.design_fingerprint)
      or not nonempty_string(evaluation.qualification_fingerprint) then
      error("TechnologyCatalog constructed diagnostic binding is invalid: "
        .. tostring(candidate.candidate_id), 3)
    end
    local alternative = indexer.alternative(indexes, candidate.candidate_id, evaluation.alternative_id)
    if not alternative or alternative.action ~= "diagnose" or alternative.disposition ~= "safe-diagnostic"
      or alternative.design_fingerprint ~= evaluation.design_fingerprint
      or alternative.qualification_fingerprint ~= evaluation.qualification_fingerprint then
      error("TechnologyCatalog constructed diagnostic binding is invalid: "
        .. tostring(candidate.candidate_id), 3)
    end
    return false
  end
  if evaluation.state == "deferred-initial-skip-rejected-primary" then
    verify_exact_fields(evaluation, {
      state = true, selection_key = true, reason = true, primary_alternative_id = true,
      primary_design_fingerprint = true, primary_qualification_fingerprint = true
    }, "deferred rejected diagnostic evaluation")
    if catalog.phase ~= "final"
      or catalog.alternative_evaluation.mode ~= "player-selected-primary-plus-required-fallbacks"
      or not nonempty_string(evaluation.selection_key)
      or not nonempty_string(evaluation.reason)
      or not nonempty_string(evaluation.primary_alternative_id)
      or not nonempty_string(evaluation.primary_design_fingerprint)
      or not nonempty_string(evaluation.primary_qualification_fingerprint)
      or candidate.selection_key ~= evaluation.selection_key then
      error("TechnologyCatalog deferred rejected diagnostic is outside its player final-mode contract.", 3)
    end
    local primary = indexer.alternative(indexes, candidate.candidate_id, evaluation.primary_alternative_id)
    local qualification = primary and indexer.qualification(indexes, primary.qualification_fingerprint)
    if not primary or primary.action ~= "reject" or primary.disposition ~= "rejected"
      or primary.qualification_decision ~= "rejected"
      or primary.design_fingerprint ~= evaluation.primary_design_fingerprint
      or primary.qualification_fingerprint ~= evaluation.primary_qualification_fingerprint
      or not qualification or qualification.candidate_id ~= candidate.candidate_id
      or qualification.design_fingerprint ~= primary.design_fingerprint
      or qualification.decision ~= "rejected" then
      error("TechnologyCatalog deferred rejected diagnostic primary proof is invalid: "
        .. tostring(candidate.candidate_id), 3)
    end
    if #candidate.alternatives ~= 1 then
      error("TechnologyCatalog deferred rejected diagnostic retained an unevaluated alternative: "
        .. tostring(candidate.candidate_id), 3)
    end
    return "rejected", primary
  end
  if evaluation.state ~= "deferred-primary-qualified" then
    error("TechnologyCatalog diagnostic evaluation state is unknown: "
      .. tostring(evaluation.state), 3)
  end
  verify_exact_fields(evaluation, {
    state = true, primary_alternative_id = true,
    primary_design_fingerprint = true, primary_qualification_fingerprint = true
  }, "deferred diagnostic evaluation")
  if catalog.phase ~= "final"
    or catalog.alternative_evaluation.mode ~= "player-selected-primary-plus-required-fallbacks"
    or not nonempty_string(evaluation.primary_alternative_id)
    or not nonempty_string(evaluation.primary_design_fingerprint)
    or not nonempty_string(evaluation.primary_qualification_fingerprint) then
    error("TechnologyCatalog deferred diagnostic is outside its player final-mode contract.", 3)
  end
  local primary = indexer.alternative(indexes, candidate.candidate_id, evaluation.primary_alternative_id)
  local qualification = primary and indexer.qualification(indexes, primary.qualification_fingerprint)
  if not primary or primary.action ~= "emit" and primary.action ~= "adopt"
    or primary.disposition ~= "materialize" or primary.qualification_decision ~= "qualified"
    or primary.design_fingerprint ~= evaluation.primary_design_fingerprint
    or primary.qualification_fingerprint ~= evaluation.primary_qualification_fingerprint
    or not qualification or qualification.candidate_id ~= candidate.candidate_id
    or qualification.design_fingerprint ~= primary.design_fingerprint
    or qualification.decision ~= "qualified" then
    error("TechnologyCatalog deferred diagnostic primary proof is invalid: "
      .. tostring(candidate.candidate_id), 3)
  end
  if #candidate.alternatives ~= 1 then
    error("TechnologyCatalog deferred diagnostic retained an unevaluated alternative: "
      .. tostring(candidate.candidate_id), 3)
  end
  return "qualified", primary
end

local function verify(catalog, options)
  options = options or {}
  if type(catalog) ~= "table" or catalog.schema ~= model.SCHEMA
    or type(catalog.candidates) ~= "table" or type(catalog.qualifications) ~= "table"
    or type(catalog.alternative_qualifications) ~= "table" or type(catalog.current_selections) ~= "table"
    or type(catalog.alternative_evaluation) ~= "table"
    or not model.PHASES[catalog.phase]
    or catalog.mutation_authority ~= false or catalog.selection_authority ~= "deterministic-policy-v2"
    or type(catalog.generation_plan_fingerprint) ~= "string"
    or type(catalog.compilation_plan_fingerprint) ~= "string" then
    error("TechnologyCatalog schema 4 canonical inventory is required.", 2)
  end
  verify_evaluation_shape(catalog.alternative_evaluation)
  if catalog.phase ~= "final" and catalog.alternative_evaluation.mode ~= "full-diagnostics" then
    error("TechnologyCatalog preselection must retain full diagnostics.", 2)
  end
  if type(catalog.base_candidates) ~= "table" then
    error("TechnologyCatalog base continuation inventory is required.", 2)
  end
  local indexes = indexer.new()
  for _, qualification in ipairs(catalog.qualifications) do
    if options.trusted_children then technology_qualification.assert_trusted(qualification)
    else technology_qualification.verify_untrusted(qualification) end
    if indexer.qualification(indexes, qualification.qualification_fingerprint) then
      error("TechnologyCatalog qualification fingerprint is duplicated: "
        .. tostring(qualification.qualification_fingerprint), 2)
    end
    indexer.add_qualification(indexes, qualification)
  end
  local alternative_count = 0
  local qualification_use = {}
  for _, candidate in ipairs(catalog.candidates) do
    if options.trusted_children then technology_candidate.assert_trusted(candidate)
    else technology_candidate.verify_untrusted(candidate) end
    if type(candidate.selection_key) ~= "string" or type(candidate.alternatives) ~= "table" then
      error("TechnologyCatalog candidate alternatives are invalid.", 2)
    end
    for _, alternative in ipairs(candidate.alternatives) do
      alternative_count = alternative_count + 1
      local key = indexer.alternative_key(candidate.candidate_id, alternative.alternative_id)
      if indexes.alternatives[key] then error("TechnologyCatalog alternative is duplicated: " .. key, 2) end
      local qualification = indexer.qualification(indexes, alternative.qualification_fingerprint)
      if not qualification then
        error("TechnologyCatalog alternative lacks an exact qualification: " .. key, 2)
      end
      if qualification.candidate_id ~= candidate.candidate_id
        or qualification.design_fingerprint ~= alternative.design_fingerprint
        or qualification.decision ~= alternative.qualification_decision then
        error("TechnologyCatalog alternative qualification does not bind its candidate: " .. key, 2)
      end
      if qualification_use[alternative.qualification_fingerprint] then
        error("TechnologyCatalog qualification is reused by multiple alternatives: " .. key, 2)
      end
      qualification_use[alternative.qualification_fingerprint] = true
      if type(alternative.technology_design) ~= "table"
        or alternative.technology_design.design_fingerprint ~= alternative.design_fingerprint then
        error("TechnologyCatalog alternative lacks its exact preserved TechnologyDesign: " .. key, 2)
      end
      if options.trusted_children then technology_design.assert_trusted(alternative.technology_design)
      else technology_design.verify_untrusted(alternative.technology_design) end
      indexer.add_alternative(indexes, candidate.candidate_id, alternative)
    end
  end
  if #catalog.qualifications ~= alternative_count then
    error("TechnologyCatalog qualification inventory does not match alternatives.", 2)
  end
  for qualification_fingerprint in pairs(indexes.qualifications) do
    if not qualification_use[qualification_fingerprint] then
      error("TechnologyCatalog qualification lacks an alternative binding: "
        .. qualification_fingerprint, 2)
    end
  end
  local deferred_primaries, deferred_rejected_primaries, deferred_rejected_evaluations = {}, {}, {}
  local deferred_count, deferred_rejected_count = 0, 0
  for _, candidate in ipairs(catalog.candidates) do
    local deferred_kind, primary = verify_diagnostic_evaluation(catalog, indexes, candidate)
    if deferred_kind == "qualified" then
      deferred_count = deferred_count + 1
      deferred_primaries[candidate.candidate_id] = primary
    elseif deferred_kind == "rejected" then
      deferred_count = deferred_count + 1
      deferred_rejected_count = deferred_rejected_count + 1
      deferred_rejected_primaries[candidate.candidate_id] = primary
      deferred_rejected_evaluations[candidate.candidate_id] = candidate.diagnostic_evaluation
    end
  end
  local evaluation = catalog.alternative_evaluation
  if evaluation.evaluated_alternatives ~= alternative_count
    or evaluation.deferred_diagnostic_alternatives ~= deferred_count
    or evaluation.deferred_rejected_diagnostic_alternatives ~= deferred_rejected_count
    or evaluation.complete ~= (deferred_count == 0)
    or (evaluation.mode == "full-diagnostics" and deferred_count ~= 0)
    or (evaluation.mode == "player-selected-primary-plus-required-fallbacks" and deferred_count == 0) then
    error("TechnologyCatalog alternative evaluation counts are invalid.", 2)
  end
  if catalog.phase == "final" then
    for _, qualification in ipairs(catalog.qualifications) do
      for _, gate_name in ipairs(safety_qualification.schema_authority().gate_order) do
        local gate = qualification.hard_gates[gate_name]
        local resolved = gate and gate_contract.is_authoritatively_resolved(gate)
        if not resolved then
          error("TechnologyCatalog final qualification has an unresolved hard gate: "
            .. qualification.candidate_id .. "/" .. gate_name, 2)
        end
      end
    end
  end
  local mapped_alternatives, mapping_count = {}, 0
  for _, mapping in ipairs(catalog.alternative_qualifications) do
    local alternative = indexer.alternative(indexes, mapping.candidate_id, mapping.alternative_id)
    if not alternative or alternative.design_fingerprint ~= mapping.design_fingerprint
      or alternative.qualification_fingerprint ~= mapping.qualification_fingerprint
      or alternative.qualification_decision ~= mapping.decision then
      error("TechnologyCatalog alternative qualification mapping is invalid.", 2)
    end
    local key = indexer.alternative_key(mapping.candidate_id, mapping.alternative_id)
    if mapped_alternatives[key] then
      error("TechnologyCatalog alternative qualification mapping is duplicated: " .. key, 2)
    end
    mapped_alternatives[key] = true
    mapping_count = mapping_count + 1
  end
  if mapping_count ~= alternative_count then
    error("TechnologyCatalog alternative qualification mappings are incomplete.", 2)
  end
  for key in pairs(indexes.alternatives) do
    if not mapped_alternatives[key] then
      error("TechnologyCatalog alternative qualification mapping is missing: " .. key, 2)
    end
  end
  local selections_by_candidate = {}
  for _, selection in ipairs(catalog.current_selections) do
    local alternative = indexer.alternative(indexes, selection.candidate_id, selection.alternative_id)
    local acceptable = alternative and (alternative.qualification_decision == "qualified"
      or (catalog.phase ~= "final" and alternative.qualification_decision == "proposal"))
    local deferred_rejected = deferred_rejected_primaries[selection.candidate_id]
    local deferred_evaluation = deferred_rejected_evaluations[selection.candidate_id]
    local special_rejection = deferred_rejected
      and selection.action == "reject"
      and alternative == deferred_rejected
      and selection.alternative_id == deferred_rejected.alternative_id
      and selection.design_fingerprint == deferred_rejected.design_fingerprint
      and selection.qualification_fingerprint == deferred_rejected.qualification_fingerprint
      and selection.policy == "stable-owner-promoted-diagnostic-v1"
      and type(selection.deferred_rejection) == "table"
      and selection.deferred_rejection.state == "deferred-initial-skip-rejected-primary"
      and selection.selection_key == deferred_evaluation.selection_key
      and selection.reason == deferred_evaluation.reason
      and selection.deferred_rejection.selection_key == deferred_evaluation.selection_key
      and selection.deferred_rejection.reason == deferred_evaluation.reason
      and selection.deferred_rejection.primary_alternative_id == deferred_rejected.alternative_id
      and selection.deferred_rejection.primary_design_fingerprint == deferred_rejected.design_fingerprint
      and selection.deferred_rejection.primary_qualification_fingerprint == deferred_rejected.qualification_fingerprint
    if special_rejection then
      verify_exact_fields(selection, {
        selection_key = true, candidate_id = true, alternative_id = true, action = true,
        reason = true, design_fingerprint = true, qualification_fingerprint = true,
        policy = true, deferred_rejection = true
      }, "deferred rejected current selection")
      verify_exact_fields(selection.deferred_rejection, {
        state = true, selection_key = true, reason = true, primary_alternative_id = true,
        primary_design_fingerprint = true, primary_qualification_fingerprint = true
      }, "deferred rejected selection provenance")
    elseif not acceptable
      or alternative.action ~= selection.action
      or alternative.design_fingerprint ~= selection.design_fingerprint
      or alternative.qualification_fingerprint ~= selection.qualification_fingerprint then
      error("TechnologyCatalog current selection is invalid or rejected.", 2)
    end
    local selections = selections_by_candidate[selection.candidate_id] or {}
    table.insert(selections, selection)
    selections_by_candidate[selection.candidate_id] = selections
  end
  for candidate_id, primary in pairs(deferred_primaries) do
    local selections = selections_by_candidate[candidate_id] or {}
    local selection = selections[1]
    if #selections ~= 1 or not selection
      or selection.alternative_id ~= primary.alternative_id
      or selection.action ~= primary.action
      or selection.design_fingerprint ~= primary.design_fingerprint
      or selection.qualification_fingerprint ~= primary.qualification_fingerprint then
      error("TechnologyCatalog deferred diagnostic primary selection is invalid: " .. candidate_id, 2)
    end
  end
  for candidate_id, primary in pairs(deferred_rejected_primaries) do
    local selection = (selections_by_candidate[candidate_id] or {})[1]
    if #(selections_by_candidate[candidate_id] or {}) ~= 1 or not selection
      or selection.alternative_id ~= primary.alternative_id
      or selection.action ~= "reject"
      or selection.design_fingerprint ~= primary.design_fingerprint
      or selection.qualification_fingerprint ~= primary.qualification_fingerprint then
      error("TechnologyCatalog deferred rejected diagnostic primary selection is invalid: " .. candidate_id, 2)
    end
  end
  if options.verify_fingerprints ~= false then
    if catalog.candidate_catalog_fingerprint ~= fingerprint.of(model.candidate_catalog_material(catalog.candidates))
      or catalog.qualification_catalog_fingerprint ~= fingerprint.of(model.qualification_catalog_material(catalog.qualifications))
      or catalog.preselection_catalog_fingerprint ~= fingerprint.of(model.preselection_material(catalog))
      or catalog.selection_fingerprint ~= fingerprint.of(catalog.current_selections)
      or catalog.catalog_fingerprint ~= fingerprint.of(model.catalog_material(catalog)) then
      error("TechnologyCatalog schema 4 fingerprints are invalid.", 2)
    end
  end
  return true
end

function M.verify_untrusted(catalog)
  model.authority.verify_untrusted(catalog, verify, model.trust_identity(catalog or {}))
  return true
end

function M.validate(catalog)
  return M.verify_untrusted(catalog)
end

function M.assert_owned(catalog)
  return verify(catalog, {trusted_children = true, verify_fingerprints = false})
end

function M.assert_newly_constructed(catalog)
  -- Constructor output must still be authority-owned. assert_owned performs
  -- those cheap identity checks without recanonicalizing each child.
  return M.assert_owned(catalog)
end

function M.assert_trusted(catalog)
  return model.authority.assert_trusted(catalog, model.trust_identity_unchanged)
end

function M.is_trusted(catalog)
  return model.authority.is_trusted(catalog)
end

return M
