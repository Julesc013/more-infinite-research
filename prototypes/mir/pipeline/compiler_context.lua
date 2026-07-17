local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}
local Context = {}
Context.__index = Context

function M.new()
  return setmetatable({schema = 1, command_state = {}, artifacts = {}}, Context)
end

function Context:command_status(id)
  return self.command_state[id]
end

function Context:mark_command(id, status)
  if self.command_state[id] ~= nil then
    error("MIR compiler context command was completed more than once: " .. tostring(id), 2)
  end
  self.command_state[id] = status
end

function Context:record_artifact(name, value)
  if self.artifacts[name] ~= nil then
    error("MIR compiler context artifact was recorded more than once: " .. tostring(name), 2)
  end
  self.artifacts[name] = deepcopy(value)
end

function Context:artifact(name)
  return deepcopy(self.artifacts[name])
end

function Context:snapshot()
  return deepcopy({schema = self.schema, command_state = self.command_state, artifacts = self.artifacts})
end

return M
