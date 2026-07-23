local deepcopy = require("prototypes.mir.core.deepcopy")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

local commands = {
  ["compatibility-repairs"] = {
    kind = "mutation",
    requires_features = {"compatibility_repairs"},
    implementation = "prototypes/mir/compatibility/repairs/registry.lua",
    apply = function()
      require("prototypes.mir.compatibility.repairs.registry").apply()
    end
  },
  ["sanitize-input-technology-effects"] = {
    kind = "sanitation",
    requires_features = {},
    implementation = "prototypes/mir/emit/effect_safety.lua",
    apply = function(context)
      local ledger = require("prototypes.mir.emit.effect_safety")
        .sanitize_all_technology_effects({pass = "input"})
      context:record_artifact("input_sanitation_ledger", ledger)
    end
  },
  ["module-permissions"] = {
    kind = "mutation",
    requires_features = {"module_permissions"},
    implementation = "prototypes/mir/pipeline/module_permissions.lua",
    apply = function() require("prototypes.mir.pipeline.module_permissions").apply() end
  },
  ["prototype-limits"] = {
    kind = "mutation",
    requires_features = {"prototype_limits"},
    implementation = "prototypes/mir/pipeline/prototype_limits.lua",
    apply = function() require("prototypes.mir.pipeline.prototype_limits").apply() end
  },
  ["pipeline-extent"] = {
    kind = "mutation",
    requires_features = {"pipeline_extent"},
    implementation = "prototypes/mir/pipeline/extent.lua",
    apply = function()
      local value = require("prototypes.mir.settings.effective").get("mir-pipeline-extent-multiplier")
      local multiplier = require("prototypes.mir.settings.pipeline_extent").multiplier(value)
      if multiplier ~= 1 then require("prototypes.mir.pipeline.extent").apply(multiplier) end
    end
  },
  ["prepare-competing-productivity"] = {
    kind = "plan",
    requires_features = {"recipe_productivity"},
    implementation = "prototypes/mir/policy/competing_productivity.lua",
    apply = function() require("prototypes.mir.policy.competing_productivity").prepare() end
  },
  ["prepare-competing-base-extensions"] = {
    kind = "plan",
    requires_features = {},
    implementation = "prototypes/mir/policy/competing_base_extensions.lua",
    apply = function() require("prototypes.mir.policy.competing_base_extensions").prepare() end
  },
  ["compile-generation-plan"] = {
    kind = "plan",
    requires_features = {},
    implementation = "prototypes/mir/pipeline/compiler_orchestrator.lua",
    apply = function(context) require("prototypes.mir.pipeline.compiler_orchestrator").compile(context) end
  },
  ["emit-streams"] = {
    kind = "emission",
    requires_features = {},
    implementation = "prototypes/mir/emit/stream_executor.lua",
    apply = function(context) require("prototypes.mir.pipeline.compiler_orchestrator").apply_streams(context) end
  },
  ["apply-competing-productivity"] = {
    kind = "mutation",
    requires_features = {"recipe_productivity"},
    implementation = "prototypes/mir/pipeline/mutations/competing_productivity.lua",
    apply = function() require("prototypes.mir.pipeline.mutations.competing_productivity").apply() end
  },
  ["emit-base-extensions"] = {
    kind = "emission",
    requires_features = {},
    implementation = "prototypes/mir/planner/base_continuations.lua + prototypes/mir/emit/base_continuation_executor.lua",
    apply = function(context) require("prototypes.mir.pipeline.compiler_orchestrator").apply_base_extensions(context) end
  },
  ["apply-competing-base-extensions"] = {
    kind = "mutation",
    requires_features = {},
    implementation = "prototypes/mir/pipeline/mutations/competing_base_extensions.lua",
    apply = function() require("prototypes.mir.pipeline.mutations.competing_base_extensions").apply() end
  },
  ["weapon-speed-adjustments"] = {
    kind = "mutation",
    requires_features = {},
    implementation = "prototypes/mir/pipeline/mutations/weapon_speed.lua",
    apply = function() require("prototypes.mir.pipeline.mutations.weapon_speed").apply() end
  },
  ["max-level-control"] = {
    kind = "mutation",
    requires_features = {},
    implementation = "prototypes/mir/pipeline/mutations/max_level.lua",
    apply = function() require("prototypes.mir.pipeline.mutations.max_level").apply() end
  },
  ["assert-technology-safety"] = {
    kind = "assertion",
    requires_features = {},
    implementation = "prototypes/mir/emit/effect_safety.lua",
    apply = function(context)
      local ledger = require("prototypes.mir.emit.effect_safety")
        .sanitize_all_technology_effects({pass = "output"})
      require("prototypes.mir.emit.effect_safety").assert_target_inventory_unchanged(
        context:artifact("input_sanitation_ledger"), ledger)
      context:record_artifact("output_sanitation_ledger", ledger)
      require("prototypes.mir.emit.effect_safety").assert_registered_technology_effects()
      local graph_parity = require("prototypes.mir.emit.technology_graph_safety")
        .assert_registered_technologies(require("prototypes.mir.pipeline.compiler_orchestrator").compile(context))
      context:record_artifact("technology_graph_parity", graph_parity)
    end
  },
  ["emit-compatibility-diagnostics"] = {
    kind = "report",
    requires_features = {},
    implementation = "prototypes/mir/compatibility/diagnostics/registry.lua",
    apply = function() require("prototypes.mir.compatibility.diagnostics.registry").emit_all() end
  },
  ["emit-compiler-reports"] = {
    kind = "report",
    requires_features = {},
    implementation = "prototypes/mir/planner/compiler.lua",
    apply = function() require("prototypes.mir.report.compiler_diagnostics").emit() end
  },
  ["emit-compatibility-planner"] = {
    kind = "report",
    requires_features = {},
    implementation = "prototypes/mir/compatibility/planner.lua",
    apply = function() require("prototypes.mir.compatibility.planner").emit() end
  },
  ["assert-plan-output"] = {
    kind = "assertion",
    requires_features = {},
    implementation = "prototypes/mir/planner/output_validator.lua",
    apply = function(context) require("prototypes.mir.pipeline.compiler_orchestrator").assert_output(context) end
  },
  ["publish-compiler-artifacts"] = {
    kind = "publication",
    requires_features = {},
    implementation = "prototypes/mir/pipeline/compiler_orchestrator.lua",
    apply = function(context) require("prototypes.mir.pipeline.compiler_orchestrator").publish(context) end
  },
  ["flush-diagnostics"] = {
    kind = "report",
    requires_features = {},
    implementation = "prototypes/mir/report/diagnostics_sink.lua",
    apply = function() require("prototypes.mir.report.diagnostics_sink").flush() end
  }
}

local ORDERING = {
  ["compatibility-repairs"] = {phase = 10, dependencies = {}},
  ["sanitize-input-technology-effects"] = {phase = 15, dependencies = {"compatibility-repairs"}},
  ["module-permissions"] = {phase = 20, dependencies = {"sanitize-input-technology-effects"}},
  ["prototype-limits"] = {phase = 20, dependencies = {"compatibility-repairs", "module-permissions"}},
  ["pipeline-extent"] = {phase = 20, dependencies = {"compatibility-repairs", "prototype-limits"}},
  ["prepare-competing-productivity"] = {phase = 30, dependencies = {"pipeline-extent"}},
  ["prepare-competing-base-extensions"] = {phase = 30, dependencies = {"prepare-competing-productivity"}},
  ["compile-generation-plan"] = {phase = 35, dependencies = {"prepare-competing-base-extensions"}},
  ["emit-streams"] = {phase = 40, dependencies = {"compile-generation-plan"}},
  ["apply-competing-productivity"] = {phase = 50, dependencies = {"emit-streams"}},
  ["emit-base-extensions"] = {phase = 50, dependencies = {"apply-competing-productivity"}},
  ["apply-competing-base-extensions"] = {phase = 60, dependencies = {"emit-base-extensions"}},
  ["weapon-speed-adjustments"] = {phase = 70, dependencies = {"apply-competing-base-extensions"}},
  ["max-level-control"] = {phase = 70, dependencies = {"weapon-speed-adjustments"}},
  ["assert-technology-safety"] = {phase = 75, dependencies = {"max-level-control"}},
  ["emit-compatibility-diagnostics"] = {phase = 80, dependencies = {"assert-technology-safety"}},
  ["emit-compiler-reports"] = {phase = 80, dependencies = {"emit-compatibility-diagnostics"}},
  ["emit-compatibility-planner"] = {phase = 80, dependencies = {"emit-compiler-reports"}},
  ["assert-plan-output"] = {phase = 90, dependencies = {"emit-compatibility-planner"}},
  ["publish-compiler-artifacts"] = {phase = 95, dependencies = {"assert-plan-output"}},
  ["flush-diagnostics"] = {phase = 100, dependencies = {"publish-compiler-artifacts"}}
}


for id, command in pairs(commands) do
  local ordering = ORDERING[id]
  if not ordering then error("MIR pipeline command lacks ordering metadata: " .. id) end
  command.phase = ordering.phase
  command.dependencies = ordering.dependencies
end

local function supported(command)
  for _, feature in ipairs(command.requires_features) do
    if not target_line.feature_enabled(feature) then return false end
  end
  return true
end

function M.run(id, context)
  if not context then error("MIR pipeline command requires a compiler context.", 2) end
  return compiler_context.with_active(context, function()
    local command = commands[id]
    if not command then error("Unknown MIR pipeline command " .. tostring(id) .. ".", 2) end
    for _, dependency in ipairs(command.dependencies) do
      if not context:command_status(dependency) then
        error("MIR pipeline command " .. id .. " ran before dependency " .. dependency .. ".", 2)
      end
    end
    if not supported(command) then context:mark_command(id, "skipped"); return false end
    telemetry.start_phase("pipeline:" .. id)
    local summary_phase = id == "assert-technology-safety" and "postconditions" or nil
    if summary_phase then telemetry.start_phase(summary_phase) end
    local ok, result = pcall(command.apply, context)
    if summary_phase then telemetry.finish_phase(summary_phase) end
    telemetry.finish_phase("pipeline:" .. id)
    if not ok then error(result, 2) end
    context:mark_command(id, "applied")
    return true
  end)
end

function M.run_all(options)
  options = options or {}
  local context = compiler_context.new()
  local ok, result = pcall(compiler_context.with_active, context, function()
    for _, id in ipairs(M.order()) do M.run(id, context) end
  end)
  if not ok then
    pcall(function() require("prototypes.mir.report.diagnostics_sink").flush() end)
    error(result, 2)
  end
  if options.return_snapshot == false then return context end
  return context:snapshot()
end

function M.new_context()
  return compiler_context.new()
end

function M.order()
  local ordered, visiting, visited = {}, {}, {}
  local function visit(id)
    if visiting[id] then error("MIR pipeline command dependency cycle at " .. id, 2) end
    if visited[id] then return end
    visiting[id] = true
    for _, dependency in ipairs(commands[id].dependencies) do
      if not commands[dependency] then error("Unknown MIR pipeline dependency " .. dependency, 2) end
      visit(dependency)
    end
    visiting[id] = nil
    visited[id] = true
    table.insert(ordered, id)
  end
  local ids = {}
  for id, _ in pairs(commands) do table.insert(ids, id) end
  table.sort(ids, function(a, b)
    if commands[a].phase ~= commands[b].phase then return commands[a].phase < commands[b].phase end
    return a < b
  end)
  for _, id in ipairs(ids) do visit(id) end
  return ordered
end

function M.snapshot()
  local out = {}
  for id, command in pairs(commands) do
    out[id] = {
      id = id,
      kind = command.kind,
      phase = command.phase,
      dependencies = deepcopy(command.dependencies),
      requires_features = deepcopy(command.requires_features),
      implementation = command.implementation
    }
  end
  return out
end

return M
