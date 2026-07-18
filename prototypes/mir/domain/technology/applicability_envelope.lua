local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1
local PREDICATES = {
  ["recipe.visible"] = true,
  ["recipe.productivity-eligible"] = true,
  ["output.deterministic-single-item"] = true,
  ["output.place-result-family"] = true,
  ["risk.none"] = true,
  ["family.semantic-signature"] = true
}

local function sorted_unique(values, label)
  local seen, out = {}, {}
  if type(values) ~= "table" then error("TechnologyApplicabilityEnvelope " .. label .. " is required.", 3) end
  for _, value in ipairs(values) do
    if type(value) ~= "string" or value == "" then
      error("TechnologyApplicabilityEnvelope " .. label .. " contains an invalid value.", 3)
    end
    if not seen[value] then seen[value] = true; table.insert(out, value) end
  end
  table.sort(out)
  return out
end

local function material(envelope)
  return {
    schema = envelope.schema,
    envelope_id = envelope.envelope_id,
    factorio_lines = envelope.factorio_lines,
    required_features = envelope.required_features,
    required_mods = envelope.required_mods,
    structural_predicates = envelope.structural_predicates,
    positive_examples = envelope.positive_examples,
    negative_examples = envelope.negative_examples,
    maximum_new_matches = envelope.maximum_new_matches
  }
end

local function sorted_rows(values, key, label)
  if type(values) ~= "table" then error("TechnologyApplicabilityEnvelope " .. label .. " is required.", 3) end
  local seen, out = {}, {}
  for _, value in ipairs(values) do
    if type(value) ~= "table" or type(value[key]) ~= "string" or value[key] == "" then
      error("TechnologyApplicabilityEnvelope " .. label .. " contains an invalid value.", 3)
    end
    if seen[value[key]] then error("TechnologyApplicabilityEnvelope " .. label .. " contains a duplicate value.", 3) end
    seen[value[key]] = true
    table.insert(out, deepcopy(value))
  end
  table.sort(out, function(left, right) return left[key] < right[key] end)
  return out
end

function M.schema_authority()
  local predicates = {}
  for name, _ in pairs(PREDICATES) do table.insert(predicates, name) end
  table.sort(predicates)
  return {schema = SCHEMA, predicates = predicates}
end

function M.validate(envelope)
  if type(envelope) ~= "table" or envelope.schema ~= SCHEMA then
    error("TechnologyApplicabilityEnvelope schema 1 record is required.", 2)
  end
  if type(envelope.envelope_id) ~= "string" or envelope.envelope_id == "" then
    error("TechnologyApplicabilityEnvelope envelope_id is required.", 2)
  end
  sorted_unique(envelope.factorio_lines, "factorio_lines")
  sorted_unique(envelope.required_features, "required_features")
  sorted_unique(envelope.positive_examples, "positive_examples")
  sorted_unique(envelope.negative_examples, "negative_examples")
  if #envelope.positive_examples == 0 or #envelope.negative_examples == 0 then
    error("TechnologyApplicabilityEnvelope requires positive and negative examples.", 2)
  end
  if type(envelope.required_mods) ~= "table" or #envelope.required_mods == 0
    or type(envelope.structural_predicates) ~= "table" or #envelope.structural_predicates == 0 then
    error("TechnologyApplicabilityEnvelope structural requirements are incomplete.", 2)
  end
  for _, row in ipairs(envelope.required_mods) do
    if type(row) ~= "table" or type(row.id) ~= "string" or row.id == "" then
      error("TechnologyApplicabilityEnvelope required mod is invalid.", 2)
    end
    if row.version ~= nil and (type(row.version) ~= "string" or row.version == "") then
      error("TechnologyApplicabilityEnvelope required mod version is invalid.", 2)
    end
  end
  for _, row in ipairs(envelope.structural_predicates) do
    if type(row) ~= "table" or not PREDICATES[row.predicate] then
      error("TechnologyApplicabilityEnvelope structural predicate is invalid: " .. tostring(row and row.predicate), 2)
    end
  end
  if type(envelope.maximum_new_matches) ~= "number" or envelope.maximum_new_matches < 0
    or envelope.maximum_new_matches % 1 ~= 0 then
    error("TechnologyApplicabilityEnvelope maximum_new_matches is invalid.", 2)
  end
  if envelope.envelope_fingerprint ~= fingerprint.of(material(envelope)) then
    error("TechnologyApplicabilityEnvelope fingerprint is invalid.", 2)
  end
  return true
end

function M.new(record)
  local out = deepcopy(record or {})
  out.schema = SCHEMA
  out.factorio_lines = sorted_unique(out.factorio_lines or {}, "factorio_lines")
  out.required_features = sorted_unique(out.required_features or {}, "required_features")
  out.positive_examples = sorted_unique(out.positive_examples or {}, "positive_examples")
  out.negative_examples = sorted_unique(out.negative_examples or {}, "negative_examples")
  out.required_mods = sorted_rows(out.required_mods or {}, "id", "required_mods")
  out.structural_predicates = sorted_rows(out.structural_predicates or {}, "predicate", "structural_predicates")
  out.maximum_new_matches = out.maximum_new_matches or 0
  out.envelope_fingerprint = fingerprint.of(material(out))
  M.validate(out)
  return out
end

local function contains(values, expected)
  for _, value in ipairs(values or {}) do if value == expected then return true end end
  return false
end

function M.matches(envelope, context)
  M.validate(envelope)
  context = context or {}
  if not contains(envelope.factorio_lines, context.factorio_line) then return false, "factorio-line" end
  for _, feature in ipairs(envelope.required_features) do
    if not (context.features and context.features[feature]) then return false, "feature:" .. feature end
  end
  for _, mod in ipairs(envelope.required_mods) do
    local actual = context.active_mods and context.active_mods[mod.id]
    if not actual then return false, "mod:" .. mod.id end
    if mod.version and actual ~= true and tostring(actual) ~= mod.version then
      return false, "mod-version:" .. mod.id
    end
  end
  for _, predicate in ipairs(envelope.structural_predicates) do
    if not (context.predicates and context.predicates[predicate.predicate]) then
      return false, "predicate:" .. predicate.predicate
    end
  end
  if tonumber(context.new_matches or 0) > envelope.maximum_new_matches then return false, "new-matches" end
  return true, nil
end

return M
