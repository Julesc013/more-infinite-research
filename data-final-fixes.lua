local pipeline_extent_setting = settings
  and settings.startup
  and settings.startup["mir-pipeline-extent-multiplier"]
local pipeline_extent_multiplier = pipeline_extent_setting and tonumber(pipeline_extent_setting.value) or 1
if pipeline_extent_multiplier > 1 then
  require("prototypes.pipeline-extent").apply(pipeline_extent_multiplier)
end
require("prototypes.tech-gen")
require("prototypes.compat.competing-productivity").apply()
require("prototypes.compat.competing-base-extensions").apply()
require("prototypes.base-tech-extensions")
require("prototypes.weapon-speed-adjustments")
require("prototypes.max-level-control")
require("prototypes.diagnostics").flush()
