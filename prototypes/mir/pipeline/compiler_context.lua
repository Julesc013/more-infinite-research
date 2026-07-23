local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local Context = {}
Context.__index = Context
local active = nil

function M.new()
  local context = setmetatable({
    schema = 3,
    command_state = {},
    artifacts = {},
    state = {},
    state_epochs = {},
    frozen_state = {},
    services = {},
    services_frozen = false
  }, Context)
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
  -- Factorio data-stage adapter. Pure compiler services receive a Context
  -- explicitly; legacy platform facades use this active-run bridge only.
  if not active then error("MIR compiler state was requested before CompilerContext activation.", 2) end
  return active
end

function Context:set_service(name, implementation)
  if self.services_frozen then error("MIR compiler services are frozen.", 2) end
  if self.services[name] ~= nil then
    error("MIR compiler service was registered more than once: " .. tostring(name), 2)
  end
  if type(implementation) ~= "function" and type(implementation) ~= "table" then
    error("MIR compiler service must be a function or table: " .. tostring(name), 2)
  end
  self.services[name] = implementation
  return implementation
end

function Context:service(name)
  return self.services[name]
end

function Context:has_service(name)
  return self.services[name] ~= nil
end

function Context:freeze_services()
  self.services_frozen = true
  return self
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
  if self.frozen_state[name] and self.state[name] == nil and factory ~= nil then
    error("MIR compiler state is frozen and cannot be initialized: " .. tostring(name), 2)
  end
  if self.state[name] == nil and factory ~= nil then
    self.state[name] = factory()
    self.state_epochs[name] = self.state_epochs[name] or 1
  end
  return self.state[name]
end

function Context:set_state(name, value)
  return self:set_once(name, value)
end

function Context:set_once(name, value)
  if self.frozen_state[name] then error("MIR compiler state is frozen: " .. tostring(name), 2) end
  if self.state[name] ~= nil then
    error("MIR compiler state was assigned more than once; use replace_epoch: " .. tostring(name), 2)
  end
  self.state[name] = value
  self.state_epochs[name] = 1
  return value
end


function Context:replace_epoch(name, value, expected_epoch)
  if self.frozen_state[name] then error("MIR compiler state is frozen: " .. tostring(name), 2) end
  if self.state[name] == nil then
    error("MIR compiler state cannot replace a missing epoch: " .. tostring(name), 2)
  end
  local current_epoch = self.state_epochs[name] or 1
  if expected_epoch ~= nil and expected_epoch ~= current_epoch then
    error("MIR compiler state epoch mismatch for " .. tostring(name) .. ": expected "
      .. tostring(expected_epoch) .. ", current " .. tostring(current_epoch), 2)
  end
  self.state[name] = value
  self.state_epochs[name] = current_epoch + 1
  return value, self.state_epochs[name]
end

function Context:state_epoch(name)
  return self.state_epochs[name]
end

function Context:freeze_state(name)
  if self.state[name] == nil then error("MIR compiler cannot freeze missing state: " .. tostring(name), 2) end
  self.frozen_state[name] = true
  return self.state_epochs[name]
end

function Context:state_snapshot(name)
  return deepcopy(self.state[name])
end

function Context:has_state(name)
  return self.state[name] ~= nil
end

function Context:state_key_count()
  local count = 0
  for _ in pairs(self.state) do count = count + 1 end
  return count
end

function Context:snapshot()
  local payload = {
    schema = self.schema,
    command_state = deepcopy(self.command_state),
    artifacts = deepcopy(self.artifacts),
    state = deepcopy(self.state),
    state_epochs = deepcopy(self.state_epochs),
    frozen_state = deepcopy(self.frozen_state),
    services = {},
    services_frozen = self.services_frozen
  }
  for name in pairs(self.services) do table.insert(payload.services, name) end
  table.sort(payload.services)
  local telemetry_state = payload.state.compiler_telemetry
  if telemetry_state and telemetry_state.counters then
    telemetry_state.counters.context_state_keys = self:state_key_count()
    local measured_bytes = tonumber(telemetry_state.counters.context_snapshot_bytes) or 0
    for _ = 1, 4 do
      telemetry_state.counters.context_snapshot_bytes = measured_bytes
      local next_bytes = #fingerprint.canonical(payload)
      if next_bytes == measured_bytes then break end
      measured_bytes = next_bytes
    end
    telemetry_state.counters.context_snapshot_bytes = measured_bytes
  end
  return payload
end

return M
