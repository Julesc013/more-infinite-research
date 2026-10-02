-- Observe the unmodified package through Factorio's development instrument
-- mode. Keep this state outside package.loaded: 2.0 resets that cache between
-- data files. Only MIR's four governed measurement boundaries are wrapped.
local probe = require("probe")
rawset(_G, "__mir_performance_instrument_probe", probe)
local original_require = require
local attached = setmetatable({}, {__mode = "k"})
local snapshot_recorded = false
local paths = {
  ["prototypes.mir.index.recipe_facts"] = "snapshot",
  ["prototypes.mir.pipeline.compiler_orchestrator"] = "planning",
  ["prototypes.mir.planner.compilation_plan"] = "planning",
  ["prototypes.mir.emit.technology_graph_safety"] = "graph",
  ["prototypes.mir.pipeline.commands"] = "postconditions"
}

local function attach(module, phase)
  if type(module) ~= "table" or attached[module] then return end
  attached[module] = true
  if phase == "snapshot" then
    for _, name in ipairs({
      "get", "view", "index_view", "for_each", "summary", "fingerprint", "candidate_names",
      "recipes_by_output", "recipes_by_output_view", "recipes_by_ingredient", "recipes_by_category",
      "all_names", "snapshot", "scan_count"
    }) do
      local original = module[name]
      if type(original) == "function" then
        module[name] = function(...)
          if snapshot_recorded then return original(...) end
          snapshot_recorded = true
          return probe.measure("snapshot", original, ...)
        end
      end
    end
  elseif phase == "postconditions" then
    local original = module.run
    if type(original) ~= "function" then error("MIR performance command boundary is absent") end
    module.run = function(id, ...)
      if id == "assert-plan-output" or id == "assert-technology-safety" then
        return probe.measure(phase, original, id, ...)
      end
      return original(id, ...)
    end
  else
    local name = phase == "planning" and "compile" or "assert_registered_technologies"
    local original = module[name]
    if type(original) ~= "function" then error("MIR performance boundary is absent: " .. name) end
    module[name] = function(...) return probe.measure(phase, original, ...) end
  end
end

require = function(name)
  local caller = debug.getinfo(2, "S")
  local from_mir = caller and string.find(caller.source, "__more-infinite-research__", 1, true)
  local relative = string.gsub(name, "^__more%-infinite%-research__%.", "")
  local phase = paths[relative]
  local module = original_require(name)
  if phase and (from_mir or relative ~= name) then attach(module, phase) end
  return module
end
