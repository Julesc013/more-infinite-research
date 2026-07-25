local M = {}
local commands = require("prototypes.mir.pipeline.commands")
local context = commands.new_context()

function M.apply_compatibility_repairs() commands.run("compatibility-repairs", context) end
function M.sanitize_input_technology_effects() commands.run("sanitize-input-technology-effects", context) end
function M.apply_module_permissions() commands.run("module-permissions", context) end
function M.apply_prototype_limits() commands.run("prototype-limits", context) end
function M.apply_pipeline_extent() commands.run("pipeline-extent", context) end
function M.prepare_competing_productivity() commands.run("prepare-competing-productivity", context) end
function M.prepare_competing_base_extensions() commands.run("prepare-competing-base-extensions", context) end
function M.emit_streams() commands.run("emit-streams", context) end
function M.apply_competing_productivity() commands.run("apply-competing-productivity", context) end
function M.emit_base_extensions() commands.run("emit-base-extensions", context) end
function M.apply_competing_base_extensions() commands.run("apply-competing-base-extensions", context) end
function M.apply_weapon_speed_adjustments() commands.run("weapon-speed-adjustments", context) end
function M.apply_max_level_control() commands.run("max-level-control", context) end
function M.assert_registered_technology_safety() commands.run("assert-technology-safety", context) end
function M.publish_compiler_artifacts() commands.run("publish-compiler-artifacts", context) end

function M.emit_compatibility_planner()
  require("prototypes.mir.compatibility.planner").emit()
end

function M.flush_diagnostics()
  require("prototypes.mir.report.diagnostics_sink").flush()
end

return M
