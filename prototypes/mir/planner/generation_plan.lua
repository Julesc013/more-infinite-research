local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")

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
  "loop_safe",
  "progression_safe",
  "migration_safe",
  "output_identity_safe"
}

local function effect_identity(effect)
  return effect_contracts.identity(effect)
end

local function effect_signature(effect)
  if not effect or effect.type == nil or effect.type == "nothing" then return "" end
  local normalized = {}
  for key, value in pairs(effect) do
    if key ~= "icon" and key ~= "icons" then normalized[key] = deepcopy(value) end
  end
  return fingerprint.canonical(normalized)
end

local function validate_gate(row, gate_name)
  local gate = row.gates[gate_name]
  gate_contract.validate(gate)
  if row.action ~= "skip" and gate.status == "failed" then
    error("GenerationPlan materializing row failed gate " .. gate_name .. ": " .. row.stream_key, 3)
  end
end

local function required(row, field)
  if row[field] == nil then
    error("GenerationPlan row missing required field: " .. field, 3)
  end
end

local function validate_row(row, options)
  options = options or {}
  if type(row) ~= "table" then error("GenerationPlan row must be a table", 3) end
  if row.schema ~= 3 then error("GenerationPlan row schema must be 3", 3) end
  required(row, "stream_key")
  required(row, "manifest_id")
  required(row, "action")
  required(row, "source")
  if not ACTIONS[row.action] then
    error("GenerationPlan row has unsupported action: " .. tostring(row.action), 3)
  end
  required(row, "gates")
  for _, gate in ipairs(REQUIRED_GATES) do
    validate_gate(row, gate)
  end
  if row.action == "emit" then
    required(row, "technology_name")
    required(row, "technology_design")
    if options.design_derived then
      if type(row.technology_design) ~= "table" or row.technology_design.schema ~= 2 then
        error("GenerationPlan derived row lacks TechnologyDesign schema 2: " .. tostring(row.stream_key), 3)
      end
    else
      technology_design.assert_generation_row(row)
    end
    required(row, "fields")
    required(row.fields, "effects")
    required(row.fields, "ingredients")
    required(row.fields, "prerequisites")
    required(row.fields, "count_formula")
    required(row.fields, "research_time")
    required(row.fields, "max_level")
  elseif row.action == "adopt" then
    required(row, "adoption")
    required(row, "technology_design")
    if row.adoption.schema ~= 2 then error("GenerationPlan native-owner binding schema must be 2", 3) end
    required(row.adoption, "owner")
    required(row.adoption, "operation")
    required(row.adoption, "configured_fields")
    required(row.adoption, "effects")
    required(row.adoption, "input_snapshot")
    required(row.adoption, "expected_snapshot")
    required(row.adoption, "input_fingerprint")
    required(row.adoption, "output_fingerprint")
    if fingerprint.of(row.adoption.input_snapshot) ~= row.adoption.input_fingerprint then
      error("GenerationPlan native-owner input fingerprint differs: " .. row.stream_key, 3)
    end
    if fingerprint.of(row.adoption.expected_snapshot) ~= row.adoption.output_fingerprint then
      error("GenerationPlan native-owner output fingerprint differs: " .. row.stream_key, 3)
    end
    if options.design_derived then
      if type(row.technology_design) ~= "table" or row.technology_design.schema ~= 2 then
        error("GenerationPlan derived row lacks TechnologyDesign schema 2: " .. tostring(row.stream_key), 3)
      end
    else
      technology_design.assert_generation_row(row)
    end
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

local function row_fingerprint_material(row)
  local design = row.technology_design or {}
  local adoption = row.adoption
  return {
    schema = row.schema,
    stream_key = row.stream_key,
    manifest_id = row.manifest_id,
    action = row.action,
    source = row.source,
    reason = row.reason,
    technology_name = row.technology_name,
    target_profile_fingerprint = row.target_profile_fingerprint,
    provider_ids = row.provider_ids,
    family_ids = row.family_ids,
    gates = row.gates,
    diagnostics = row.diagnostics,
    effect_ownership = row.effect_ownership,
    effect_integrity = row.effect_integrity,
    graph_integrity = row.graph_integrity,
    adoption = adoption and {
      schema = adoption.schema,
      owner = adoption.owner,
      operation = adoption.operation,
      configured_fields = adoption.configured_fields,
      effects = adoption.effects,
      input_fingerprint = adoption.input_fingerprint,
      output_fingerprint = adoption.output_fingerprint
    } or nil,
    technology_design = row.technology_design and {
      schema = design.schema,
      candidate_id = design.candidate_id,
      technology_id = design.technology_id,
      subject_fingerprint = design.subject_fingerprint,
      design_fingerprint = design.design_fingerprint,
      prototype_fingerprint = design.prototype_fingerprint,
      qualification_fingerprint = design.qualification_fingerprint,
      semantic_fingerprint = design.semantic_fingerprint
    } or nil
  }
end

local function rows_fingerprint_material(rows)
  local out = {}
  for index, row in ipairs(rows) do out[index] = row_fingerprint_material(row) end
  return out
end

function Plan:add_derived(row)
  if self.finalized then error("GenerationPlan is already finalized", 2) end
  validate_row(row, {design_derived = true})
  table.insert(self.rows, deepcopy(row))
end

function Plan:add_owned_derived(row)
  if self.finalized then error("GenerationPlan is already finalized", 2) end
  validate_row(row, {design_derived = true})
  table.insert(self.rows, row)
end

function Plan:finalize()
  if self.finalized then return self end

  table.sort(self.rows, function(a, b)
    if a.stream_key ~= b.stream_key then return a.stream_key < b.stream_key end
    if a.action ~= b.action then return a.action < b.action end
    return tostring(a.manifest_id) < tostring(b.manifest_id)
  end)

  local stream_keys = {}
  local manifest_ids = {}
  local technology_names = {}
  local adopted_recipes = {}
  local adopted_owners = {}
  local materialized_effects = {}
  for _, row in ipairs(self.rows) do
    -- Recheck the inexpensive row and gate invariants at the ownership
    -- boundary without repeating complete TechnologyDesign fingerprints.
    validate_row(row, {design_derived = true})
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
      for _, effect in ipairs(row.fields.effects or {}) do
        local identity = effect_identity(effect)
        if identity ~= "" then
          if materialized_effects[identity] then
            error("GenerationPlan contains duplicate materialized effect identity: " .. identity, 2)
          end
          materialized_effects[identity] = row.technology_name
        end
      end
    elseif row.action == "adopt" then
      if adopted_owners[row.adoption.owner] then
        error("GenerationPlan contains duplicate native-owner binding: " .. row.adoption.owner, 2)
      end
      adopted_owners[row.adoption.owner] = row.stream_key
      for _, effect in ipairs(row.adoption.effects) do
        local identity = row.adoption.owner .. "\0" .. tostring(effect.recipe)
        if adopted_recipes[identity] then
          error("GenerationPlan contains duplicate adopted recipe: " .. tostring(effect.recipe), 2)
        end
        adopted_recipes[identity] = true
        local effect_key = effect_identity(effect)
        if effect_key ~= "" then
          if materialized_effects[effect_key] then
            error("GenerationPlan contains duplicate materialized effect identity: " .. effect_key, 2)
          end
          materialized_effects[effect_key] = row.adoption.owner
        end
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
  local ownership_conflict_count = 0
  for _, row in ipairs(self.rows) do
    ownership_conflict_count = ownership_conflict_count + #((row.effect_ownership and row.effect_ownership.lost) or {})
  end
  self.validation_summary = {
    valid = true,
    row_count = #self.rows,
    action_counts = action_counts,
    reason_counts = reason_counts,
    effect_ownership_conflict_count = ownership_conflict_count
  }
  self.plan_fingerprint = fingerprint.of({
    schema = 3,
    source_fingerprints = self.source_fingerprints,
    rows = rows_fingerprint_material(self.rows),
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
    schema = 3,
    plan_fingerprint = self.plan_fingerprint,
    source_fingerprints = self.source_fingerprints,
    rows = self.rows,
    validation_summary = self.validation_summary
  })
end

function Plan:artifact_view()
  if not self.finalized then error("GenerationPlan must be finalized before artifact view", 2) end
  return {
    schema = 3,
    plan_fingerprint = self.plan_fingerprint,
    source_fingerprints = self.source_fingerprints,
    rows = self.rows,
    validation_summary = self.validation_summary
  }
end

function M.effect_identity(effect)
  return effect_identity(effect)
end

function M.effect_signature(effect)
  return effect_signature(effect)
end

return M
