local context_construction = require("prototypes.mir.pipeline.compiler_orchestrator.context_construction")
local phase_invocation = require("prototypes.mir.pipeline.compiler_orchestrator.phase_invocation")
local contract_checks = require("prototypes.mir.pipeline.compiler_orchestrator.contract_checks")
local publication = require("prototypes.mir.pipeline.compiler_orchestrator.publication")

local M = {}

function M.compile(context) return context_construction.compile(context) end
function M.apply_streams(context) return phase_invocation.apply_streams(context) end
function M.apply_base_extensions(context) return phase_invocation.apply_base_extensions(context) end
function M.snapshot(context) return contract_checks.snapshot(context) end
function M.assert_output(context) return contract_checks.assert_output(context) end
function M.publish(context) return publication.publish(context) end

return M
