local M = {}
local legacy = require("prototypes.mir.legacy.data_final_fixes")

function M.run()
  legacy.apply_pipeline_extent()
  legacy.prepare_competing_productivity()
  legacy.emit_legacy_streams()
  legacy.apply_competing_productivity()
  legacy.apply_competing_base_extensions()
  legacy.emit_base_extensions()
  legacy.apply_weapon_speed_adjustments()
  legacy.apply_max_level_control()

  require("prototypes.mir.compatibility.diagnostics.registry").emit_all()
  require("prototypes.mir.planner.compiler").emit()
  legacy.emit_compatibility_planner()

  legacy.assert_registered_technology_effects()
  legacy.flush_diagnostics()
end

return M
