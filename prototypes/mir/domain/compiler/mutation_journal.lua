local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")
local plan_contract = require("prototypes.mir.domain.compiler.transformation_plan")

local M = {}
local Journal = {}
Journal.__index = Journal
local SCHEMA = 2

local function terminal_counts(entries)
  local counts = {applied = 0, failed = 0}
  for _, entry in ipairs(entries) do counts[entry.status] = (counts[entry.status] or 0) + 1 end
  return counts
end

local function entry_material(entry)
  local out = deepcopy(entry)
  out.entry_fingerprint = nil
  return out
end

function M.new(plan)
  if plan_contract.is_trusted(plan) then plan_contract.assert_trusted(plan)
  else plan_contract.verify_untrusted(plan) end
  return setmetatable({
    schema = SCHEMA,
    record_type = "MutationJournal",
    plan_fingerprint = plan.plan_fingerprint,
    planned_operation_fingerprints = deepcopy(plan.operation_fingerprints),
    required_operation_count = #plan.operations,
    entries = {},
    recorded = {},
    violations = {duplicate = {}, undeclared = {}, out_of_plan = {}},
    finalized = false
  }, Journal)
end

function Journal:assert_operation(operation)
  if self.finalized then error("MutationJournal is finalized.", 2) end
  if operation_contract.is_trusted(operation) then operation_contract.assert_trusted(operation)
  else operation_contract.verify_untrusted(operation) end
  local planned = self.planned_operation_fingerprints[operation.operation_id]
  if not planned then
    table.insert(self.violations.undeclared, operation.operation_id)
    error("MutationJournal rejected undeclared operation: " .. operation.operation_id, 2)
  end
  if planned ~= operation.operation_fingerprint then
    table.insert(self.violations.out_of_plan, operation.operation_id)
    error("MutationJournal operation differs from its bound plan: " .. operation.operation_id, 2)
  end
  if self.recorded[operation.operation_id] then
    table.insert(self.violations.duplicate, operation.operation_id)
    error("MutationJournal operation was recorded more than once: " .. operation.operation_id, 2)
  end
  return true
end

function Journal:assert_before(operation, before)
  self:assert_operation(operation)
  local actual = fingerprint.of(before or {})
  if actual ~= operation.expected_before_fingerprint then
    self:record(operation, before, before, "failed", "precondition-mismatch", {skip_precheck = true})
    error("Transformation precondition differs for " .. operation.operation_id
      .. " expected=" .. operation.expected_before_fingerprint .. " actual=" .. actual, 2)
  end
  return true
end

function Journal:record(operation, before, after, status, failure_code, options)
  options = options or {}
  if not options.skip_precheck then self:assert_operation(operation) end
  if status ~= "applied" and status ~= "failed" then
    error("MutationJournal terminal status is invalid.", 2)
  end
  local entry = {
    operation_id = operation.operation_id,
    operation_fingerprint = operation.operation_fingerprint,
    status = status,
    failure_code = failure_code,
    before_snapshot = deepcopy(before or {}),
    after_projection = deepcopy(after or {}),
    before_fingerprint = fingerprint.of(before or {}),
    after_fingerprint = fingerprint.of(after or {})
  }
  if status == "applied" and entry.before_fingerprint ~= operation.expected_before_fingerprint then
    entry.status = "failed"
    entry.failure_code = "precondition-mismatch"
  elseif status == "applied" and entry.after_fingerprint ~= operation.expected_after_fingerprint then
    entry.status = "failed"
    entry.failure_code = "postcondition-mismatch"
  end
  entry.entry_fingerprint = fingerprint.of(entry_material(entry))
  self.recorded[operation.operation_id] = true
  table.insert(self.entries, entry)
  if entry.status == "failed" then
    error("Transformation execution failed for " .. operation.operation_id
      .. ": " .. tostring(entry.failure_code), 2)
  end
  return deepcopy(entry)
end

function Journal:snapshot()
  if self.final_snapshot then return deepcopy(self.final_snapshot) end
  table.sort(self.entries, function(left, right) return left.operation_id < right.operation_id end)
  local missing = {}
  for operation_id in pairs(self.planned_operation_fingerprints) do
    if not self.recorded[operation_id] then table.insert(missing, operation_id) end
  end
  table.sort(missing)
  for _, values in pairs(self.violations) do table.sort(values) end
  local out = {
    schema = self.schema,
    record_type = self.record_type,
    plan_fingerprint = self.plan_fingerprint,
    required_operation_count = self.required_operation_count,
    entries = self.entries,
    terminal_counts = terminal_counts(self.entries),
    missing_operations = missing,
    missing_operation_count = #missing,
    duplicate_operation_count = #self.violations.duplicate,
    undeclared_operation_count = #self.violations.undeclared,
    out_of_plan_operation_count = #self.violations.out_of_plan,
    violations = self.violations,
    finalized = self.finalized
  }
  out.journal_fingerprint = fingerprint.of(out)
  return deepcopy(out)
end

function Journal:finalize(options)
  options = options or {}
  local preview = self:snapshot()
  local complete = preview.missing_operation_count == 0
    and preview.duplicate_operation_count == 0
    and preview.undeclared_operation_count == 0
    and preview.out_of_plan_operation_count == 0
    and preview.terminal_counts.failed == 0
    and #preview.entries == self.required_operation_count
  self.finalized = true
  local result = self:snapshot()
  result.complete = complete
  result.journal_fingerprint = fingerprint.of((function()
    local material = deepcopy(result)
    material.journal_fingerprint = nil
    return material
  end)())
  self.final_snapshot = deepcopy(result)
  if not complete and options.allow_failed ~= true then
    error("MutationJournal is incomplete or failed: missing=" .. result.missing_operation_count
      .. " duplicate=" .. result.duplicate_operation_count
      .. " undeclared=" .. result.undeclared_operation_count
      .. " out-of-plan=" .. result.out_of_plan_operation_count
      .. " failed=" .. result.terminal_counts.failed, 2)
  end
  return result
end

return M
