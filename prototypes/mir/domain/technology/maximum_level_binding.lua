local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local SCHEMA = 3
local KIND = "MIRMaximumLevelPolicyV3"
local KNOWN_FINALIZER_ADAPTER = "factorio-data-final-fixes-v1"
local PRECEDENCE = {
  ["exact-technology"] = 1,
  ["exact-native-owner"] = 2,
  ["exact-stream"] = 3,
  family = 4,
  ["ecosystem-profile"] = 5,
  global = 6
}

local function effective_cap(value)
  if value == "infinite" then return "infinite" end
  local number = tonumber(value)
  if not number or number <= 0 then return "infinite" end
  return math.floor(number)
end

local function finite_cap(value)
  local cap = effective_cap(value)
  return type(cap) == "number" and cap or nil
end

local function stable_fingerprint(record, field)
  local material = deepcopy(record)
  material[field] = nil
  return fingerprint.of(material)
end

local function strategies(cap, runtime_supported)
  local finite = finite_cap(cap)
  if finite and runtime_supported then
    return {
      prototype = {mode = "lossless-infinite-prototype", max_level = "infinite"},
      runtime = {
        mode = "absolute-cap-controller",
        queue = "remove-only-levels-above-effective-cap",
        completion = "retain-completed-levels-and-bonuses",
        restoration = "restore-only-mir-disabled-technologies"
      },
      presentation = {
        mode = "finite-runtime-cap",
        show_levels_info = false,
        visible_when_disabled = true,
        completed_state = "visible-and-completed",
        description = "exact-effective-cap"
      }
    }
  end
  if finite then
    return {
      prototype = {mode = "native-finite-prototype", max_level = finite},
      runtime = {mode = "prototype-cap", queue = "engine-owned"},
      presentation = {mode = "native-prototype-maximum", show_levels_info = true}
    }
  end
  return {
    prototype = {mode = "lossless-infinite-prototype", max_level = "infinite"},
    runtime = {mode = "unbounded", queue = "unchanged"},
    presentation = {mode = "native-infinite", show_levels_info = true}
  }
end

local function new_binding(input, options)
  local cap = effective_cap(input.requested_cap)
  local strategy = strategies(cap, options.scripted_techs_supported == true)
  local scope = input.scope
  local binding = {
    schema = SCHEMA,
    record_type = "MaximumLevelBinding",
    technology_id = tostring(input.technology_id),
    semantic = {
      stream_id = input.stream_id,
      family_id = input.family_id
    },
    binding = {
      source = input.source,
      scope = scope,
      precedence_rank = PRECEDENCE[scope],
      operation = input.operation,
      resolution = "selected"
    },
    setting = {
      name = input.setting_name,
      profile = input.setting_profile or "effective-startup-settings"
    },
    cap = {
      semantics = "absolute-highest-technology-level",
      requested = input.requested_cap,
      effective = cap
    },
    prototype_strategy = strategy.prototype,
    runtime_strategy = strategy.runtime,
    presentation_strategy = strategy.presentation,
    target_requirements = {
      target_profile = options.target_profile or "unknown",
      scripted_techs = finite_cap(cap) ~= nil,
      scripted_techs_supported = options.scripted_techs_supported == true,
      mod_data_transport_supported = options.mod_data_supported == true,
      finalizer_adapter = KNOWN_FINALIZER_ADAPTER
    },
    finalizer_observation = {
      adapter = KNOWN_FINALIZER_ADAPTER,
      status = "pending",
      observed_prototype_max_level = "unobserved"
    },
    migration_behavior = {
      retain_current_progress = true,
      retain_completed_levels = true,
      retain_completed_bonus = true,
      lowering = "remove-invalid-current-and-queued-levels-without-reversing-completion",
      raising = "preserve-progress-and-restore-future-levels",
      removal = "restore-unbounded-research",
      restoration = "restore-only-mir-disabled-technologies"
    },
    diagnostics = {
      status = "planned",
      conflict_code = "maximum_level_late_prototype_mutation",
      unknown_finalizer_code = "maximum_level_unknown_finalizer_adapter"
    },
    provenance = {
      plan_fingerprint = options.plan_fingerprint,
      manifest_id = input.manifest_id,
      proof = input.proof or "compiler-plan-binding"
    },

    -- Stable compatibility projection consumed by older runtime adapters.
    -- Keep the normalized setting record above intact; legacy consumers use
    -- setting_name as the scalar compatibility field.
    technology = tostring(input.technology_id),
    setting_name = input.setting_name,
    selected = cap,
    source = input.source,
    operation = input.operation,
    presentation = strategy.presentation
  }
  binding.binding_fingerprint = stable_fingerprint(binding, "binding_fingerprint")
  return binding
end

local function candidate_rows(plan, options)
  local rows = {}
  for _, row in ipairs((plan.stream_plan and plan.stream_plan.rows) or {}) do
    if row.action == "emit" then
      table.insert(rows, new_binding({
        technology_id = row.technology_name,
        stream_id = row.manifest_id or row.stream_key,
        family_id = row.family_id or row.stream_key,
        manifest_id = row.manifest_id,
        setting_name = "ips-max-level-" .. tostring(row.stream_key),
        requested_cap = row.planned_max_level,
        source = "generated-stream",
        scope = "exact-stream",
        operation = "emit"
      }, options))
    elseif row.action == "adopt" and row.adoption then
      table.insert(rows, new_binding({
        technology_id = row.adoption.owner,
        stream_id = row.manifest_id or row.stream_key,
        family_id = row.family_id or row.stream_key,
        manifest_id = row.manifest_id,
        setting_name = "ips-max-level-" .. tostring(row.stream_key),
        requested_cap = row.adoption.planned_max_level,
        source = "native-owner",
        scope = "exact-native-owner",
        operation = row.adoption.operation
      }, options))
    end
  end
  for _, operation in ipairs(plan.base_extension_operations or {}) do
    table.insert(rows, new_binding({
      technology_id = operation.technology_name,
      stream_id = operation.manifest_id or ("base-extension:" .. tostring(operation.key)),
      family_id = operation.family_id or operation.key,
      manifest_id = operation.manifest_id,
      setting_name = "mir-max-level-" .. tostring(operation.key),
      requested_cap = operation.planned_max_level,
      source = "base-continuation",
      scope = "exact-technology",
      operation = operation.operation
    }, options))
  end
  table.sort(rows, function(left, right)
    if left.technology_id ~= right.technology_id then
      return left.technology_id < right.technology_id
    end
    if left.binding.precedence_rank ~= right.binding.precedence_rank then
      return left.binding.precedence_rank < right.binding.precedence_rank
    end
    return tostring(left.setting.name) < tostring(right.setting.name)
  end)
  return rows
end

local function resolve_candidates(rows)
  local resolved, by_technology = {}, {}
  for _, candidate in ipairs(rows) do
    local current = by_technology[candidate.technology_id]
    if not current then
      by_technology[candidate.technology_id] = candidate
      table.insert(resolved, candidate)
    elseif current.binding.precedence_rank == candidate.binding.precedence_rank
        and (current.setting.name ~= candidate.setting.name
          or current.cap.effective ~= candidate.cap.effective) then
      current.binding.resolution = "blocking-equal-precedence-conflict"
      current.diagnostics.status = "blocking-conflict"
      current.diagnostics.active_code = "maximum_level_equal_precedence_conflict"
      current.diagnostics.conflicting_setting = candidate.setting.name
      current.binding_fingerprint = stable_fingerprint(current, "binding_fingerprint")
    else
      current.provenance.shadowed = current.provenance.shadowed or {}
      table.insert(current.provenance.shadowed, {
        source = candidate.binding.source,
        scope = candidate.binding.scope,
        setting = candidate.setting.name,
        effective_cap = candidate.cap.effective
      })
      current.binding_fingerprint = stable_fingerprint(current, "binding_fingerprint")
    end
  end
  return resolved
end

function M.from_plan(plan, options)
  if type(plan) ~= "table" then error("MaximumLevelBinding requires a compiler plan.", 2) end
  options = options or {}
  options.plan_fingerprint = options.plan_fingerprint or plan.fingerprint
  local artifact = {
    schema = SCHEMA,
    kind = KIND,
    semantics = "absolute-highest-technology-level",
    precedence_order = {
      "exact-technology", "exact-native-owner", "exact-stream",
      "family", "ecosystem-profile", "global"
    },
    finalizer_adapter = KNOWN_FINALIZER_ADAPTER,
    finalizer_status = "pending",
    bindings = resolve_candidates(candidate_rows(plan, options))
  }
  artifact.artifact_fingerprint = stable_fingerprint(artifact, "artifact_fingerprint")
  return artifact
end

local function observed_matches(binding, observed)
  local expected = binding.prototype_strategy.max_level
  if expected == "infinite" then return observed == "infinite" end
  return tonumber(observed) == tonumber(expected)
end

function M.observe_finalizers(artifact, observations)
  if type(artifact) ~= "table" or artifact.schema ~= SCHEMA or artifact.kind ~= KIND then
    error("MaximumLevelBinding finalizer observation requires policy schema 3.", 2)
  end
  observations = observations or {}
  local out = deepcopy(artifact)
  local blocked = false
  for _, binding in ipairs(out.bindings or {}) do
    local observation = observations[binding.technology_id]
    local adapter = observation and observation.adapter or "unobserved"
    local observed = observation and observation.observed_prototype_max_level or "missing"
    local accepted = observation ~= nil
      and adapter == KNOWN_FINALIZER_ADAPTER
      and observed_matches(binding, observed)
      and binding.diagnostics.status ~= "blocking-conflict"
    binding.finalizer_observation = {
      adapter = adapter,
      status = accepted and "accepted" or "blocking-conflict",
      observed_prototype_max_level = observed
    }
    if accepted then
      binding.diagnostics.status = "accepted"
      binding.diagnostics.active_code = nil
    else
      blocked = true
      binding.diagnostics.status = "blocking-conflict"
      if adapter ~= KNOWN_FINALIZER_ADAPTER then
        binding.diagnostics.active_code = binding.diagnostics.unknown_finalizer_code
      elseif observation == nil or observed == "missing" then
        binding.diagnostics.active_code = "maximum_level_finalizer_observation_missing"
      elseif not observed_matches(binding, observed) then
        binding.diagnostics.active_code = binding.diagnostics.conflict_code
      end
    end
    binding.binding_fingerprint = stable_fingerprint(binding, "binding_fingerprint")
  end
  out.finalizer_status = blocked and "blocking-conflict" or "accepted"
  out.artifact_fingerprint = stable_fingerprint(out, "artifact_fingerprint")
  return out
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    kind = KIND,
    semantics = "absolute-highest-technology-level",
    precedence = deepcopy(PRECEDENCE),
    finalizer_adapter = KNOWN_FINALIZER_ADAPTER
  }
end

return M
