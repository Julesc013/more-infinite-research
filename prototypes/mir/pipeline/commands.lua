local deepcopy = require("prototypes.mir.core.deepcopy")
local target_line = require("prototypes.mir.platform.factorio.target_line")

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
      local multiplier = require("prototypes.mir.settings.pipeline_extent").multiplier()
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
  ["emit-streams"] = {
    kind = "emission",
    requires_features = {},
    implementation = "prototypes/mir/planner/stream_compiler.lua",
    apply = function() require("prototypes.mir.planner.stream_compiler").run() end
  },
  ["apply-competing-productivity"] = {
    kind = "mutation",
    requires_features = {"recipe_productivity"},
    implementation = "prototypes/mir/policy/competing_productivity.lua",
    apply = function() require("prototypes.mir.policy.competing_productivity").apply() end
  },
  ["emit-base-extensions"] = {
    kind = "emission",
    requires_features = {},
    implementation = "prototypes/mir/emit/base_extensions.lua",
    apply = function() require("prototypes.mir.emit.base_extensions").emit_all() end
  },
  ["apply-competing-base-extensions"] = {
    kind = "mutation",
    requires_features = {},
    implementation = "prototypes/mir/policy/competing_base_extensions.lua",
    apply = function() require("prototypes.mir.policy.competing_base_extensions").apply() end
  },
  ["weapon-speed-adjustments"] = {
    kind = "mutation",
    requires_features = {},
    implementation = "prototypes/mir/policy/weapon_speed.lua",
    apply = function() require("prototypes.mir.policy.weapon_speed").apply() end
  },
  ["max-level-control"] = {
    kind = "mutation",
    requires_features = {},
    implementation = "prototypes/mir/policy/max_level.lua",
    apply = function() require("prototypes.mir.policy.max_level").apply() end
  },
  ["assert-technology-safety"] = {
    kind = "assertion",
    requires_features = {},
    implementation = "prototypes/mir/emit/effect_safety.lua",
    apply = function()
      require("prototypes.mir.emit.effect_safety").assert_registered_technology_effects()
      require("prototypes.mir.emit.technology_graph_safety").assert_registered_technologies()
    end
  }
}

local ORDERING = {
  ["compatibility-repairs"] = {phase = 10, dependencies = {}},
  ["module-permissions"] = {phase = 20, dependencies = {"compatibility-repairs"}},
  ["prototype-limits"] = {phase = 20, dependencies = {"compatibility-repairs", "module-permissions"}},
  ["pipeline-extent"] = {phase = 20, dependencies = {"compatibility-repairs", "prototype-limits"}},
  ["prepare-competing-productivity"] = {phase = 30, dependencies = {"pipeline-extent"}},
  ["prepare-competing-base-extensions"] = {phase = 30, dependencies = {"prepare-competing-productivity"}},
  ["emit-streams"] = {phase = 40, dependencies = {"prepare-competing-base-extensions"}},
  ["apply-competing-productivity"] = {phase = 50, dependencies = {"emit-streams"}},
  ["emit-base-extensions"] = {phase = 50, dependencies = {"apply-competing-productivity"}},
  ["apply-competing-base-extensions"] = {phase = 60, dependencies = {"emit-base-extensions"}},
  ["weapon-speed-adjustments"] = {phase = 70, dependencies = {"apply-competing-base-extensions"}},
  ["max-level-control"] = {phase = 70, dependencies = {"weapon-speed-adjustments"}},
  ["assert-technology-safety"] = {phase = 90, dependencies = {"max-level-control"}}
}

for id, command in pairs(commands) do
  local ordering = ORDERING[id]
  if not ordering then error("MIR pipeline command lacks ordering metadata: " .. id) end
  command.phase = ordering.phase
  command.dependencies = ordering.dependencies
end

local completed = {}

local function supported(command)
  for _, feature in ipairs(command.requires_features) do
    if not target_line.feature_enabled(feature) then return false end
  end
  return true
end

function M.run(id)
  local command = commands[id]
  if not command then error("Unknown MIR pipeline command " .. tostring(id) .. ".", 2) end
  for _, dependency in ipairs(command.dependencies) do
    if not completed[dependency] then
      error("MIR pipeline command " .. id .. " ran before dependency " .. dependency .. ".", 2)
    end
  end
  if not supported(command) then completed[id] = "skipped"; return false end
  command.apply()
  completed[id] = "applied"
  return true
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
