local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1

local REQUIRED_TABLES = {
  "prototype_surfaces", "surface_fingerprints", "relationship_indexes", "recipe_facts",
  "graph_input", "effect_target_inventory", "provider_inputs", "stream_inputs", "base_continuation_inputs",
  "source_fingerprints"
}

local function material(record)
  local out = deepcopy(record)
  out.snapshot_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA
    or record.record_type ~= "CompilationSnapshot" then
    error("CompilationSnapshot schema 1 record is required.", 2)
  end
  for _, field in ipairs(REQUIRED_TABLES) do
    if type(record[field]) ~= "table" then
      error("CompilationSnapshot table field is required: " .. field, 2)
    end
  end
  for surface, value in pairs(record.prototype_surfaces) do
    if record.surface_fingerprints[surface] ~= fingerprint.of(value) then
      error("CompilationSnapshot prototype surface fingerprint differs: " .. tostring(surface), 2)
    end
  end
  if record.relationship_fingerprint ~= fingerprint.of(record.relationship_indexes)
    or record.recipe_facts_fingerprint ~= fingerprint.of(record.recipe_facts)
    or record.graph_input_fingerprint ~= fingerprint.of(record.graph_input)
    or record.effect_target_inventory_fingerprint ~= fingerprint.of(record.effect_target_inventory)
    or record.provider_input_fingerprint ~= fingerprint.of(record.provider_inputs) then
    error("CompilationSnapshot derived fingerprint is invalid.", 2)
  end
  if record.snapshot_fingerprint ~= fingerprint.of(material(record)) then
    error("CompilationSnapshot fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = SCHEMA
  record.record_type = "CompilationSnapshot"
  for _, field in ipairs(REQUIRED_TABLES) do record[field] = record[field] or {} end
  record.surface_fingerprints = {}
  for surface, value in pairs(record.prototype_surfaces) do
    record.surface_fingerprints[surface] = fingerprint.of(value)
  end
  record.relationship_fingerprint = fingerprint.of(record.relationship_indexes)
  record.recipe_facts_fingerprint = fingerprint.of(record.recipe_facts)
  record.graph_input_fingerprint = fingerprint.of(record.graph_input)
  record.effect_target_inventory_fingerprint = fingerprint.of(record.effect_target_inventory)
  record.provider_input_fingerprint = fingerprint.of(record.provider_inputs)
  record.snapshot_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.snapshot(record)
  M.validate(record)
  return deepcopy(record)
end

return M
