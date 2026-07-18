local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")

local M = {}

local SCHEMA = {
  schema = 2,
  dimensions = {
    "identity", "effects", "progression", "cost", "presentation", "ownership", "runtime_contracts"
  },
  subject_categories = {
    "recipes", "products", "items", "fluids", "entities", "technologies", "effect_targets",
    "science_packs", "surfaces"
  },
  fingerprints = {
    "subject_fingerprint", "design_fingerprint", "prototype_fingerprint", "qualification_fingerprint"
  },
  maturity_enums = {
    safety = {"blocked", "quarantined", "safe"},
    discovery_evidence = {"none", "structural", "exact", "reviewed-examples"},
    design_maturity = {
      "proposed", "experimental", "automation-qualified", "human-reviewed", "promoted", "released-canonical"
    },
    validation_evidence = {
      "none", "fixture", "exact-mod", "exact-ecosystem", "upgrade-qualified", "interactive-qualified"
    },
    applicability_scope = {"none", "exact-ecosystem", "structural-envelope", "target-line"},
    identity_stability = {"unassigned", "provisional", "reserved", "stable-unreleased", "released", "retired"},
    runtime_action = {"diagnose", "preview", "emit", "adopt", "patch-existing", "continuation"},
    public_claim = {
      "none", "loads", "observed", "cooperates", "diagnostic-only", "partial-support",
      "full-family-support", "full-pack-support"
    }
  },
  evidence_classes = {
    "none", "generic-inferred", "legacy-fixed", "generated-policy", "target-profile", "manifest",
    "planner", "fixture", "exact-mod", "exact-ecosystem", "human-review", "fallback"
  },
  lock_states = {"none", "partial", "all"},
  lock_policies = {"adaptive", "locked", "field-specific", "adaptive-within-envelope"},
  required_paths = {
    "identity.technology_id", "identity.candidate_id", "identity.identity_state", "subjects", "members", "effects",
    "progression.prerequisites", "progression.science", "cost.count_formula", "cost.count",
    "cost.research_time", "cost.max_level", "presentation.localised_name",
    "presentation.localised_description", "presentation.icons", "presentation.order", "presentation.level",
    "presentation.enabled", "presentation.hidden", "ownership.action", "ownership.migration_policy",
    "runtime_contracts.upgrade"
  },
  cross_field_invariants = {
    "technology-id-matches-identity-value",
    "candidate-id-matches-identity-value",
    "identity-state-matches-authority",
    "members-match-subject-projection",
    "dimension-values-match-leaf-provenance",
    "dimension-lock-state-matches-leaf-locks",
    "fingerprints-match-canonical-material"
  }
}

local DIMENSION_PATHS = {
  identity = {"identity.technology_id", "identity.candidate_id", "identity.identity_state"},
  effects = {"effects"},
  progression = {"progression.prerequisites", "progression.science"},
  cost = {"cost.count_formula", "cost.count", "cost.research_time", "cost.max_level"},
  presentation = {
    "presentation.localised_name", "presentation.localised_description", "presentation.icons",
    "presentation.order", "presentation.level", "presentation.enabled", "presentation.hidden"
  },
  ownership = {"ownership.action", "ownership.migration_policy"},
  runtime_contracts = {"runtime_contracts.upgrade"}
}

local function enum_set(values)
  local out = {}
  for _, value in ipairs(values) do out[value] = true end
  return out
end

local EVIDENCE_CLASSES = enum_set(SCHEMA.evidence_classes)
local LOCK_STATES = enum_set(SCHEMA.lock_states)
local LOCK_POLICIES = enum_set(SCHEMA.lock_policies)
local MATURITY_ENUMS = {}
for axis, values in pairs(SCHEMA.maturity_enums) do MATURITY_ENUMS[axis] = enum_set(values) end

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

local function sorted_records(values)
  local by_identity, out = {}, {}
  for _, value in ipairs(values or {}) do
    local identity = fingerprint.canonical(value)
    if not by_identity[identity] then by_identity[identity] = deepcopy(value) end
  end
  for _, value in pairs(by_identity) do table.insert(out, value) end
  table.sort(out, function(left, right)
    return fingerprint.canonical(left) < fingerprint.canonical(right)
  end)
  return out
end

local function same(left, right)
  return fingerprint.of({value = left}) == fingerprint.of({value = right})
end

local function leaf(value, source, evidence_class, locked, lock_policy, envelope)
  local lock_state = locked and "all" or "none"
  return {
    present = value ~= nil,
    value = deepcopy(value),
    source = source,
    evidence_class = evidence_class,
    lock_state = lock_state,
    locked = lock_state == "all",
    lock_policy = lock_policy or (locked and "locked" or "adaptive"),
    envelope = deepcopy(envelope)
  }
end

local function dimension(value, source, evidence_class, paths, fields)
  local locked_count = 0
  for _, path in ipairs(paths) do
    if fields[path].lock_state == "all" then locked_count = locked_count + 1 end
  end
  local lock_state = locked_count == 0 and "none" or locked_count == #paths and "all" or "partial"
  return {
    present = true,
    value = deepcopy(value),
    source = source,
    evidence_class = evidence_class,
    lock_state = lock_state,
    locked = lock_state == "all",
    lock_policy = lock_state == "all" and "locked" or lock_state == "partial" and "field-specific" or "adaptive"
  }
end

local function source_profile(row)
  local automatic = type(row.spec) == "table" and row.spec.automatic_family ~= nil
  if automatic then
    return "family-rule:" .. tostring(row.stream_key), "generic-inferred", false
  end
  return "stream:" .. tostring(row.stream_key), "legacy-fixed", true
end

local function effect_target(effect)
  if type(effect) ~= "table" or effect.type == nil or effect.type == "nothing" then return nil end
  for _, field_name in ipairs({"recipe", "ammo_category", "turret_id", "fluid", "item", "space_location"}) do
    if effect[field_name] ~= nil then
      return {type = effect.type, target_type = field_name, name = tostring(effect[field_name])}
    end
  end
  return {type = effect.type, target_type = "native-modifier", name = effect.type}
end

local function subjects_for(row, effects, progression)
  local recipes, effect_targets, science_packs, surfaces = {}, {}, {}, {}
  for _, effect in ipairs(effects or {}) do
    if effect.recipe then table.insert(recipes, effect.recipe) end
    local target = effect_target(effect)
    if target and effect.type ~= "change-recipe-productivity" then table.insert(effect_targets, target) end
    if effect.space_location then table.insert(surfaces, effect.space_location) end
  end
  for _, ingredient in ipairs((progression and progression.science) or {}) do
    table.insert(science_packs, ingredient.name or ingredient[1])
  end
  local spec = row.spec or {}
  return {
    recipes = sorted_unique(recipes),
    products = {},
    items = sorted_unique(spec.items or {}),
    fluids = sorted_unique(spec.fluids or {}),
    entities = sorted_unique(spec.entities or {}),
    technologies = {},
    effect_targets = sorted_records(effect_targets),
    science_packs = sorted_unique(science_packs),
    surfaces = sorted_unique(surfaces)
  }
end

local function members_from_subjects(subjects)
  return {
    recipes = deepcopy(subjects.recipes),
    items = deepcopy(subjects.items),
    fluids = deepcopy(subjects.fluids),
    entities = deepcopy(subjects.entities)
  }
end

local function capability_for(row, effects)
  if not row.direct_effects then return "recipe-productivity" end
  local types = {}
  for _, effect in ipairs(effects or {}) do
    if effect.type and effect.type ~= "nothing" then table.insert(types, effect.type) end
  end
  types = sorted_unique(types)
  if #types == 0 then return "direct-effect" end
  return table.concat(types, "+")
end

local function identity_state_for(row, technology_id, fixed)
  if not technology_id then return "unassigned", "generation-plan" end
  local explicit = row.spec and row.spec.identity_state
  if explicit then return explicit, "stream-manifest" end
  if fixed then return "released", "legacy-stream-manifest" end
  return "provisional", "candidate-catalog"
end

local function effect_envelope(effects)
  local effect_types, minimum, maximum = {}, nil, nil
  for _, effect in ipairs(effects or {}) do
    if effect.type then table.insert(effect_types, effect.type) end
    local value = effect.change or effect.modifier
    if type(value) == "number" then
      minimum = minimum and math.min(minimum, value) or value
      maximum = maximum and math.max(maximum, value) or value
    end
  end
  return {
    permitted_effect_types = sorted_unique(effect_types),
    effect_change = minimum and {minimum = minimum, maximum = maximum} or nil,
    maximum_member_additions = 4096
  }
end

local function subject_material(design)
  return {
    schema = design.schema,
    semantic_identity = design.semantic_identity,
    subjects = design.subjects
  }
end

local function design_material(design)
  local values = {}
  for _, name in ipairs(SCHEMA.dimensions) do values[name] = design.design[name].value end
  return {schema = design.schema, candidate_id = design.candidate_id, values = values}
end

local function prototype_projection_unvalidated(design)
  local identity = design.design.identity.value
  local progression = design.design.progression.value
  local cost = design.design.cost.value
  local presentation = design.design.presentation.value
  local runtime_contracts = design.design.runtime_contracts.value
  return {
    name = identity.technology_name,
    localised_name = deepcopy(presentation.localised_name),
    localised_description = deepcopy(presentation.localised_description),
    icons = deepcopy(presentation.icons),
    effects = deepcopy(design.design.effects.value),
    prerequisites = deepcopy(progression.prerequisites),
    unit = {
      ingredients = deepcopy(progression.science),
      count_formula = cost.count_formula,
      count = cost.count,
      time = cost.research_time
    },
    max_level = cost.max_level,
    order = presentation.order,
    level = presentation.level,
    enabled = presentation.enabled,
    hidden = presentation.hidden,
    upgrade = runtime_contracts.upgrade
  }
end

local function qualification_material(design)
  return {
    schema = design.schema,
    subject_fingerprint = design.subject_fingerprint,
    design_fingerprint = design.design_fingerprint,
    prototype_fingerprint = design.prototype_fingerprint,
    identity_authority = design.identity_authority,
    gates = design.gates,
    provenance = design.provenance,
    maturity = design.maturity,
    context = design.context
  }
end

local function validate_string_array(values, label)
  if type(values) ~= "table" then error("TechnologyDesign " .. label .. " must be an array.", 3) end
  for _, value in ipairs(values) do
    if type(value) ~= "string" or value == "" then
      error("TechnologyDesign " .. label .. " contains an invalid value.", 3)
    end
  end
end

local function validate_field_record(record, label)
  if type(record) ~= "table" or type(record.present) ~= "boolean"
    or type(record.source) ~= "string" or record.source == ""
    or not EVIDENCE_CLASSES[record.evidence_class]
    or not LOCK_STATES[record.lock_state] or not LOCK_POLICIES[record.lock_policy]
    or type(record.locked) ~= "boolean" or record.locked ~= (record.lock_state == "all") then
    error("TechnologyDesign field provenance is invalid: " .. label, 3)
  end
  if record.lock_state == "partial" and label:find("provenance.fields", 1, true) then
    error("TechnologyDesign leaf lock_state cannot be partial: " .. label, 3)
  end
  if record.present == false and record.value ~= nil then
    error("TechnologyDesign absent field carries a value: " .. label, 3)
  end
  if record.lock_policy == "adaptive-within-envelope" and type(record.envelope) ~= "table" then
    error("TechnologyDesign adaptive field lacks an envelope: " .. label, 3)
  end
end

local function expected_dimension_values(design)
  local fields = design.provenance.fields
  return {
    identity = {
      technology_name = fields["identity.technology_id"].value,
      candidate_id = fields["identity.candidate_id"].value,
      identity_state = fields["identity.identity_state"].value,
      stream_key = design.design.identity.value.stream_key,
      manifest_id = design.design.identity.value.manifest_id
    },
    effects = fields.effects.value,
    progression = {
      prerequisites = fields["progression.prerequisites"].value,
      science = fields["progression.science"].value
    },
    cost = {
      count_formula = fields["cost.count_formula"].value,
      count = fields["cost.count"].value,
      research_time = fields["cost.research_time"].value,
      max_level = fields["cost.max_level"].value
    },
    presentation = {
      localised_name = fields["presentation.localised_name"].value,
      localised_description = fields["presentation.localised_description"].value,
      icons = fields["presentation.icons"].value,
      order = fields["presentation.order"].value,
      level = fields["presentation.level"].value,
      enabled = fields["presentation.enabled"].value,
      hidden = fields["presentation.hidden"].value
    },
    ownership = {
      action = fields["ownership.action"].value,
      owner = design.design.ownership.value.owner,
      migration_policy = fields["ownership.migration_policy"].value
    },
    runtime_contracts = {
      upgrade = fields["runtime_contracts.upgrade"].value,
      migration_policy = design.design.runtime_contracts.value.migration_policy
    }
  }
end

function M.schema_authority()
  return deepcopy(SCHEMA)
end

function M.validate(design)
  if type(design) ~= "table" or design.schema ~= SCHEMA.schema then
    error("TechnologyDesign schema 2 record is required.", 2)
  end
  if type(design.candidate_id) ~= "string" or design.candidate_id == "" then
    error("TechnologyDesign candidate_id is required.", 2)
  end
  if type(design.semantic_identity) ~= "table"
    or type(design.semantic_identity.capability) ~= "string" or design.semantic_identity.capability == ""
    or type(design.semantic_identity.family) ~= "string" or design.semantic_identity.family == ""
    or type(design.semantic_identity.partition) ~= "string" or design.semantic_identity.partition == "" then
    error("TechnologyDesign semantic_identity is invalid.", 2)
  end
  if type(design.subjects) ~= "table" then error("TechnologyDesign subjects are required.", 2) end
  for _, category in ipairs(SCHEMA.subject_categories) do
    if category == "effect_targets" then
      if type(design.subjects[category]) ~= "table" then error("TechnologyDesign effect_targets are invalid.", 2) end
      for _, target in ipairs(design.subjects[category]) do
        if type(target) ~= "table" or type(target.type) ~= "string" or type(target.name) ~= "string" then
          error("TechnologyDesign effect target is invalid.", 2)
        end
      end
    else
      validate_string_array(design.subjects[category], "subjects." .. category)
    end
  end
  if type(design.members) ~= "table" then error("TechnologyDesign members are required.", 2) end
  for _, category in ipairs({"recipes", "items", "fluids", "entities"}) do
    validate_string_array(design.members[category], "members." .. category)
  end
  if not same(design.members, members_from_subjects(design.subjects)) then
    error("TechnologyDesign members differ from subjects.", 2)
  end
  if type(design.design) ~= "table" then error("TechnologyDesign design fields are required.", 2) end
  if type(design.provenance) ~= "table" or type(design.provenance.fields) ~= "table" then
    error("TechnologyDesign field provenance map is required.", 2)
  end
  for _, path in ipairs(SCHEMA.required_paths) do
    if type(design.provenance.fields[path]) ~= "table" then
      error("TechnologyDesign required leaf-field provenance is missing: " .. path, 2)
    end
  end
  for path, record in pairs(design.provenance.fields) do
    if type(path) ~= "string" then error("TechnologyDesign leaf path is invalid.", 2) end
    validate_field_record(record, "provenance.fields." .. path)
  end
  for _, name in ipairs(SCHEMA.dimensions) do
    local record = design.design[name]
    validate_field_record(record, "design." .. name)
    local locked_count = 0
    for _, path in ipairs(DIMENSION_PATHS[name]) do
      if design.provenance.fields[path].lock_state == "all" then locked_count = locked_count + 1 end
    end
    local expected_state = locked_count == 0 and "none"
      or locked_count == #DIMENSION_PATHS[name] and "all" or "partial"
    if record.lock_state ~= expected_state then
      error("TechnologyDesign dimension lock_state differs from leaf locks: " .. name, 2)
    end
  end
  if type(design.maturity) ~= "table" then error("TechnologyDesign maturity is required.", 2) end
  for axis, allowed in pairs(MATURITY_ENUMS) do
    if not allowed[design.maturity[axis]] then
      error("TechnologyDesign maturity axis is invalid: " .. axis, 2)
    end
  end
  if type(design.gates) ~= "table" or type(design.context) ~= "table"
    or type(design.identity_authority) ~= "table" then
    error("TechnologyDesign qualification context is invalid.", 2)
  end
  local identity = design.design.identity.value
  if design.technology_id ~= identity.technology_name
    or design.candidate_id ~= identity.candidate_id
    or design.maturity.identity_stability ~= identity.identity_state
    or design.identity_authority.state ~= identity.identity_state then
    error("TechnologyDesign identity authority is internally inconsistent.", 2)
  end
  if identity.identity_state == "released" and (not design.technology_id or design.technology_id == "") then
    error("TechnologyDesign released identity lacks a technology_id.", 2)
  end
  local expected_values = expected_dimension_values(design)
  for _, name in ipairs(SCHEMA.dimensions) do
    if not same(design.design[name].value, expected_values[name]) then
      error("TechnologyDesign dimension differs from leaf provenance: " .. name, 2)
    end
  end
  if not same(design.subjects, design.provenance.fields.subjects.value)
    or not same(design.members, design.provenance.fields.members.value) then
    error("TechnologyDesign subjects or members differ from provenance.", 2)
  end
  local expected_subject = fingerprint.of(subject_material(design))
  local expected_design = fingerprint.of(design_material(design))
  local expected_prototype = fingerprint.of(prototype_projection_unvalidated(design))
  if design.subject_fingerprint ~= expected_subject
    or design.design_fingerprint ~= expected_design
    or design.prototype_fingerprint ~= expected_prototype then
    error("TechnologyDesign semantic identity fingerprints differ: " .. design.candidate_id, 2)
  end
  local expected_qualification = fingerprint.of(qualification_material(design))
  if design.qualification_fingerprint ~= expected_qualification
    or design.semantic_fingerprint ~= expected_qualification then
    error("TechnologyDesign qualification fingerprint differs: " .. design.candidate_id, 2)
  end
  return true
end

function M.refresh_fingerprints(design)
  design.subject_fingerprint = fingerprint.of(subject_material(design))
  design.design_fingerprint = fingerprint.of(design_material(design))
  design.prototype_fingerprint = fingerprint.of(prototype_projection_unvalidated(design))
  design.qualification_fingerprint = fingerprint.of(qualification_material(design))
  design.semantic_fingerprint = design.qualification_fingerprint
  return design
end

function M.from_generation_row(row)
  if type(row) ~= "table" then error("TechnologyDesign requires a GenerationPlan row.", 2) end
  local source, evidence_class, fixed = source_profile(row)
  local fields = row.fields or {}
  local adoption = row.adoption or {}
  local expected = adoption.expected_snapshot or {}
  local effects = row.action == "adopt" and (adoption.effects or {}) or (fields.effects or {})
  local technology_id = row.technology_name or adoption.owner
  local capability = capability_for(row, effects)
  local candidate_id = "mir-candidate/" .. capability .. "/" .. tostring(row.stream_key)
  local automatic_family = type(row.spec) == "table" and row.spec.automatic_family or nil
  local identity_state, identity_authority = identity_state_for(row, technology_id, fixed)
  local design_maturity = automatic_family and
    (type(automatic_family) == "table" and automatic_family.creation_maturity or "experimental")
    or "released-canonical"
  if design_maturity == "reviewed" then design_maturity = "human-reviewed" end
  local runtime_action = row.action == "skip" and "diagnose" or row.action
  local identity_locked = fixed and technology_id ~= nil
  local progression = {
    prerequisites = deepcopy(fields.prerequisites or expected.prerequisites or {}),
    science = deepcopy(fields.ingredients or ((expected.unit or {}).ingredients) or {})
  }
  local cost = {
    count_formula = fields.count_formula or (expected.unit or {}).count_formula,
    count = fields.count or (expected.unit or {}).count,
    research_time = fields.research_time or (expected.unit or {}).time,
    max_level = fields.max_level or expected.max_level
  }
  local presentation = {
    localised_name = deepcopy(fields.localised_name),
    localised_description = deepcopy(fields.localised_description),
    icons = deepcopy(fields.icons or {}),
    order = fields.order or ("p[" .. tostring(row.stream_key) .. "]"),
    level = fields.level or 1,
    enabled = fields.enabled,
    hidden = fields.hidden
  }
  local subjects = subjects_for(row, effects, progression)
  local members = members_from_subjects(subjects)
  local field_provenance = {}
  local function record(path, value, record_source, record_evidence, locked, lock_policy, envelope)
    field_provenance[path] = leaf(value, record_source, record_evidence, locked, lock_policy, envelope)
  end
  record("identity.technology_id", technology_id, identity_authority, "manifest", identity_locked)
  record("identity.candidate_id", candidate_id, source, evidence_class, false)
  record("identity.identity_state", identity_state, identity_authority, "manifest", identity_locked)
  record("subjects", subjects, source, evidence_class, false)
  record("members", members, source, evidence_class, false)
  record("effects", effects, source, evidence_class, false, fixed and "adaptive-within-envelope" or "adaptive",
    fixed and effect_envelope(effects) or nil)
  record("progression.prerequisites", progression.prerequisites, "planner:progression", "planner", false)
  record("progression.science", progression.science, "planner:progression", "planner", false)
  record("cost.count_formula", cost.count_formula, "planner:cost", "planner", false)
  record("cost.count", cost.count, "planner:cost", "planner", false)
  record("cost.research_time", cost.research_time, "planner:cost", "planner", false)
  record("cost.max_level", cost.max_level, "planner:cost", "planner", false)
  record("presentation.localised_name", presentation.localised_name, source, evidence_class, fixed)
  record("presentation.localised_description", presentation.localised_description, source, evidence_class, fixed)
  record("presentation.icons", presentation.icons, "presentation:fallback-chain", "fallback", false)
  record("presentation.order", presentation.order, source, evidence_class, fixed)
  record("presentation.level", presentation.level, source, evidence_class, fixed)
  record("presentation.enabled", presentation.enabled, source, evidence_class, fixed)
  record("presentation.hidden", presentation.hidden, source, evidence_class, fixed)
  record("ownership.action", row.action, source, evidence_class, fixed)
  record("ownership.migration_policy", row.spec and row.spec.migration_policy, source, evidence_class, fixed)
  record("runtime_contracts.upgrade", fields.upgrade ~= false, source, evidence_class, fixed)

  local identity_value = {
    technology_name = technology_id,
    candidate_id = candidate_id,
    identity_state = identity_state,
    stream_key = row.stream_key,
    manifest_id = row.manifest_id
  }
  local ownership_value = {
    action = row.action,
    owner = adoption.owner,
    migration_policy = row.spec and row.spec.migration_policy
  }
  local runtime_value = {
    upgrade = fields.upgrade ~= false,
    migration_policy = row.spec and row.spec.migration_policy
  }
  local result = {
    schema = SCHEMA.schema,
    candidate_id = candidate_id,
    technology_id = technology_id,
    identity_authority = {source = identity_authority, state = identity_state},
    semantic_identity = {
      capability = capability,
      family = (row.family_ids and row.family_ids[1]) or (row.spec and row.spec.family) or row.stream_key,
      partition = row.stream_key
    },
    subjects = subjects,
    members = members,
    design = {
      identity = dimension(identity_value, source, evidence_class, DIMENSION_PATHS.identity, field_provenance),
      effects = dimension(effects, source, evidence_class, DIMENSION_PATHS.effects, field_provenance),
      progression = dimension(progression, "planner:progression", "planner", DIMENSION_PATHS.progression, field_provenance),
      cost = dimension(cost, "planner:cost", "planner", DIMENSION_PATHS.cost, field_provenance),
      presentation = dimension(presentation, source, evidence_class, DIMENSION_PATHS.presentation, field_provenance),
      ownership = dimension(ownership_value, source, evidence_class, DIMENSION_PATHS.ownership, field_provenance),
      runtime_contracts = dimension(runtime_value, source, evidence_class, DIMENSION_PATHS.runtime_contracts, field_provenance)
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
      validation_evidence = "none",
      applicability_scope = automatic_family and "structural-envelope" or "target-line",
      identity_stability = identity_state,
      runtime_action = runtime_action,
      public_claim = "none"
    },
    context = {
      generation_plan_schema = row.schema,
      stream_key = row.stream_key,
      action_reason = row.reason,
      target_profile_fingerprint = row.target_profile_fingerprint
    }
  }
  M.refresh_fingerprints(result)
  M.validate(result)
  return result
end

function M.graph_projection(design)
  M.validate(design)
  return deepcopy({
    name = design.design.identity.value.technology_name,
    prerequisites = design.design.progression.value.prerequisites
  })
end

function M.prototype_projection(design)
  M.validate(design)
  return deepcopy(prototype_projection_unvalidated(design))
end

function M.presentation_projection(design)
  M.validate(design)
  local identity = design.design.identity.value
  local presentation = design.design.presentation.value
  return deepcopy({
    name = identity.technology_name,
    localised_name = presentation.localised_name,
    localised_description = presentation.localised_description,
    icons = presentation.icons,
    order = presentation.order,
    level = presentation.level,
    enabled = presentation.enabled,
    hidden = presentation.hidden
  })
end

function M.save_identity_projection(design)
  M.validate(design)
  local identity = design.design.identity.value
  local ownership = design.design.ownership.value
  return deepcopy({
    technology_id = design.technology_id,
    identity_state = identity.identity_state,
    migration_policy = ownership.migration_policy,
    upgrade = design.design.runtime_contracts.value.upgrade
  })
end

function M.prototype_shape(design)
  return M.prototype_projection(design)
end

function M.diff(before, after)
  M.validate(before)
  M.validate(after)
  local paths, seen = {}, {}
  for _, path in ipairs(SCHEMA.required_paths) do
    table.insert(paths, path)
    seen[path] = true
  end
  for path, _ in pairs(before.provenance.fields) do if not seen[path] then table.insert(paths, path); seen[path] = true end end
  for path, _ in pairs(after.provenance.fields) do if not seen[path] then table.insert(paths, path); seen[path] = true end end
  table.sort(paths)
  local out = {}
  for _, path in ipairs(paths) do
    local left, right = before.provenance.fields[path], after.provenance.fields[path]
    if not same(left and {present = left.present, value = left.value}, right and {present = right.present, value = right.value}) then
      table.insert(out, {path = path, before = deepcopy(left), after = deepcopy(right)})
    end
  end
  return out
end

local function authorized(path, authorization)
  if authorization == "override" then return true end
  if type(authorization) ~= "table" then return false end
  if authorization.allow_all_locked == true then return true end
  for _, allowed in ipairs(authorization.allowed_paths or {}) do if allowed == path then return true end end
  return false
end

local function assert_envelope(path, before_record, after_record)
  local envelope = before_record.envelope
  if not envelope then return end
  if path == "effects" then
    local permitted = enum_set(envelope.permitted_effect_types or {})
    local bounds = envelope.effect_change
    for _, effect in ipairs(after_record.value or {}) do
      if not permitted[effect.type] then error("TechnologyDesign effect left its approved envelope: " .. tostring(effect.type), 3) end
      local value = effect.change or effect.modifier
      if bounds and type(value) == "number" and (value < bounds.minimum or value > bounds.maximum) then
        error("TechnologyDesign effect value left its approved envelope: " .. tostring(value), 3)
      end
    end
    local additions = #((after_record and after_record.value) or {}) - #((before_record and before_record.value) or {})
    if additions > (envelope.maximum_member_additions or 0) then
      error("TechnologyDesign effect membership left its approved envelope.", 3)
    end
  end
end

function M.assert_locks(before, after, authorization)
  local changes = M.diff(before, after)
  for _, change in ipairs(changes) do
    local record = change.before
    if record and record.lock_state == "all" and not authorized(change.path, authorization) then
      error("TechnologyDesign locked field changed without authorization: " .. change.path, 2)
    end
    if record and record.lock_policy == "adaptive-within-envelope" then
      assert_envelope(change.path, record, change.after)
    end
  end
  return true
end

function M.merge(base, overlay, authority)
  M.validate(base)
  M.validate(overlay)
  M.assert_locks(base, overlay, authority)
  return deepcopy(overlay)
end

function M.assert_generation_row(row)
  if type(row) ~= "table" or row.action ~= "emit" then return true end
  if not row.technology_design then
    error("GenerationPlan emitted row requires TechnologyDesign schema 2: " .. tostring(row.stream_key), 2)
  end
  M.validate(row.technology_design)
  local design = row.technology_design
  local projection = M.prototype_projection(design)
  local legacy = row.fields or {}
  local mismatches = {}
  local function compare(path, left, right)
    if not same(left, right) then table.insert(mismatches, path) end
  end
  compare("name", row.technology_name, projection.name)
  compare("effects", legacy.effects, projection.effects)
  compare("prerequisites", legacy.prerequisites, projection.prerequisites)
  compare("ingredients", legacy.ingredients, projection.unit.ingredients)
  compare("count_formula", legacy.count_formula, projection.unit.count_formula)
  compare("count", legacy.count, projection.unit.count)
  compare("research_time", legacy.research_time, projection.unit.time)
  compare("max_level", legacy.max_level, projection.max_level)
  compare("localised_name", legacy.localised_name, projection.localised_name)
  compare("localised_description", legacy.localised_description, projection.localised_description)
  compare("icons", legacy.icons or {}, projection.icons)
  compare("order", legacy.order or ("p[" .. tostring(row.stream_key) .. "]"), projection.order)
  compare("level", legacy.level or 1, projection.level)
  compare("enabled", legacy.enabled, projection.enabled)
  compare("hidden", legacy.hidden, projection.hidden)
  compare("upgrade", legacy.upgrade ~= false, projection.upgrade)
  if #mismatches > 0 then
    error("GenerationPlan legacy projection differs from TechnologyDesign: " .. tostring(row.stream_key)
      .. " fields=" .. table.concat(mismatches, ","), 2)
  end
  return true
end

return M
