local context_construction = require("prototypes.mir.pipeline.compiler_orchestrator.context_construction")
local base_continuation_executor = require("prototypes.mir.emit.base_continuation_executor")
local stream_executor = require("prototypes.mir.emit.stream_executor")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local mutation_journal = require("prototypes.mir.domain.compiler.mutation_journal")

local M = {}

function M.apply_streams(context)
  context = context or compiler_context.current()
  local plan = context_construction.compile(context)
  local journal = context:state_view("mutation_journal", function()
    return mutation_journal.new(plan.transformation_plan)
  end)
  stream_executor.apply(plan.stream_plan, plan.transformation_plan, journal)
end

function M.apply_base_extensions(context)
  context = context or compiler_context.current()
  local plan = context_construction.compile(context)
  local journal = context:state_view("mutation_journal", function()
    return mutation_journal.new(plan.transformation_plan)
  end)
  base_continuation_executor.apply_plan(
    plan.base_extension_operations, plan.transformation_plan, journal)
end

return M
