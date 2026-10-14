local probe = require("probe")
local recipe_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_facts")
local mir_version = mods and mods["more-infinite-research"] or nil
local compilation_module
if mir_version == "3.1.9" then
  compilation_module = "__more-infinite-research__.prototypes.mir.planner.compilation_plan"
elseif mir_version == "3.2.0"
    or mir_version == "3.2.1"
    or mir_version == "3.2.2"
    or mir_version == "3.2.3"
    or mir_version == "3.2.4"
    or mir_version == "3.2.5"
    or mir_version == "3.2.9"
    or mir_version == "3.2.10"
    or mir_version == "3.2.11"
    or mir_version == "2.5.11"
    or mir_version == "4.0.21000"
    or mir_version == "4.0.20000"
    or mir_version == "4.1.21000"
    or mir_version == "4.1.20000"
    or mir_version == "4.2.21000"
    or mir_version == "4.2.20000"
    or mir_version == "4.2.21001"
    or mir_version == "4.2.20001"
    or mir_version == "4.3.21000"
    or mir_version == "4.3.20000"
    or mir_version == "4.4.21000"
    or mir_version == "4.4.20000" then
  compilation_module = "__more-infinite-research__.prototypes.mir.pipeline.compiler_orchestrator"
else
  error("performance probe does not govern MIR version " .. tostring(mir_version))
end
local compilation_plan = require(compilation_module)
local graph_safety = require("__more-infinite-research__.prototypes.mir.emit.technology_graph_safety")
local commands = require("__more-infinite-research__.prototypes.mir.pipeline.commands")

-- Retain bounded timing boundaries only around current public compiler phases.
-- The retired science discovery solver has no probe hooks or counters here.
local function trace(module_name, method, label)
  local module = require("__more-infinite-research__." .. module_name)
  local original = module[method]
  if type(original) ~= "function" then error("missing performance step " .. label) end
  module[method] = function(...)
    log("[MIR_PERFORMANCE_STEP] start " .. label)
    local results = table.pack(original(...))
    log("[MIR_PERFORMANCE_STEP] end " .. label)
    return table.unpack(results, 1, results.n)
  end
end
trace("prototypes.mir.planner.stream_compiler", "compile_view", "stream-compilation")
trace("prototypes.mir.planner.base_continuations", "plan_all", "base-continuations")
trace("prototypes.mir.planner.compilation_plan", "finalize", "plan-finalization")
trace("prototypes.mir.planner.compiler", "compile", "pure-compilation")

local snapshot_recorded = false
for _, name in ipairs({
  "get", "view", "index_view", "for_each", "summary", "fingerprint", "candidate_names",
  "recipes_by_output", "recipes_by_output_view", "recipes_by_ingredient", "recipes_by_category",
  "all_names", "snapshot", "scan_count"
}) do
  local original = recipe_facts[name]
  if type(original) == "function" then
    recipe_facts[name] = function(...)
      if snapshot_recorded then return original(...) end
      snapshot_recorded = true
      return probe.measure("snapshot", original, ...)
    end
  end
end

local original_compile = compilation_plan.compile
compilation_plan.compile = function(...)
  return probe.measure("planning", original_compile, ...)
end

local original_graph_assertion = graph_safety.assert_registered_technologies
graph_safety.assert_registered_technologies = function(...)
  return probe.measure("graph", original_graph_assertion, ...)
end

local original_run = commands.run
commands.run = function(id, ...)
  if id == "assert-plan-output" or id == "assert-technology-safety" then
    return probe.measure("postconditions", original_run, id, ...)
  end
  return original_run(id, ...)
end
