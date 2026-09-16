local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")

local M = {}
local SCHEMA = 1
local WITNESS_LIMIT = 32

local function material(record)
  local out = deepcopy(record)
  out.metrics_fingerprint = nil
  return out
end

local function count(rows, predicate)
  local value = 0
  for _, row in ipairs(rows or {}) do if predicate(row) then value = value + 1 end end
  return value
end

local function metric(value, source, status, witnesses)
  return {
    value = value,
    source = source,
    measurement_status = status,
    witnesses = deepcopy(witnesses or {})
  }
end

function M.build(rule, rows, budget, options)
  options = options or {}
  local partitions, depths, unlock_witnesses = {}, {}, {}
  for _, row in ipairs(rows or {}) do
    if row.partition_key then partitions[row.partition_key] = true end
    for _, unlocker in ipairs(recipe_unlocks.for_recipe(row.recipe)) do
      local depth = options.researchability_index and options.researchability_index.unlock_depths[unlocker]
      if type(depth) == "number" then
        depths[depth] = true
        if #unlock_witnesses < WITNESS_LIMIT then
          table.insert(unlock_witnesses, row.recipe .. "@" .. unlocker .. "=" .. tostring(depth))
        end
      end
    end
  end
  local partition_count, earliest, latest = 0, nil, nil
  local semantic_partitions = {}
  for partition in pairs(partitions) do
    partition_count = partition_count + 1
    table.insert(semantic_partitions, partition)
  end
  table.sort(semantic_partitions)
  for depth in pairs(depths) do
    earliest = earliest and math.min(earliest, depth) or depth
    latest = latest and math.max(latest, depth) or depth
  end
  local accepted = count(rows, function(row) return row.final_state == "attach" end)
  local review = count(rows, function(row) return row.final_state == "review-required" end)
  local hard = count(rows, function(row) return row.risk_disposition == "HARD_REJECTED" end)
  local provider_phase_time = tonumber(options.phase_seconds)
  local canonical_bytes = #fingerprint.canonical(rows or {})
  local witness_count = #unlock_witnesses + #(options.witnesses or {})
  local metrics = {
    member_count = metric(accepted, "provider-decision-set", "COMPLETE"),
    candidate_count = metric(#(rows or {}), "provider-decision-set", "COMPLETE"),
    accepted_count = metric(accepted, "provider-decision-set", "COMPLETE"),
    review_required_count = metric(review, "provider-decision-set", "COMPLETE"),
    hard_reject_count = metric(hard, "canonical-recipe-risk", "COMPLETE"),
    semantic_cluster_count = metric(partition_count, "family-operator-partitioner", "COMPLETE"),
    earliest_unlock_depth = metric(earliest, "technology-researchability-index-v2",
      earliest and "COMPLETE" or "INCOMPLETE", unlock_witnesses),
    latest_unlock_depth = metric(latest, "technology-researchability-index-v2",
      latest and "COMPLETE" or "INCOMPLETE", unlock_witnesses),
    progression_span = metric(earliest and latest and (latest - earliest) or nil,
      "technology-researchability-index-v2", earliest and latest and "COMPLETE" or "INCOMPLETE"),
    science_tier_span = metric(nil, "generation-plan-science", "INCOMPLETE"),
    accepting_lab_count = metric(nil, "lab-input-index", "INCOMPLETE"),
    owner_conflict_count = metric(count(rows, function(row)
      return row.blocker == "existing_recipe_productivity_owner" or row.blocker == "ambiguous_family_attachment"
    end), "provider-owner-arbitration", "COMPLETE"),
    cross_version_add_count = metric(options.baseline and options.baseline.add_count or nil,
      "provider-baseline", options.baseline and "COMPLETE" or "INCOMPLETE"),
    cross_version_remove_count = metric(options.baseline and options.baseline.remove_count or nil,
      "provider-baseline", options.baseline and "COMPLETE" or "INCOMPLETE"),
    provider_phase_time = metric(provider_phase_time, "compiler-telemetry-clock",
      provider_phase_time and "COMPLETE" or "INCOMPLETE"),
    canonical_bytes = metric(canonical_bytes, "canonical-provider-decisions", "COMPLETE"),
    provider_canonical_bytes = metric(canonical_bytes, "canonical-provider-decisions", "COMPLETE"),
    provider_witness_count = metric(witness_count, "provider-metric-witnesses", "COMPLETE")
  }
  local incomplete = {}
  for name, row in pairs(metrics) do
    if row.measurement_status ~= "COMPLETE" then table.insert(incomplete, name) end
  end
  table.sort(incomplete)
  local record = {
    schema = SCHEMA,
    record_type = "ProviderMetrics",
    provider_id = rule.provider_id,
    provider_version = "compiler-provider-schema-1/family-rule-schema-" .. tostring(rule.schema),
    provider_source_fingerprint = fingerprint.of(rule),
    family_id = rule.id,
    partition_key = #semantic_partitions == 1 and semantic_partitions[1]
      or "partition-set:" .. fingerprint.of(semantic_partitions),
    semantic_partitions = semantic_partitions,
    environment_identity = deepcopy(options.environment_identity),
    environment_fingerprint = options.environment_fingerprint,
    measurement_status = #incomplete == 0 and "COMPLETE" or "INCOMPLETE",
    incomplete_metrics = incomplete,
    metrics = metrics,
    budget_fingerprint = budget.cardinality_fingerprint,
    witnesses = deepcopy(options.witnesses or {})
  }
  record.metrics_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "ProviderMetrics" then
    error("ProviderMetrics schema 1 record is required.", 2)
  end
  for _, field in ipairs({
    "provider_id", "provider_version", "provider_source_fingerprint", "family_id",
    "partition_key", "environment_fingerprint", "measurement_status", "budget_fingerprint"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("ProviderMetrics field is required: " .. field, 2)
    end
  end
  if type(record.environment_identity) ~= "table"
    or record.environment_identity.environment_fingerprint ~= record.environment_fingerprint
    or type(record.semantic_partitions) ~= "table" or type(record.metrics) ~= "table"
    or type(record.incomplete_metrics) ~= "table" or type(record.witnesses) ~= "table" then
    error("ProviderMetrics exact environment, partition, metric, and witness material is required.", 2)
  end
  if record.measurement_status ~= "COMPLETE" and record.measurement_status ~= "INCOMPLETE" then
    error("ProviderMetrics measurement status is invalid.", 2)
  end
  for name, row in pairs(record.metrics) do
    if type(row) ~= "table" or (row.measurement_status ~= "COMPLETE" and row.measurement_status ~= "INCOMPLETE")
      or type(row.source) ~= "string" or row.source == "" or type(row.witnesses) ~= "table"
      or (row.measurement_status == "COMPLETE" and type(row.value) ~= "number") then
      error("ProviderMetrics metric is invalid: " .. tostring(name), 2)
    end
  end
  if record.metrics_fingerprint ~= fingerprint.of(material(record)) then
    error("ProviderMetrics fingerprint is invalid.", 2)
  end
  return true
end

return M
