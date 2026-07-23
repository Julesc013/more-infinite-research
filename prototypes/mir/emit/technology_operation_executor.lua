local technology_design = require("prototypes.mir.domain.technology.technology_design")
local technology_design_adapter = require("prototypes.mir.emit.technology_design_adapter")
local adoption_transaction = require("prototypes.mir.emit.transactions.productivity_family_adoption")

local M = {}

local function record(journal, transformation_operation, before, after, status)
  if journal and transformation_operation then
    journal:record(transformation_operation, before, after, status)
  end
end

function M.create(design, registry, journal, transformation_operation)
  technology_design.validate(design)
  local before = {}
  local technology = technology_design_adapter.emit(design, registry)
  record(journal, transformation_operation, before, technology, "applied")
  return technology
end

function M.patch(adoption, design, journal, transformation_operation)
  technology_design.validate(design)
  local before = adoption and adoption.input_snapshot or {}
  local result = adoption_transaction.apply(adoption, design)
  local after = adoption and adoption.expected_snapshot or result or {}
  record(journal, transformation_operation, before, after, "applied")
  return result
end

function M.apply_stream_row(row, journal, transformation_operation)
  if row.action == "emit" then
    return M.create(row.technology_design, {kind = "stream", key = row.stream_key}, journal, transformation_operation)
  end
  if row.action == "adopt" then
    return M.patch(row.adoption, row.technology_design, journal, transformation_operation)
  end
  error("Technology operation executor cannot apply non-materializing stream row.", 2)
end

function M.apply_base_continuation(operation, journal, transformation_operation)
  if not operation.technology_design then
    error("Base continuation operation requires TechnologyDesign schema 2: "
      .. tostring(operation.technology_name), 2)
  end
  return M.create(operation.technology_design, {kind = "base_extension", key = operation.key},
    journal, transformation_operation)
end

return M
