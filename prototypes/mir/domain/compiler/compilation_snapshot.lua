local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 2

local REQUIRED_DOMAINS = {
  "recipes", "technologies", "items", "entities", "labs", "science_packs"
}

local REUSED_QUALIFICATION_DOMAINS = {
  "recipes", "technologies", "items", "entities", "labs", "science_packs",
  "relationships", "owners", "graph", "effect_targets", "providers"
}

local function top_material(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    base_snapshot_fingerprint = record.base_snapshot_fingerprint,
    domain_fingerprints = record.domain_fingerprints,
    relationship_fingerprint = record.relationship_fingerprint,
    owner_index_fingerprint = record.owner_index_fingerprint,
    graph_input_fingerprint = record.graph_input_fingerprint,
    effect_target_inventory_fingerprint = record.effect_target_inventory_fingerprint,
    provider_input_fingerprint = record.provider_input_fingerprint,
    stream_input_fingerprint = record.stream_input_fingerprint,
    base_continuation_input_fingerprint = record.base_continuation_input_fingerprint,
    source_fingerprints = record.source_fingerprints,
    structural_sharing = record.structural_sharing
  }
end

local function sorted_copy(values)
  local out = {}
  for _, value in ipairs(values or {}) do table.insert(out, value) end
  table.sort(out)
  return out
end

local function gate_identity_map(gates)
  local out = {}
  for name, gate in pairs(gates or {}) do
    out[name] = {
      status = gate.status,
      passed = gate.passed,
      evaluator = gate.evaluator,
      evidence_fingerprint = gate.evidence_fingerprint
    }
  end
  return out
end

local function stream_input_material(inputs)
  local plan = (inputs or {}).plan or inputs or {}
  if type(plan.plan_fingerprint) == "string" then
    return {schema = plan.schema, plan_fingerprint = plan.plan_fingerprint}
  end
  return inputs or {}
end

local function base_input_material(inputs)
  local operations = (inputs or {}).operations or inputs or {}
  local out = {}
  for _, operation in ipairs(operations) do
    local design = operation.technology_design or {}
    table.insert(out, {
      key = operation.key,
      manifest_id = operation.manifest_id,
      technology_name = operation.technology_name,
      candidate_id = design.candidate_id,
      design_fingerprint = design.design_fingerprint,
      prototype_fingerprint = design.prototype_fingerprint,
      qualification_fingerprint = design.qualification_fingerprint,
      gates = gate_identity_map(operation.gates or design.gates)
    })
  end
  return out
end

function M.validate(record, options)
  options = options or {}
  if type(record) ~= "table" or record.schema ~= SCHEMA
    or record.record_type ~= "CompilationSnapshot"
    or type(record.fact_domains) ~= "table"
    or type(record.domain_fingerprints) ~= "table" then
    error("CompilationSnapshot schema 2 normalized fact record is required.", 2)
  end
  for _, domain in ipairs(REQUIRED_DOMAINS) do
    if type(record.fact_domains[domain]) ~= "table"
      or type(record.domain_fingerprints[domain]) ~= "string" then
      error("CompilationSnapshot normalized fact domain is required: " .. domain, 2)
    end
    if options.deep and record.domain_fingerprints[domain] ~= fingerprint.of(record.fact_domains[domain]) then
      error("CompilationSnapshot fact-domain fingerprint differs: " .. domain, 2)
    end
  end
  for _, field in ipairs({
    "relationship_indexes", "owner_index", "graph_input", "effect_target_inventory",
    "provider_inputs", "stream_inputs", "base_continuation_inputs", "source_fingerprints",
    "structural_sharing", "metrics"
  }) do
    if type(record[field]) ~= "table" then
      error("CompilationSnapshot table field is required: " .. field, 2)
    end
  end
  if options.deep then
    if record.relationship_fingerprint ~= fingerprint.of(record.relationship_indexes)
      or record.owner_index_fingerprint ~= fingerprint.of(record.owner_index)
      or record.graph_input_fingerprint ~= fingerprint.of(record.graph_input)
      or record.effect_target_inventory_fingerprint ~= fingerprint.of(record.effect_target_inventory)
      or record.provider_input_fingerprint ~= fingerprint.of(record.provider_inputs)
      or record.stream_input_fingerprint ~= fingerprint.of(stream_input_material(record.stream_inputs))
      or record.base_continuation_input_fingerprint ~= fingerprint.of(base_input_material(record.base_continuation_inputs)) then
      error("CompilationSnapshot deep domain fingerprint is invalid.", 2)
    end
  end
  if record.snapshot_fingerprint ~= fingerprint.of(top_material(record)) then
    error("CompilationSnapshot Merkle fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  values = values or {}
  local domains = values.fact_domains or values.prototype_surfaces or {}
  local record = {
    schema = SCHEMA,
    record_type = "CompilationSnapshot",
    base_snapshot_fingerprint = values.base_snapshot_fingerprint,
    fact_domains = domains,
    domain_fingerprints = values.domain_fingerprints or {},
    relationship_indexes = values.relationship_indexes or {},
    owner_index = values.owner_index or {},
    graph_input = values.graph_input or {},
    effect_target_inventory = values.effect_target_inventory or {},
    provider_inputs = values.provider_inputs or {},
    stream_inputs = values.stream_inputs or {},
    base_continuation_inputs = values.base_continuation_inputs or {},
    source_fingerprints = values.source_fingerprints or {},
    structural_sharing = values.structural_sharing or {reused_domains = {}, copied_domains = REQUIRED_DOMAINS},
    metrics = values.metrics or {}
  }
  local captured_bytes, canonicalization_passes = 0, 0
  for _, domain in ipairs(REQUIRED_DOMAINS) do
    record.fact_domains[domain] = record.fact_domains[domain] or {}
    if not record.domain_fingerprints[domain] then
      local canonical = fingerprint.canonical(record.fact_domains[domain])
      captured_bytes = captured_bytes + #canonical
      canonicalization_passes = canonicalization_passes + 1
      record.domain_fingerprints[domain] = fingerprint.of(record.fact_domains[domain])
      canonicalization_passes = canonicalization_passes + 1
    end
  end
  record.relationship_fingerprint = values.relationship_fingerprint or fingerprint.of(record.relationship_indexes)
  record.owner_index_fingerprint = values.owner_index_fingerprint or fingerprint.of(record.owner_index)
  record.graph_input_fingerprint = values.graph_input_fingerprint or fingerprint.of(record.graph_input)
  record.effect_target_inventory_fingerprint = values.effect_target_inventory_fingerprint
    or fingerprint.of(record.effect_target_inventory)
  record.provider_input_fingerprint = values.provider_input_fingerprint or fingerprint.of(record.provider_inputs)
  record.stream_input_fingerprint = values.stream_input_fingerprint
    or fingerprint.of(stream_input_material(record.stream_inputs))
  record.base_continuation_input_fingerprint = values.base_continuation_input_fingerprint
    or fingerprint.of(base_input_material(record.base_continuation_inputs))
  canonicalization_passes = canonicalization_passes + 2
    + (values.relationship_fingerprint and 0 or 1)
    + (values.owner_index_fingerprint and 0 or 1)
    + (values.graph_input_fingerprint and 0 or 1)
    + (values.effect_target_inventory_fingerprint and 0 or 1)
    + (values.provider_input_fingerprint and 0 or 1)
  record.structural_sharing.reused_domains = sorted_copy(record.structural_sharing.reused_domains)
  record.structural_sharing.copied_domains = sorted_copy(record.structural_sharing.copied_domains)
  record.metrics.prototype_bytes_captured = record.metrics.prototype_bytes_captured or captured_bytes
  record.metrics.canonicalization_passes = record.metrics.canonicalization_passes or canonicalization_passes
  record.metrics.deep_copy_count = record.metrics.deep_copy_count or 0
  record.metrics.reused_domain_count = #record.structural_sharing.reused_domains
  record.metrics.copied_domain_count = #record.structural_sharing.copied_domains
  record.snapshot_fingerprint = fingerprint.of(top_material(record))
  M.validate(record)
  return record
end

function M.qualify(base, values)
  M.validate(base)
  values = values or {}
  return M.new({
    base_snapshot_fingerprint = base.snapshot_fingerprint,
    fact_domains = base.fact_domains,
    domain_fingerprints = base.domain_fingerprints,
    relationship_indexes = base.relationship_indexes,
    relationship_fingerprint = base.relationship_fingerprint,
    owner_index = base.owner_index,
    owner_index_fingerprint = base.owner_index_fingerprint,
    graph_input = base.graph_input,
    graph_input_fingerprint = base.graph_input_fingerprint,
    effect_target_inventory = base.effect_target_inventory,
    effect_target_inventory_fingerprint = base.effect_target_inventory_fingerprint,
    provider_inputs = base.provider_inputs,
    provider_input_fingerprint = base.provider_input_fingerprint,
    stream_inputs = values.stream_inputs or base.stream_inputs,
    base_continuation_inputs = values.base_continuation_inputs or base.base_continuation_inputs,
    source_fingerprints = values.source_fingerprints or base.source_fingerprints,
    structural_sharing = {
      reused_domains = REUSED_QUALIFICATION_DOMAINS,
      copied_domains = {"stream_inputs", "base_continuation_inputs"}
    },
    metrics = {
      prototype_bytes_captured = 0,
      deep_copy_count = 0,
      qualification_delta = true
    }
  })
end

function M.snapshot(record, options)
  M.validate(record)
  if not (options and options.full) then
    return deepcopy({
      schema = record.schema,
      record_type = record.record_type,
      base_snapshot_fingerprint = record.base_snapshot_fingerprint,
      domain_fingerprints = record.domain_fingerprints,
      relationship_fingerprint = record.relationship_fingerprint,
      owner_index_fingerprint = record.owner_index_fingerprint,
      graph_input_fingerprint = record.graph_input_fingerprint,
      effect_target_inventory_fingerprint = record.effect_target_inventory_fingerprint,
      provider_input_fingerprint = record.provider_input_fingerprint,
      stream_input_fingerprint = record.stream_input_fingerprint,
      base_continuation_input_fingerprint = record.base_continuation_input_fingerprint,
      source_fingerprints = record.source_fingerprints,
      structural_sharing = record.structural_sharing,
      metrics = record.metrics,
      snapshot_fingerprint = record.snapshot_fingerprint
    })
  end
  M.validate(record, {deep = true})
  return deepcopy(record)
end

function M.schema_authority()
  return {schema = SCHEMA, fact_domains = deepcopy(REQUIRED_DOMAINS)}
end

return M
