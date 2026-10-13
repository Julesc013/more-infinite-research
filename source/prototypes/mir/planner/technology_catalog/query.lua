local deepcopy = require("prototypes.mir.core.deepcopy")
local model = require("prototypes.mir.planner.technology_catalog.model")
local validate = require("prototypes.mir.planner.technology_catalog.validate")

local M = {}

local function validate_catalog(catalog)
  if validate.is_trusted(catalog) then validate.assert_trusted(catalog) else validate.verify_untrusted(catalog) end
  return catalog
end

function M.authority_projection(catalog)
  validate_catalog(catalog)
  return {
    schema = catalog.schema,
    phase = catalog.phase,
    candidate_catalog_fingerprint = catalog.candidate_catalog_fingerprint,
    qualification_catalog_fingerprint = catalog.qualification_catalog_fingerprint,
    preselection_catalog_fingerprint = catalog.preselection_catalog_fingerprint,
    selection_fingerprint = catalog.selection_fingerprint,
    catalog_fingerprint = catalog.catalog_fingerprint
  }
end

function M.require_full_diagnostics(catalog)
  validate_catalog(catalog)
  local evaluation = catalog.alternative_evaluation or {}
  if evaluation.mode ~= "full-diagnostics" or evaluation.complete ~= true
    or evaluation.deferred_diagnostic_alternatives ~= 0 then
    error("TechnologyCatalog full diagnostics are required; player-deferred diagnostics are not an export inventory.", 2)
  end
  return catalog
end

function M.snapshot(catalog)
  validate_catalog(catalog)
  model.authority.count_snapshot()
  model.authority.count_full_copy()
  return deepcopy(catalog)
end

return M
