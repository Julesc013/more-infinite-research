local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local Plan = {}
Plan.__index = Plan

local ACTIONS = {
  adopt = true,
  emit = true,
  skip = true
}

local REQUIRED_GATES = {
  "target_supported",
  "effect_valid",
  "owner_conflict_free",
  "science_compatible",
  "lab_compatible",
  "prerequisites_acyclic",
  "loop_safe"
}

local function required(row, field)
  if row[field] == nil then
    error("GenerationPlan row missing required field: " .. field, 3)
  end
end

local function validate_row(row)
  if type(row) ~= "table" then error("GenerationPlan row must be a table", 3) end
  if row.schema ~= 2 then error("GenerationPlan row schema must be 2", 3) end
  required(row, "stream_key")
  required(row, "manifest_id")
  required(row, "action")
  required(row, "source")
  if not ACTIONS[row.action] then
    error("GenerationPlan row has unsupported action: " .. tostring(row.action), 3)
  end
  required(row, "gates")
  for _, gate in ipairs(REQUIRED_GATES) do
    if type(row.gates[gate]) ~= "boolean" then
      error("GenerationPlan row gate must be boolean: " .. gate, 3)
    end
    if row.action ~= "skip" and not row.gates[gate] then
      error("GenerationPlan materializing row failed gate " .. gate .. ": " .. row.stream_key, 3)
    end
  end
  if row.action == "emit" then
    required(row, "technology_name")
    required(row, "fields")
    required(row.fields, "effects")
    required(row.fields, "ingredients")
    required(row.fields, "prerequisites")
    required(row.fields, "count_formula")
    required(row.fields, "research_time")
    required(row.fields, "max_level")
  elseif row.action == "adopt" then
    required(row, "adoption")
    required(row.adoption, "owner")
    required(row.adoption, "effects")
  else
    required(row, "reason")
  end
end

function M.new(metadata)
  metadata = metadata or {}
  return setmetatable({
    rows = {},
    finalized = false,
    source_fingerprints = deepcopy(metadata.source_fingerprints or {}),
    validation_summary = nil,
    plan_fingerprint = nil
  }, Plan)
end

function Plan:add(row)
  if self.finalized then error("GenerationPlan is already finalized", 2) end
  validate_row(row)
  table.insert(self.rows, deepcopy(row))
end

function Plan:finalize()
  if self.finalized then return self end

  local stream_keys = {}
  local manifest_ids = {}
  local technology_names = {}
  local adopted_recipes = {}
  for _, row in ipairs(self.rows) do
    validate_row(row)
    if stream_keys[row.stream_key] then
      error("GenerationPlan contains duplicate stream key: " .. row.stream_key, 2)
    end
    stream_keys[row.stream_key] = true

    if row.action == "emit" then
      if manifest_ids[row.manifest_id] then
        error("GenerationPlan contains duplicate emitted manifest id: " .. row.manifest_id, 2)
      end
      if technology_names[row.technology_name] then
        error("GenerationPlan contains duplicate technology name: " .. row.technology_name, 2)
      end
      manifest_ids[row.manifest_id] = true
      technology_names[row.technology_name] = true
    elseif row.action == "adopt" then
      for _, effect in ipairs(row.adoption.effects) do
        local identity = row.adoption.owner .. "\0" .. tostring(effect.recipe)
        if adopted_recipes[identity] then
          error("GenerationPlan contains duplicate adopted recipe: " .. tostring(effect.recipe), 2)
        end
        adopted_recipes[identity] = true
      end
    end
  end

  self.finalized = true
  local action_counts, reason_counts = {}, {}
  for _, row in ipairs(self.rows) do
    action_counts[row.action] = (action_counts[row.action] or 0) + 1
    local reason = row.reason or row.action
    reason_counts[reason] = (reason_counts[reason] or 0) + 1
  end
  self.validation_summary = {
    valid = true,
    row_count = #self.rows,
    action_counts = action_counts,
    reason_counts = reason_counts
  }
  self.plan_fingerprint = fingerprint.of({
    schema = 2,
    source_fingerprints = self.source_fingerprints,
    rows = self.rows,
    validation_summary = self.validation_summary
  })
  return self
end

function Plan:snapshot()
  if not self.finalized then error("GenerationPlan must be finalized before snapshot", 2) end
  return deepcopy(self.rows)
end

function Plan:count(action)
  local count = 0
  for _, row in ipairs(self.rows) do
    if action == nil or row.action == action then count = count + 1 end
  end
  return count
end

function Plan:artifact()
  if not self.finalized then error("GenerationPlan must be finalized before artifact export", 2) end
  return deepcopy({
    schema = 2,
    plan_fingerprint = self.plan_fingerprint,
    source_fingerprints = self.source_fingerprints,
    rows = self.rows,
    validation_summary = self.validation_summary
  })
end

return M
