local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_candidate = require("prototypes.mir.domain.technology.technology_candidate")
local technology_qualification = require("prototypes.mir.domain.technology.technology_qualification")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}

local function alternative_id(design)
  local target = design.materialization.target or design.technology_id or design.candidate_id
  return design.materialization.kind .. ":" .. tostring(target)
end

function M.from_generation_rows(rows, context_material)
  local candidates, qualifications, by_id = {}, {}, {}
  for _, row in ipairs(rows or {}) do
    if not row.technology_design then
      error("Technology catalog row lacks TechnologyDesign: " .. tostring(row.stream_key), 2)
    end
    technology_design.validate(row.technology_design)
    local candidate = technology_candidate.from_design(row.technology_design, row)
    local existing = by_id[candidate.candidate_id]
    if existing and existing.candidate_fingerprint ~= candidate.candidate_fingerprint then
      error("TechnologyCandidate identity has contradictory discovery material: " .. candidate.candidate_id, 2)
    end
    if not existing then
      candidate.alternatives = {}
      by_id[candidate.candidate_id] = candidate
      table.insert(candidates, candidate)
    end
    table.insert(by_id[candidate.candidate_id].alternatives, {
      alternative_id = alternative_id(row.technology_design),
      action = row.action,
      materialization = deepcopy(row.technology_design.materialization),
      design_fingerprint = row.technology_design.design_fingerprint,
      prototype_fingerprint = row.technology_design.prototype_fingerprint,
      qualification_fingerprint = row.technology_design.qualification_fingerprint
    })
    table.insert(qualifications, technology_qualification.from_design(row.technology_design, row))
  end
  table.sort(candidates, function(left, right) return left.candidate_id < right.candidate_id end)
  for _, candidate in ipairs(candidates) do
    table.sort(candidate.alternatives, function(left, right) return left.alternative_id < right.alternative_id end)
  end
  table.sort(qualifications, function(left, right)
    if left.candidate_id ~= right.candidate_id then return left.candidate_id < right.candidate_id end
    return left.design_fingerprint < right.design_fingerprint
  end)
  local catalog = {
    schema = 1,
    candidates = candidates,
    qualifications = qualifications,
    context_fingerprint = fingerprint.of(context_material or {})
  }
  catalog.candidate_catalog_fingerprint = fingerprint.of(candidates)
  catalog.qualification_catalog_fingerprint = fingerprint.of(qualifications)
  catalog.catalog_fingerprint = fingerprint.of({
    candidates = catalog.candidate_catalog_fingerprint,
    qualifications = catalog.qualification_catalog_fingerprint,
    context = catalog.context_fingerprint
  })
  return catalog
end

function M.validate(catalog)
  if type(catalog) ~= "table" or catalog.schema ~= 1
    or type(catalog.candidates) ~= "table" or type(catalog.qualifications) ~= "table" then
    error("Technology catalog schema 1 artifact is required.", 2)
  end
  for _, candidate in ipairs(catalog.candidates) do technology_candidate.validate(candidate) end
  for _, qualification in ipairs(catalog.qualifications) do technology_qualification.validate(qualification) end
  if catalog.candidate_catalog_fingerprint ~= fingerprint.of(catalog.candidates)
    or catalog.qualification_catalog_fingerprint ~= fingerprint.of(catalog.qualifications)
    or catalog.catalog_fingerprint ~= fingerprint.of({
      candidates = catalog.candidate_catalog_fingerprint,
      qualifications = catalog.qualification_catalog_fingerprint,
      context = catalog.context_fingerprint
    }) then
    error("Technology catalog fingerprints are invalid.", 2)
  end
  return true
end

function M.snapshot(catalog)
  M.validate(catalog)
  return deepcopy(catalog)
end

return M
