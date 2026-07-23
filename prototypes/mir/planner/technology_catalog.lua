local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_candidate = require("prototypes.mir.domain.technology.technology_candidate")
local technology_qualification = require("prototypes.mir.domain.technology.technology_qualification")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local selection_policy = require("prototypes.mir.planner.technology_selection_policy")

local M = {}
local SCHEMA = 2

local function alternative_id(design)
  local target = design.materialization.target or design.technology_id or design.candidate_id
  return design.materialization.kind .. ":" .. tostring(target)
end

local function selection_key(row)
  return tostring(row.stream_key) .. ":" .. tostring(row.manifest_id or row.stream_key)
end

local function safe_diagnostic_row(row)
  local copy = deepcopy(row)
  copy.action = "diagnose"
  copy.reason = nil
  copy.gates = {}
  for gate_name in pairs(row.gates or {}) do
    copy.gates[gate_name] = gate_contract.not_applicable(
      "candidate-catalog:diagnostic-alternative",
      {"candidate-catalog:safe-diagnostic-alternative"}
    )
  end
  return copy
end

local function alternative_record(design, qualification, action)
  return {
    alternative_id = alternative_id(design),
    action = action,
    materialization = deepcopy(design.materialization),
    design_fingerprint = design.design_fingerprint,
    prototype_fingerprint = design.prototype_fingerprint,
    qualification_fingerprint = qualification.qualification_fingerprint,
    qualification_decision = qualification.decision
  }
end

local function preselection_material(catalog)
  return {
    schema = catalog.schema,
    candidates = catalog.candidates,
    qualifications = catalog.qualifications,
    alternative_qualifications = catalog.alternative_qualifications,
    context_fingerprint = catalog.context_fingerprint,
    mutation_authority = catalog.mutation_authority,
    selection_authority = catalog.selection_authority
  }
end

local function catalog_material(catalog)
  return {
    preselection_catalog_fingerprint = catalog.preselection_catalog_fingerprint,
    current_selections = catalog.current_selections,
    selection_fingerprint = catalog.selection_fingerprint
  }
end

function M.from_preselection_rows(rows, context_material, options)
  options = options or {}
  local candidates, qualifications, alternative_qualifications, by_id = {}, {}, {}, {}
  for _, row in ipairs(rows or {}) do
    local primary_design = row.technology_design or technology_design.from_generation_row(row)
    if not options.trusted_designs then technology_design.validate(primary_design) end
    local diagnostic_design = technology_design.as_diagnostic_alternative(primary_design, row.reason)
    local diagnostic_row = safe_diagnostic_row(row)
    local designs = {}
    if row.action == "emit" or row.action == "adopt" then
      table.insert(designs, {design = primary_design, row = row, action = row.action})
    end
    table.insert(designs, {design = diagnostic_design, row = diagnostic_row, action = "diagnose"})

    local candidate = technology_candidate.from_design(primary_design, row, {validated = true})
    if by_id[candidate.candidate_id] then
      error("TechnologyCandidate identity has contradictory preselection rows: " .. candidate.candidate_id, 2)
    end
    candidate.alternatives = {}
    candidate.selection_key = selection_key(row)
    by_id[candidate.candidate_id] = candidate
    table.insert(candidates, candidate)

    for _, entry in ipairs(designs) do
      local qualification = technology_qualification.from_design(
        entry.design,
        entry.row,
        {status = "UNMEASURED"},
        {validated = true}
      )
      local alternative = alternative_record(entry.design, qualification, entry.action)
      table.insert(candidate.alternatives, alternative)
      table.insert(qualifications, qualification)
      table.insert(alternative_qualifications, {
        candidate_id = candidate.candidate_id,
        alternative_id = alternative.alternative_id,
        design_fingerprint = alternative.design_fingerprint,
        qualification_fingerprint = alternative.qualification_fingerprint,
        decision = alternative.qualification_decision
      })
    end
    table.sort(candidate.alternatives, function(left, right) return left.alternative_id < right.alternative_id end)
  end
  table.sort(candidates, function(left, right) return left.candidate_id < right.candidate_id end)
  table.sort(qualifications, function(left, right)
    if left.candidate_id ~= right.candidate_id then return left.candidate_id < right.candidate_id end
    return left.design_fingerprint < right.design_fingerprint
  end)
  table.sort(alternative_qualifications, function(left, right)
    if left.candidate_id ~= right.candidate_id then return left.candidate_id < right.candidate_id end
    return left.alternative_id < right.alternative_id
  end)
  local catalog = {
    schema = SCHEMA,
    candidates = candidates,
    qualifications = qualifications,
    alternative_qualifications = alternative_qualifications,
    current_selections = {},
    context_fingerprint = fingerprint.of(context_material or {}),
    mutation_authority = false,
    selection_authority = "deterministic-policy-v1"
  }
  catalog.candidate_catalog_fingerprint = fingerprint.of(candidates)
  catalog.qualification_catalog_fingerprint = fingerprint.of(qualifications)
  catalog.preselection_catalog_fingerprint = fingerprint.of(preselection_material(catalog))
  catalog.selection_fingerprint = fingerprint.of(catalog.current_selections)
  catalog.catalog_fingerprint = fingerprint.of(catalog_material(catalog))
  M.validate(catalog)
  return catalog
end

function M.bind_selections(catalog, rows)
  M.validate(catalog)
  local result = deepcopy(catalog)
  local selections = selection_policy.select(result, rows)
  result.current_selections = selections
  result.selection_fingerprint = fingerprint.of(selections)
  result.catalog_fingerprint = fingerprint.of(catalog_material(result))
  M.validate(result)
  return result
end

function M.from_generation_rows(rows, context_material, options)
  return M.bind_selections(M.from_preselection_rows(rows, context_material, options), rows)
end

function M.validate(catalog)
  if type(catalog) ~= "table" or catalog.schema ~= SCHEMA
    or type(catalog.candidates) ~= "table" or type(catalog.qualifications) ~= "table"
    or type(catalog.alternative_qualifications) ~= "table" or type(catalog.current_selections) ~= "table"
    or catalog.mutation_authority ~= false or catalog.selection_authority ~= "deterministic-policy-v1" then
    error("TechnologyCatalog schema 2 canonical preselection inventory is required.", 2)
  end
  local alternatives, qualifications = {}, {}
  for _, qualification in ipairs(catalog.qualifications) do
    technology_qualification.validate(qualification)
    qualifications[qualification.qualification_fingerprint] = qualification
  end
  for _, candidate in ipairs(catalog.candidates) do
    technology_candidate.validate(candidate)
    if type(candidate.selection_key) ~= "string" or type(candidate.alternatives) ~= "table" then
      error("TechnologyCatalog candidate alternatives are invalid.", 2)
    end
    for _, alternative in ipairs(candidate.alternatives) do
      local key = candidate.candidate_id .. "/" .. alternative.alternative_id
      if alternatives[key] then error("TechnologyCatalog alternative is duplicated: " .. key, 2) end
      if not qualifications[alternative.qualification_fingerprint] then
        error("TechnologyCatalog alternative lacks an exact qualification: " .. key, 2)
      end
      alternatives[key] = alternative
    end
  end
  for _, mapping in ipairs(catalog.alternative_qualifications) do
    local alternative = alternatives[mapping.candidate_id .. "/" .. mapping.alternative_id]
    if not alternative or alternative.design_fingerprint ~= mapping.design_fingerprint
      or alternative.qualification_fingerprint ~= mapping.qualification_fingerprint
      or alternative.qualification_decision ~= mapping.decision then
      error("TechnologyCatalog alternative qualification mapping is invalid.", 2)
    end
  end
  for _, selection in ipairs(catalog.current_selections) do
    local alternative = alternatives[selection.candidate_id .. "/" .. selection.alternative_id]
    if not alternative or (alternative.qualification_decision ~= "qualified"
        and alternative.qualification_decision ~= "proposal")
      or alternative.action ~= selection.action
      or alternative.design_fingerprint ~= selection.design_fingerprint
      or alternative.qualification_fingerprint ~= selection.qualification_fingerprint then
      error("TechnologyCatalog current selection is invalid or rejected.", 2)
    end
  end
  if catalog.candidate_catalog_fingerprint ~= fingerprint.of(catalog.candidates)
    or catalog.qualification_catalog_fingerprint ~= fingerprint.of(catalog.qualifications)
    or catalog.preselection_catalog_fingerprint ~= fingerprint.of(preselection_material(catalog))
    or catalog.selection_fingerprint ~= fingerprint.of(catalog.current_selections)
    or catalog.catalog_fingerprint ~= fingerprint.of(catalog_material(catalog)) then
    error("TechnologyCatalog schema 2 fingerprints are invalid.", 2)
  end
  return true
end

function M.snapshot(catalog)
  M.validate(catalog)
  return deepcopy(catalog)
end

return M
