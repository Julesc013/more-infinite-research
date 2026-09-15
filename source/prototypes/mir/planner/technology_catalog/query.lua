local deepcopy = require("prototypes.mir.core.deepcopy")
local model = require("prototypes.mir.planner.technology_catalog.model")
local validate = require("prototypes.mir.planner.technology_catalog.validate")

local M = {}

function M.authority_projection(catalog)
  if validate.is_trusted(catalog) then validate.assert_trusted(catalog) else validate.verify_untrusted(catalog) end
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

function M.snapshot(catalog)
  if validate.is_trusted(catalog) then validate.assert_trusted(catalog) else validate.verify_untrusted(catalog) end
  model.authority.count_snapshot()
  model.authority.count_full_copy()
  return deepcopy(catalog)
end

return M
