local pipeline_extent_multiplier = require("prototypes.pipeline-extent-settings").multiplier()
if pipeline_extent_multiplier ~= 1 then
  require("prototypes.pipeline-extent").apply(pipeline_extent_multiplier)
end
require("prototypes.tech-gen")
require("prototypes.compat.competing-productivity").apply()
require("prototypes.compat.competing-base-extensions").apply()
require("prototypes.base-tech-extensions")
require("prototypes.weapon-speed-adjustments")
require("prototypes.max-level-control")
require("prototypes.technology-effect-safety").assert_registered_technology_effects()
require("prototypes.diagnostics").flush()
