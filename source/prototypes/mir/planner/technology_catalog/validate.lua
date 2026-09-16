local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_candidate = require("prototypes.mir.domain.technology.technology_candidate")
local technology_qualification = require("prototypes.mir.domain.technology.technology_qualification")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local safety_qualification = require("prototypes.mir.domain.technology.safety_qualification")
local indexer = require("prototypes.mir.planner.technology_catalog.index")
local model = require("prototypes.mir.planner.technology_catalog.model")

local M = {}

local function verify(catalog, options)
  options = options or {}
  if type(catalog) ~= "table" or catalog.schema ~= model.SCHEMA
    or type(catalog.candidates) ~= "table" or type(catalog.qualifications) ~= "table"
    or type(catalog.alternative_qualifications) ~= "table" or type(catalog.current_selections) ~= "table"
    or not model.PHASES[catalog.phase]
    or catalog.mutation_authority ~= false or catalog.selection_authority ~= "deterministic-policy-v2"
    or type(catalog.generation_plan_fingerprint) ~= "string"
    or type(catalog.compilation_plan_fingerprint) ~= "string" then
    error("TechnologyCatalog schema 3 canonical inventory is required.", 2)
  end
  if type(catalog.base_candidates) ~= "table" then
    error("TechnologyCatalog base continuation inventory is required.", 2)
  end
  local indexes = indexer.new()
  for _, qualification in ipairs(catalog.qualifications) do
    if not options.trusted_children_verified then
      if options.trusted_children then technology_qualification.assert_trusted(qualification)
      else technology_qualification.verify_untrusted(qualification) end
    end
    indexer.add_qualification(indexes, qualification)
  end
  for _, candidate in ipairs(catalog.candidates) do
    if not options.trusted_children_verified then
      if options.trusted_children then technology_candidate.assert_trusted(candidate)
      else technology_candidate.verify_untrusted(candidate) end
    end
    if type(candidate.selection_key) ~= "string" or type(candidate.alternatives) ~= "table" then
      error("TechnologyCatalog candidate alternatives are invalid.", 2)
    end
    for _, alternative in ipairs(candidate.alternatives) do
      local key = indexer.alternative_key(candidate.candidate_id, alternative.alternative_id)
      if indexes.alternatives[key] then error("TechnologyCatalog alternative is duplicated: " .. key, 2) end
      if not indexer.qualification(indexes, alternative.qualification_fingerprint) then
        error("TechnologyCatalog alternative lacks an exact qualification: " .. key, 2)
      end
      if type(alternative.technology_design) ~= "table"
        or alternative.technology_design.design_fingerprint ~= alternative.design_fingerprint then
        error("TechnologyCatalog alternative lacks its exact preserved TechnologyDesign: " .. key, 2)
      end
      if not options.trusted_children_verified then
        if options.trusted_children then technology_design.assert_trusted(alternative.technology_design)
        else technology_design.verify_untrusted(alternative.technology_design) end
      end
      indexer.add_alternative(indexes, candidate.candidate_id, alternative)
    end
  end
  if catalog.phase == "final" then
    for _, qualification in ipairs(catalog.qualifications) do
      for _, gate_name in ipairs(safety_qualification.schema_authority().gate_order) do
        local gate = qualification.hard_gates[gate_name]
        local resolved = gate and (options.trusted_children_verified
          and (gate.status == "passed" or gate.status == "failed" or gate.status == "not-applicable")
          or gate_contract.is_authoritatively_resolved(gate))
        if not resolved then
          error("TechnologyCatalog final qualification has an unresolved hard gate: "
            .. qualification.candidate_id .. "/" .. gate_name, 2)
        end
      end
    end
  end
  for _, mapping in ipairs(catalog.alternative_qualifications) do
    local alternative = indexer.alternative(indexes, mapping.candidate_id, mapping.alternative_id)
    if not alternative or alternative.design_fingerprint ~= mapping.design_fingerprint
      or alternative.qualification_fingerprint ~= mapping.qualification_fingerprint
      or alternative.qualification_decision ~= mapping.decision then
      error("TechnologyCatalog alternative qualification mapping is invalid.", 2)
    end
  end
  for _, selection in ipairs(catalog.current_selections) do
    local alternative = indexer.alternative(indexes, selection.candidate_id, selection.alternative_id)
    local acceptable = alternative and (alternative.qualification_decision == "qualified"
      or (catalog.phase ~= "final" and alternative.qualification_decision == "proposal"))
    if not acceptable
      or alternative.action ~= selection.action
      or alternative.design_fingerprint ~= selection.design_fingerprint
      or alternative.qualification_fingerprint ~= selection.qualification_fingerprint then
      error("TechnologyCatalog current selection is invalid or rejected.", 2)
    end
  end
  if options.verify_fingerprints ~= false then
    if catalog.candidate_catalog_fingerprint ~= fingerprint.of(model.candidate_catalog_material(catalog.candidates))
      or catalog.qualification_catalog_fingerprint ~= fingerprint.of(model.qualification_catalog_material(catalog.qualifications))
      or catalog.preselection_catalog_fingerprint ~= fingerprint.of(model.preselection_material(catalog))
      or catalog.selection_fingerprint ~= fingerprint.of(catalog.current_selections)
      or catalog.catalog_fingerprint ~= fingerprint.of(model.catalog_material(catalog)) then
      error("TechnologyCatalog schema 3 fingerprints are invalid.", 2)
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
  return verify(catalog, {
    trusted_children = true,
    trusted_children_verified = true,
    verify_fingerprints = false
  })
end

function M.assert_trusted(catalog)
  return model.authority.assert_trusted(catalog, model.trust_identity_unchanged)
end

function M.is_trusted(catalog)
  return model.authority.is_trusted(catalog)
end

return M
