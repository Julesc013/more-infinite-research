local M = {}
local steps = require("prototypes.mir.stage.data_final_fixes_steps")

function M.run()
  steps.apply_compatibility_repairs()
  steps.apply_module_permissions()
  steps.apply_prototype_limits()
  steps.apply_pipeline_extent()
  steps.prepare_competing_productivity()
  steps.emit_streams()
  steps.apply_competing_productivity()
  steps.apply_competing_base_extensions()
  steps.emit_base_extensions()
  steps.apply_weapon_speed_adjustments()
  steps.apply_max_level_control()

  require("prototypes.mir.compatibility.diagnostics.registry").emit_all()
  require("prototypes.mir.planner.compiler").emit()
  steps.emit_compatibility_planner()

  steps.assert_registered_technology_safety()
  steps.flush_diagnostics()
end

return M
