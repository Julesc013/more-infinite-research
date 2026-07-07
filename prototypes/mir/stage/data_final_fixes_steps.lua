local M = {}

function M.apply_pipeline_extent()
  local pipeline_extent_multiplier = require("prototypes.pipeline-extent-settings").multiplier()
  if pipeline_extent_multiplier ~= 1 then
    require("prototypes.pipeline-extent").apply(pipeline_extent_multiplier)
  end
end

function M.prepare_competing_productivity()
  require("prototypes.compat.competing-productivity").prepare()
end

function M.emit_streams()
  require("prototypes.mir.planner.stream_compiler").run()
end

function M.apply_competing_productivity()
  require("prototypes.compat.competing-productivity").apply()
end

function M.apply_competing_base_extensions()
  require("prototypes.compat.competing-base-extensions").apply()
end

function M.emit_base_extensions()
  require("prototypes.base-tech-extensions")
end

function M.apply_weapon_speed_adjustments()
  require("prototypes.weapon-speed-adjustments")
end

function M.apply_max_level_control()
  require("prototypes.max-level-control")
end

function M.emit_compatibility_planner()
  require("prototypes.compat.planner").emit()
end

function M.assert_registered_technology_effects()
  require("prototypes.technology-effect-safety").assert_registered_technology_effects()
end

function M.flush_diagnostics()
  require("prototypes.diagnostics").flush()
end

return M
