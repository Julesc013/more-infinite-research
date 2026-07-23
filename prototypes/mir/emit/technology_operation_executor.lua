local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local technology_design_adapter = require("prototypes.mir.emit.technology_design_adapter")
local adoption_transaction = require("prototypes.mir.emit.transactions.productivity_family_adoption")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")
local plan_contract = require("prototypes.mir.domain.compiler.transformation_plan")

local M = {}

local function project_actual(actual, expected)
  if type(expected) ~= "table" then return actual end
  local out = {}
  for key, value in pairs(expected) do out[key] = project_actual(actual and actual[key], value) end
  return out
end

local function capture(operation)
  local technology = data_raw.technology(operation.subject.id)
  if not technology then
    return {presence = "absent", prototype_type = "technology", id = operation.subject.id}
  end
  if operation.action == "patch" then return native_owner_contract.snapshot(technology) end
  return project_actual(technology, operation.expected_after_projection)
end

local function apply_operation(operation)
  local payload = operation.payload
  local design = payload.technology_design
  technology_design.validate(design)
  if operation.action == "create" then
    return technology_design_adapter.emit(design, {
      kind = payload.kind == "base-continuation" and "base_extension" or "stream",
      key = payload.key or payload.stream_key
    })
  end
  if operation.action == "patch" then
    return adoption_transaction.apply(payload.adoption, design)
  end
  error("Technology operation executor received unsupported action: " .. tostring(operation.action), 2)
end

function M.apply_plan(plan, journal, options)
  options = options or {}
  plan_contract.validate(plan)
  if type(journal) ~= "table" or journal.plan_fingerprint ~= plan.plan_fingerprint then
    error("Technology operation executor requires the exact plan-bound MutationJournal.", 2)
  end
  local realized = {}
  for _, operation in ipairs(plan.operations) do
    if options.kind == nil or operation.payload.kind == options.kind then
      local before = capture(operation)
      journal:assert_before(operation, before)
      local ok, result = xpcall(function() return apply_operation(operation) end, debug.traceback)
      local after = capture(operation)
      if not ok then
        journal:record(operation, before, after, "failed", "mutation-error", {skip_precheck = true})
      end
      journal:record(operation, before, after, "applied", nil, {skip_precheck = true})
      table.insert(realized, {
        operation_id = operation.operation_id,
        subject = deepcopy(operation.subject),
        after_fingerprint = operation.expected_after_fingerprint,
        result = result
      })
    end
  end
  return realized
end

return M
