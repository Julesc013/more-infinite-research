local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}
local Context = {}
Context.__index = Context
local active = nil

function M.new()
  local context = setmetatable({schema = 2, command_state = {}, artifacts = {}, state = {}}, Context)
  active = context
  return context
end

function M.activate(context)
  if getmetatable(context) ~= Context then
    error("MIR compiler context activation requires a CompilerContext.", 2)
  end
  active = context
  return context
end

function M.current()
  if not active then error("MIR compiler state was requested before CompilerContext activation.", 2) end
  return active
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

-- Context state is the owner for all mutable, data-derived compiler state.
-- Internal compiler modules may use the returned reference during one
-- data-final-fixes run; public snapshots must still be copied.
function Context:state_view(name, factory)
  if self.state[name] == nil and factory ~= nil then
    self.state[name] = factory()
  end
  return self.state[name]
end

function Context:set_state(name, value)
  self.state[name] = value
  return value
end

function Context:state_snapshot(name)
  return deepcopy(self.state[name])
end

function Context:has_state(name)
  return self.state[name] ~= nil
end

function Context:snapshot()
  return deepcopy({
    schema = self.schema,
    command_state = self.command_state,
    artifacts = self.artifacts,
    state = self.state
  })
end

return M
