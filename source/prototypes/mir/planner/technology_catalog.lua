local build = require("prototypes.mir.planner.technology_catalog.build")
local validate = require("prototypes.mir.planner.technology_catalog.validate")
local query = require("prototypes.mir.planner.technology_catalog.query")

return {
  from_preselection_rows = build.from_preselection_rows,
  bind_selections = build.bind_selections,
  finalize = build.finalize,
  from_generation_rows = build.from_generation_rows,
  verify_untrusted = validate.verify_untrusted,
  validate = validate.validate,
  assert_owned = validate.assert_owned,
  assert_trusted = validate.assert_trusted,
  is_trusted = validate.is_trusted,
  authority_projection = query.authority_projection,
  snapshot = query.snapshot
}
