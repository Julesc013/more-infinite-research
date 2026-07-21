local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local NUMERIC_TOLERANCE = 0.000000001

local function fail(context, message)
  error("CompilationPlan output mismatch for " .. context .. ": " .. message, 3)
end

local function close(left, right)
  return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) <= NUMERIC_TOLERANCE
end

local function effect_rows(effects)
  local out = {}
  for _, effect in ipairs(effects or {}) do
    local identity = generation_plan.effect_identity(effect)
    if identity ~= "" then
      out[identity] = out[identity] or {}
      table.insert(out[identity], effect)
    end
  end
  return out
end

function M.assert_effects(expected_effects, actual_effects, context, exact)
  local expected, actual = effect_rows(expected_effects), effect_rows(actual_effects)
  for identity, expected_rows in pairs(expected) do
    local actual_rows = actual[identity] or {}
    if #actual_rows ~= #expected_rows then
      fail(context, "effect multiplicity differs for " .. identity)
    end
    local used = {}
    for _, wanted in ipairs(expected_rows) do
      local match = nil
      for index, candidate in ipairs(actual_rows) do
        if not used[index]
          and (wanted.change == nil or close(wanted.change, candidate.change))
          and (wanted.modifier == nil or close(wanted.modifier, candidate.modifier)) then
          match = index
          break
        end
      end
      if not match then
        fail(context, "numeric effect value differs for " .. identity
          .. " expected=" .. generation_plan.effect_signature(wanted))
      end
      used[match] = true
    end
  end
  if exact then
    for identity, actual_rows in pairs(actual) do
      if #(expected[identity] or {}) ~= #actual_rows then
        fail(context, "unexpected effect " .. identity)
      end
    end
  end
end

local function normalized_names(values)
  local out = {}
  for _, value in ipairs(values or {}) do table.insert(out, tostring(value)) end
  table.sort(out)
  return table.concat(out, "\0")
end

local function normalized_ingredients(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    local name = value.name or value[1]
    local amount = value.amount or value[2]
    table.insert(out, tostring(name) .. "=" .. tostring(amount))
  end
  table.sort(out)
  return table.concat(out, "\0")
end

local function assert_equal(context, field, expected, actual)
  if expected ~= actual then
    fail(context, field .. " differs expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function assert_structural(context, field, expected, actual)
  local expected_fingerprint = fingerprint.of({value = expected})
  local actual_fingerprint = fingerprint.of({value = actual})
  if expected_fingerprint ~= actual_fingerprint then
    fail(context, field .. " differs expected=" .. expected_fingerprint .. " actual=" .. actual_fingerprint)
  end
end

function M.assert_technology_shape(expected, actual, context)
  if not actual then fail(context, "technology is missing") end
  if expected.name ~= nil then assert_equal(context, "name", expected.name, actual.name) end
  M.assert_effects(expected.effects, actual.effects, context, true)
  assert_equal(context, "prerequisites", normalized_names(expected.prerequisites), normalized_names(actual.prerequisites))
  local expected_unit, actual_unit = expected.unit or {}, actual.unit or {}
  assert_equal(context, "science ingredients", normalized_ingredients(expected_unit.ingredients), normalized_ingredients(actual_unit.ingredients))
  assert_equal(context, "count formula", expected_unit.count_formula, actual_unit.count_formula)
  assert_equal(context, "fixed count", expected_unit.count, actual_unit.count)
  if expected_unit.time ~= nil and not close(expected_unit.time, actual_unit.time) then
    fail(context, "research time differs expected=" .. tostring(expected_unit.time) .. " actual=" .. tostring(actual_unit.time))
  end
  assert_equal(context, "max level", expected.max_level, actual.max_level)
  assert_structural(context, "localized name", expected.localised_name, actual.localised_name)
  assert_structural(context, "localized description", expected.localised_description, actual.localised_description)
  assert_equal(context, "icon", expected.icon, actual.icon)
  assert_equal(context, "icon size", expected.icon_size, actual.icon_size)
  assert_structural(context, "icons", expected.icons, actual.icons)
  assert_equal(context, "order", expected.order, actual.order)
  assert_equal(context, "level", expected.level, actual.level)
  for _, field in ipairs({"enabled", "hidden", "upgrade"}) do
    if expected[field] ~= nil then assert_equal(context, field, expected[field], actual[field]) end
  end
end

local function assert_registry(operation)
  local expected = operation.registry
  if not expected then return end
  local actual = generated_registry.get(operation.technology_name)
  if not actual then fail(operation.technology_name, "generated registry record is missing") end
  assert_equal(operation.technology_name, "registry kind", expected.kind, actual.kind)
  assert_equal(operation.technology_name, "registry key", expected.key, actual.key)
end

function M.assert_compilation_artifact(artifact, options)
  if not artifact or artifact.schema ~= 2 then error("CompilationPlan schema 2 artifact is required", 2) end
  options = options or {}
  local checked = 0
  for _, operation in ipairs(artifact.operations or {}) do
    local technology = data_raw.technology(operation.technology_name)
    if operation.operation == "emit_stream" or operation.operation == "emit_base_extension" then
      if not operation.technology_design then
        fail(operation.technology_name, "TechnologyDesign is missing")
      end
      if not options.designs_validated then
        technology_design.validate(operation.technology_design)
      end
      local expected = technology_design.prototype_projection(operation.technology_design, {validated = true})
      M.assert_technology_shape(expected, operation.technology,
        operation.technology_name .. " planned TechnologyDesign projection")
      M.assert_technology_shape(expected, technology, operation.technology_name)
      assert_registry(operation)
      checked = checked + 1
    elseif operation.operation == "native_owner_binding" then
      if not technology then fail(operation.technology_name, "adoption owner is missing") end
      if not operation.technology_design then
        fail(operation.technology_name, "patch-existing TechnologyDesign is missing")
      end
      if not options.designs_validated then
        technology_design.validate(operation.technology_design)
      end
      local design_projection = technology_design.prototype_projection(operation.technology_design, {validated = true})
      if operation.technology_design.materialization.kind ~= "patch-existing"
        or operation.technology_design.materialization.target ~= operation.technology_name then
        fail(operation.technology_name, "patch-existing TechnologyDesign target differs")
      end
      assert_equal(operation.technology_name, "TechnologyDesign patch fingerprint",
        operation.output_fingerprint, native_owner_contract.fingerprint(design_projection))
      local actual_snapshot = native_owner_contract.snapshot(technology)
      local actual_fingerprint = native_owner_contract.fingerprint(actual_snapshot)
      assert_equal(operation.technology_name, "native-owner output fingerprint", operation.output_fingerprint, actual_fingerprint)
      assert_equal(operation.technology_name, "planned native-owner snapshot fingerprint",
        operation.output_fingerprint, native_owner_contract.fingerprint(operation.expected_snapshot))
      checked = checked + 1
    else
      error("Unsupported CompilationPlan output operation: " .. tostring(operation.operation), 2)
    end
  end
  return {checked_operations = checked, tolerance = NUMERIC_TOLERANCE}
end

function M.assert_artifact(artifact)
  if not artifact or artifact.schema ~= 3 then error("GenerationPlan schema 3 artifact is required", 2) end
  local operations = {}
  for _, row in ipairs(artifact.rows or {}) do
    if row.action == "emit" then
      technology_design.assert_generation_row(row)
      table.insert(operations, {
        operation = "emit_stream",
        technology_name = row.technology_name,
        technology = technology_design.prototype_projection(row.technology_design, {validated = true})
      })
    elseif row.action == "adopt" then
      technology_design.assert_generation_row(row)
      table.insert(operations, {
        operation = "native_owner_binding",
        technology_name = row.adoption.owner,
        technology_design = row.technology_design,
        output_fingerprint = row.adoption.output_fingerprint,
        expected_snapshot = row.adoption.expected_snapshot
      })
    end
  end
  return M.assert_compilation_artifact({schema = 2, operations = operations})
end

return M
