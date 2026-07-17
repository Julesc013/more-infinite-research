local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local REQUIRED_DIMENSIONS = {
  "identity", "effects", "progression", "cost", "presentation", "ownership", "runtime_contracts"
}

local function sorted_unique(values)
  local seen, out = {}, {}
  for _, value in ipairs(values or {}) do
    if value ~= nil and not seen[value] then
      seen[value] = true
      table.insert(out, value)
    end
  end
  table.sort(out)
  return out
end

local function field(value, source, evidence_class, locked, lock_policy)
  return {
    value = deepcopy(value),
    source = source,
    evidence_class = evidence_class,
    locked = locked == true,
    lock_policy = lock_policy or (locked and "locked" or "adaptive")
  }
end

local function source_profile(row)
  local automatic = type(row.spec) == "table" and row.spec.automatic_family ~= nil
  if automatic then
    return "family-rule:" .. tostring(row.stream_key), "generic-inferred", false
  end
  return "stream:" .. tostring(row.stream_key), "legacy-fixed", true
end

local function members_for(row, effects)
  local recipes, items, fluids, entities = {}, {}, {}, {}
  for _, effect in ipairs(effects or {}) do
    if effect.recipe then table.insert(recipes, effect.recipe) end
  end
  local spec = row.spec or {}
  for _, value in ipairs(spec.items or {}) do table.insert(items, value) end
  for _, value in ipairs(spec.fluids or {}) do table.insert(fluids, value) end
  for _, value in ipairs(spec.entities or {}) do table.insert(entities, value) end
  return {
    recipes = sorted_unique(recipes),
    items = sorted_unique(items),
    fluids = sorted_unique(fluids),
    entities = sorted_unique(entities)
  }
end

local function semantic_material(design)
  return {
    schema = design.schema,
    candidate_id = design.candidate_id,
    technology_id = design.technology_id,
    semantic_identity = design.semantic_identity,
    members = design.members,
    design = design.design,
    gates = design.gates,
    provenance = design.provenance,
    maturity = design.maturity,
    context = design.context
  }
end

function M.validate(design)
  if type(design) ~= "table" or design.schema ~= 1 then
    error("TechnologyDesign schema 1 record is required.", 2)
  end
  if type(design.candidate_id) ~= "string" or design.candidate_id == "" then
    error("TechnologyDesign candidate_id is required.", 2)
  end
  if type(design.design) ~= "table" then error("TechnologyDesign design fields are required.", 2) end
  for _, dimension in ipairs(REQUIRED_DIMENSIONS) do
    local record = design.design[dimension]
    if type(record) ~= "table" or record.value == nil or type(record.source) ~= "string"
      or type(record.evidence_class) ~= "string" or type(record.locked) ~= "boolean" then
      error("TechnologyDesign field provenance is invalid: " .. dimension, 2)
    end
  end
  if type(design.provenance) ~= "table" or type(design.provenance.fields) ~= "table" then
    error("TechnologyDesign field provenance map is required.", 2)
  end
  for path, record in pairs(design.provenance.fields) do
    if type(path) ~= "string" or type(record) ~= "table" or record.value == nil
      or type(record.source) ~= "string" or type(record.evidence_class) ~= "string"
      or type(record.locked) ~= "boolean" then
      error("TechnologyDesign leaf-field provenance is invalid: " .. tostring(path), 2)
    end
  end
  local expected = fingerprint.of(semantic_material(design))
  if design.semantic_fingerprint ~= expected then
    error("TechnologyDesign semantic fingerprint differs: " .. design.candidate_id, 2)
  end
  return true
end

function M.from_generation_row(row)
  if type(row) ~= "table" then error("TechnologyDesign requires a GenerationPlan row.", 2) end
  local source, evidence_class, fixed = source_profile(row)
  local fields = row.fields or {}
  local adoption = row.adoption or {}
  local expected = adoption.expected_snapshot or {}
  local effects = row.action == "adopt" and (adoption.effects or {}) or (fields.effects or {})
  local technology_id = row.technology_name or adoption.owner
  local capability = row.direct_effects and "direct-effect" or "recipe-productivity"
  local automatic_family = type(row.spec) == "table" and row.spec.automatic_family or nil
  local design_maturity = automatic_family
    and (type(automatic_family) == "table" and automatic_family.creation_maturity or "experimental")
    or "canonical"
  local runtime_action = row.action == "skip" and "diagnose" or row.action
  local identity_locked = fixed and technology_id ~= nil
  local progression = {
    prerequisites = deepcopy(fields.prerequisites or expected.prerequisites or {}),
    science = deepcopy(fields.ingredients or ((expected.unit or {}).ingredients) or {})
  }
  local cost = {
    count_formula = fields.count_formula or (expected.unit or {}).count_formula,
    count = (expected.unit or {}).count,
    research_time = fields.research_time or (expected.unit or {}).time,
    max_level = fields.max_level or expected.max_level
  }
  local presentation = {
    localised_name = deepcopy(fields.localised_name),
    localised_description = deepcopy(fields.localised_description),
    icons = deepcopy(fields.icons or {}),
    order = "p[" .. tostring(row.stream_key) .. "]"
  }
  local field_provenance = {}
  local function record(path, value, record_source, record_evidence, locked, lock_policy)
    if value ~= nil then
      field_provenance[path] = field(value, record_source, record_evidence, locked, lock_policy)
    end
  end
  record("identity.technology_id", technology_id, source, evidence_class, identity_locked)
  record("identity.candidate_id", "mir-candidate/" .. capability .. "/" .. tostring(row.stream_key),
    source, evidence_class, false)
  record("members", members_for(row, effects), source, evidence_class, false)
  record("effects", effects, source, evidence_class, false,
    fixed and "adaptive-within-reviewed-policy" or "adaptive")
  record("progression.prerequisites", progression.prerequisites, "planner:progression", evidence_class, false)
  record("progression.science", progression.science, "planner:progression", evidence_class, false)
  record("cost.count_formula", cost.count_formula, "planner:cost", evidence_class, false)
  record("cost.count", cost.count, "planner:cost", evidence_class, false)
  record("cost.research_time", cost.research_time, "planner:cost", evidence_class, false)
  record("cost.max_level", cost.max_level, "planner:cost", evidence_class, false)
  record("presentation.localised_name", presentation.localised_name, source, evidence_class, fixed)
  record("presentation.localised_description", presentation.localised_description, source, evidence_class, fixed)
  record("presentation.icons", presentation.icons, "presentation:fallback-chain", evidence_class, false)
  record("presentation.order", presentation.order, source, evidence_class, fixed)
  record("ownership.action", row.action, source, evidence_class, fixed)
  record("ownership.migration_policy", row.spec and row.spec.migration_policy, source, evidence_class, fixed)
  record("runtime_contracts.upgrade", true, source, evidence_class, fixed)
  local result = {
    schema = 1,
    candidate_id = "mir-candidate/" .. capability .. "/" .. tostring(row.stream_key),
    technology_id = technology_id,
    semantic_identity = {
      capability = capability,
      family = (row.family_ids and row.family_ids[1]) or (row.spec and row.spec.family) or row.stream_key,
      partition = row.stream_key
    },
    members = members_for(row, effects),
    design = {
      identity = field({
        technology_name = technology_id,
        stream_key = row.stream_key,
        manifest_id = row.manifest_id,
        level = 1
      }, source, evidence_class, identity_locked),
      effects = field(effects, source, evidence_class, false, fixed and "adaptive-within-reviewed-policy" or "adaptive"),
      progression = field(progression, "planner:progression", fixed and "legacy-fixed" or "generic-inferred", false),
      cost = field(cost, "planner:cost", fixed and "legacy-fixed" or "generic-inferred", false),
      presentation = field(presentation, source, evidence_class, false, "field-specific"),
      ownership = field({
        action = row.action,
        owner = adoption.owner,
        migration_policy = row.spec and row.spec.migration_policy
      }, source, evidence_class, fixed),
      runtime_contracts = field({
        upgrade = true,
        migration_policy = row.spec and row.spec.migration_policy
      }, source, evidence_class, fixed)
    },
    gates = deepcopy(row.gates or {}),
    provenance = {
      source = row.source,
      provider_ids = deepcopy(row.provider_ids or {}),
      family_ids = deepcopy(row.family_ids or {}),
      evidence_class = evidence_class,
      fields = field_provenance
    },
    maturity = {
      safety = row.action == "skip" and "blocked" or "safe",
      discovery_evidence = automatic_family and "structural" or "exact",
      design_maturity = design_maturity,
      validation_evidence = "contract",
      applicability_scope = automatic_family and "structural-envelope" or "target-line",
      identity_stability = technology_id and "released" or "provisional",
      runtime_action = runtime_action,
      public_claim = "none"
    },
    context = {
      generation_plan_schema = row.schema,
      stream_key = row.stream_key,
      action_reason = row.reason
    }
  }
  result.semantic_fingerprint = fingerprint.of(semantic_material(result))
  M.validate(result)
  return result
end

function M.prototype_shape(design)
  M.validate(design)
  local identity = design.design.identity.value
  local progression = design.design.progression.value
  local cost = design.design.cost.value
  local runtime_contracts = design.design.runtime_contracts.value
  return deepcopy({
    name = identity.technology_name,
    effects = design.design.effects.value,
    prerequisites = progression.prerequisites,
    unit = {
      ingredients = progression.science,
      count_formula = cost.count_formula,
      count = cost.count,
      time = cost.research_time
    },
    max_level = cost.max_level,
    upgrade = runtime_contracts.upgrade
  })
end

return M
