local M = {}
local target_line = require("prototypes.mir.platform.factorio.target_line")

function M.apply_compatibility_repairs()
  if not target_line.feature_enabled("compatibility_repairs") then return end
  require("prototypes.mir.compatibility.repairs.factorio_2_1_recipe_schema").apply()
end

function M.apply_prototype_limits()
  if not target_line.feature_enabled("prototype_limits") then return end
  require("prototypes.mir.pipeline.prototype_limits").apply()
end

function M.apply_pipeline_extent()
  if not target_line.feature_enabled("pipeline_extent") then return end
  local pipeline_extent_multiplier = require("prototypes.mir.settings.pipeline_extent").multiplier()
  if pipeline_extent_multiplier ~= 1 then
    require("prototypes.mir.pipeline.extent").apply(pipeline_extent_multiplier)
  end
end

function M.prepare_competing_productivity()
  if not target_line.feature_enabled("recipe_productivity") then return end
  require("prototypes.mir.policy.competing_productivity").prepare()
end

function M.emit_streams()
  require("prototypes.mir.planner.stream_compiler").run()
end

function M.apply_competing_productivity()
  if not target_line.feature_enabled("recipe_productivity") then return end
  require("prototypes.mir.policy.competing_productivity").apply()
end

function M.apply_competing_base_extensions()
  require("prototypes.mir.policy.competing_base_extensions").apply()
end

function M.emit_base_extensions()
  require("prototypes.mir.emit.base_extensions").emit_all()
end

function M.apply_weapon_speed_adjustments()
  require("prototypes.mir.policy.weapon_speed").apply()
end

function M.apply_max_level_control()
  require("prototypes.mir.policy.max_level").apply()
end

function M.emit_compatibility_planner()
  require("prototypes.mir.compatibility.planner").emit()
end

function M.assert_registered_technology_effects()
  require("prototypes.mir.emit.effect_safety").assert_registered_technology_effects()
end

function M.assert_registered_technology_safety()
  require("prototypes.mir.emit.technology_graph_safety").assert_registered_technologies()
end

function M.flush_diagnostics()
  require("prototypes.mir.report.diagnostics_sink").flush()
end

return M
