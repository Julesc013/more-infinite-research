local quality = require("prototypes.mir.domain.technology.technology_quality_assessment")

return {
  schema_authority = quality.schema_authority,
  validate = quality.validate,
  new = quality.new
}
