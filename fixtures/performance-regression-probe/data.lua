local probe = require("probe")
local recipe_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_facts")
local compilation_plan = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_orchestrator")
local graph_safety = require("__more-infinite-research__.prototypes.mir.emit.technology_graph_safety")
local commands = require("__more-infinite-research__.prototypes.mir.pipeline.commands")

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
