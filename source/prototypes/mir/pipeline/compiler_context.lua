local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local execution_mode = require("prototypes.mir.domain.compiler.execution_mode")

local M = {}
local Context = {}
Context.__index = Context
local active = nil

local function assert_context(context, level)
  if getmetatable(context) ~= Context then
    error("MIR compiler context activation requires a CompilerContext.", level or 2)
  end
  return context
end

function M.new(options)
  options = options or {}
  return setmetatable({
    schema = 4,
    compiler_execution_mode = execution_mode.normalize(options.execution_mode),
    command_state = {},
    artifacts = {},
    state = {},
    state_epochs = {},
    frozen_state = {},
    services = {},
    services_frozen = false,
    -- This is a demand bit for the existing Context export boundary, not a
    -- compiler/execution mode. The established manual/default Context is
    -- export-capable; the player data stage explicitly selects false.
    _legacy_compiler_export_requested = options.legacy_compiler_export_requested ~= false
  }, Context)
end

local function activate(context)
  active = assert_context(context, 2)
  return context
end

function M.with_active(context, callback, ...)
  assert_context(context, 2)
  if type(callback) ~= "function" then
    error("MIR scoped compiler activation requires a callback.", 2)
  end
  local previous = active
  local arguments = table.pack(...)
  activate(context)
  local results = table.pack(xpcall(function()
    return callback(table.unpack(arguments, 1, arguments.n))
  end, debug.traceback))
  active = previous
  if not results[1] then error(results[2], 2) end
  return table.unpack(results, 2, results.n)
end

function M.is_active(context)
  return active == context
end

function M.current()
  -- Factorio data-stage adapter. Pure compiler services receive a Context
  -- explicitly; legacy platform facades use this active-run bridge only.
  if not active then error("MIR compiler state was requested before CompilerContext activation.", 2) end
  return active
end

function Context:execution_mode()
  return self.compiler_execution_mode
end

function Context:legacy_compiler_export_requested()
  return self._legacy_compiler_export_requested == true
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

-- Compiler-owned immutable records may be shared between state and the
-- internal artifact index after their private authority has accepted them.
-- The context exposes this reference only through the explicitly read-only
-- artifact_view() planning surface. artifact() and snapshot() retain the
-- defensive-copy boundary used by adapters, reports, and fixtures.
function Context:record_immutable_artifact(name, value, authority)
  if self.artifacts[name] ~= nil then
    error("MIR compiler context artifact was recorded more than once: " .. tostring(name), 2)
  end
  if type(authority) ~= "table" or type(authority.assert_trusted) ~= "function" then
    error("MIR immutable compiler artifact requires its private trust authority: "
      .. tostring(name), 2)
  end
  authority.assert_trusted(value)
  self.artifacts[name] = value
end

function Context:artifact(name)
  return deepcopy(self.artifacts[name])
end

-- Planning modules may share the context-owned artifact instance while the
-- active compiler scope remains open. Callers must treat this as read-only;
-- artifact() remains the defensive-copy boundary for exports and fixtures.
function Context:artifact_view(name)
  return self.artifacts[name]
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
  if name == "recipe_risk_materialization" then return nil end
  if name == "recipe_risk_index" and self.services["recipe_risk.materialize_export"] then
    M.with_active(self, self.services["recipe_risk.materialize_export"])
  end
  if name == "recipe_index" and self.services["recipe_facts.materialize_export"] then
    M.with_active(self, self.services["recipe_facts.materialize_export"])
  end
  return deepcopy(self.state[name])
end

function Context:has_state(name)
  return self.state[name] ~= nil
end

function Context:state_key_count()
  local count = 0
  for name in pairs(self.state) do
    if name ~= "recipe_risk_materialization" then count = count + 1 end
  end
  return count
end

function Context:snapshot()
  -- An explicitly active-only context did not retain a generic pre-mutation
  -- input. Returning schema 4 after it compiled would silently remove the
  -- supported snapshot contract, so refuse that late request instead.
  if not self:legacy_compiler_export_requested() and self.state.compilation_plan ~= nil then
    error("Active-only CompilerContext cannot export legacy snapshots after compilation; request export before compilation.", 2)
  end
  local complete_risks = self.services["recipe_risk.materialize_export"]
  if complete_risks then M.with_active(self, complete_risks) end
  local complete_recipe_facts = self.services["recipe_facts.materialize_export"]
  if complete_recipe_facts then M.with_active(self, complete_recipe_facts) end
  local exported_state = deepcopy(self.state)
  -- A requested Context export must not carry the private active handle that
  -- the plan used while compiling. The generic input stored for this export is
  -- the original schema-2 record and is independently import-verifiable.
  local exported_plan = exported_state.compilation_plan
  if self:legacy_compiler_export_requested() and type(exported_plan) == "table"
    and type(exported_state.compiler_input) == "table" then
    exported_plan.compiler_input = deepcopy(exported_state.compiler_input)
  end
  local payload = {
    schema = self.schema,
    compiler_execution_mode = self.compiler_execution_mode,
    command_state = deepcopy(self.command_state),
    artifacts = deepcopy(self.artifacts),
    state = exported_state,
    state_epochs = deepcopy(self.state_epochs),
    frozen_state = deepcopy(self.frozen_state),
    services = {},
    services_frozen = self.services_frozen
  }
  -- The complete schema-1 risk index above is the public state. Its private
  -- demand-driven preparation contains borrowed input views, not an export.
  payload.state.recipe_risk_materialization = nil
  payload.state_epochs.recipe_risk_materialization = nil
  payload.frozen_state.recipe_risk_materialization = nil
  for name in pairs(self.services) do
    if name ~= "recipe_risk.materialize_export" and name ~= "recipe_facts.materialize_export" then
      table.insert(payload.services, name)
    end
  end
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
