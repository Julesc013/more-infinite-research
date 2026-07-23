local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")

local M = {}
local Journal = {}
Journal.__index = Journal

local function material(journal)
  return {
    schema = journal.schema,
    record_type = journal.record_type,
    plan_fingerprint = journal.plan_fingerprint,
    entries = journal.entries
  }
end

function M.new(plan_fingerprint)
  if type(plan_fingerprint) ~= "string" or plan_fingerprint == "" then
    error("MutationJournal requires a TransformationPlan fingerprint.", 2)
  end
  return setmetatable({schema = 1, record_type = "MutationJournal", plan_fingerprint = plan_fingerprint,
    entries = {}, recorded = {}}, Journal)
end

function Journal:record(operation, before, after, status)
  operation_contract.validate(operation)
  if self.recorded[operation.operation_id] then
    error("MutationJournal operation was recorded more than once: " .. operation.operation_id, 2)
  end
  if status ~= "applied" and status ~= "skipped" and status ~= "failed" then
    error("MutationJournal status is invalid.", 2)
  end
  local entry = {
    operation_id = operation.operation_id,
    operation_fingerprint = operation.operation_fingerprint,
    status = status,
    before_fingerprint = fingerprint.of(before or {}),
    after_fingerprint = fingerprint.of(after or {})
  }
  entry.entry_fingerprint = fingerprint.of(entry)
  self.recorded[operation.operation_id] = true
  table.insert(self.entries, entry)
  return deepcopy(entry)
end

function Journal:snapshot()
  table.sort(self.entries, function(left, right) return left.operation_id < right.operation_id end)
  local out = material(self)
  out.journal_fingerprint = fingerprint.of(out)
  return deepcopy(out)
end

return M
