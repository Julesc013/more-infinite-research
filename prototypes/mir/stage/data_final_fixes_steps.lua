local M = {}
local commands = require("prototypes.mir.pipeline.commands")

function M.apply_compatibility_repairs() commands.run("compatibility-repairs") end
function M.apply_module_permissions() commands.run("module-permissions") end
function M.apply_prototype_limits() commands.run("prototype-limits") end
function M.apply_pipeline_extent() commands.run("pipeline-extent") end
function M.prepare_competing_productivity() commands.run("prepare-competing-productivity") end
function M.prepare_competing_base_extensions() commands.run("prepare-competing-base-extensions") end
function M.emit_streams() commands.run("emit-streams") end
function M.apply_competing_productivity() commands.run("apply-competing-productivity") end
function M.emit_base_extensions() commands.run("emit-base-extensions") end
function M.apply_competing_base_extensions() commands.run("apply-competing-base-extensions") end
function M.apply_weapon_speed_adjustments() commands.run("weapon-speed-adjustments") end
function M.apply_max_level_control() commands.run("max-level-control") end
function M.assert_registered_technology_safety() commands.run("assert-technology-safety") end
function M.publish_compiler_artifacts() commands.run("publish-compiler-artifacts") end

function M.emit_compatibility_planner()
  require("prototypes.mir.compatibility.planner").emit()
end

function M.flush_diagnostics()
  require("prototypes.mir.report.diagnostics_sink").flush()
end

return M
