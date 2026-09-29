local M = {}
M.requires_features = {"scripted_techs"}

local runtime_state = require("prototypes.mir.runtime.state")
local startup_settings = require("prototypes.mir.runtime.startup_settings")
local stream_registry = require("prototypes.mir.streams.registry")
local setting_defaults = require("prototypes.mir.settings.defaults")
local fingerprint = require("prototypes.mir.core.fingerprint")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local POLICY_DATA_NAME = "more-infinite-research-maximum-level-policy"
local POLICY_VERSION = 3
local INFINITE_RUNTIME_MAX_LEVEL = 4294967295
local MAXIMUM_LEVEL_FINALIZER_ADAPTER = "factorio-data-final-fixes-v1"

-- Policy transport, startup settings, and final technology prototypes are
-- immutable for one control lifetime.  Keep their fully validated *plain*
-- result outside persistent state so a dense normal research-event stream
-- does not repeatedly fingerprint the whole transport (or, on F200, walk
-- every prototype for each continuation).  Force state, queues, enablement,
-- and visibility remain deliberately live and are never cached here.
--
-- Factorio recreates non-persistent module state across a load, so a nil
-- cache is rebuilt lazily by the first lifecycle/event normalization.  A
-- configuration change can replace the package settings/prototypes and must
-- invalidate before it performs its all-force normalization.
local validated_policy_cache = nil

local function ensure_state()
  return runtime_state.bucket("maximum_level_control")
end

local function observed_max_level(name)
  local prototype = prototypes and prototypes.technology and prototypes.technology[name]
  return prototype and prototype.max_level or nil
end

local function prototype_is_infinite(value)
  return value == "infinite"
    or (type(value) == "number" and value >= INFINITE_RUNTIME_MAX_LEVEL)
end

local function finite_number(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function finite_positive_integer(value)
  return finite_number(value) and value > 0 and value == math.floor(value)
end

local function finite_cap(value)
  return finite_positive_integer(value) and value or nil
end

local function bounded_string(value)
  return type(value) == "string" and value ~= "" and #value <= 1024
end

local function dense_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for index in pairs(value) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
      return false
    end
    count = count + 1
  end
  return #value == count
end

local function fingerprint_matches(record, field)
  if type(record) ~= "table" or not bounded_string(record[field]) then return false end
  local material = {}
  for key, value in pairs(record) do material[key] = value end
  material[field] = nil
  local ok, actual = pcall(fingerprint.of, material)
  return ok and actual == record[field]
end

local function selected_maximum(setting_name)
  local selected = tonumber(startup_settings.get(setting_name))
  if finite_number(selected) and selected == 0 then return "infinite" end
  if finite_positive_integer(selected) then return selected end
  return nil
end

local function add_runtime_binding(managed, runtime_settings_bindings, technology_name,
    declared_key, setting_name, source, operation)
  if not (prototypes and prototypes.technology and prototypes.technology[technology_name]) then return end
  local selected = selected_maximum(setting_name)
  managed[technology_name] = {
    source = source,
    operation = operation,
    setting = setting_name,
    selected = selected,
    policy_transport = "settings-derived-v3",
    ownership_kind = "settings-derived-v3",
    blocked_reason = selected == nil
      and "maximum_level_runtime_setting_invalid" or nil,
    legacy = false
  }
  -- The bridge's source key is presentation-only. Keep it in the controller's
  -- non-persistent policy cache, never in managed_technologies save state.
  runtime_settings_bindings[technology_name] = {
    source = source,
    policy_transport = "settings-derived-v3",
    declared_key = declared_key,
    setting = setting_name
  }
end

local function add_generated_runtime_bindings(managed, runtime_settings_bindings)
  for key, spec in pairs(stream_registry.snapshot()) do
    local technology_name = spec.technology_name or ("recipe-prod-" .. tostring(key) .. "-1")
    add_runtime_binding(
      managed,
      runtime_settings_bindings,
      technology_name,
      key,
      "ips-max-level-" .. tostring(key),
      "generated-stream",
      "runtime-settings-transport")
  end
end

local function add_base_continuation_runtime_bindings(managed, runtime_settings_bindings)
  for key, spec in pairs(setting_defaults.base_extensions or {}) do
    local chain_key = spec.chain_key or key
    local generated_key = spec.generated_key or chain_key
    local pattern = "^" .. tostring(generated_key):gsub("([^%w])", "%%%1") .. "%-([0-9]+)$"
    local selected_name, selected_level = nil, nil
    for name, prototype in pairs((prototypes and prototypes.technology) or {}) do
      local level = tonumber(string.match(name, pattern))
      if level and prototype.max_level ~= nil
          and (selected_level == nil or level < selected_level) then
        selected_name, selected_level = name, level
      end
    end
    if selected_name then
      add_runtime_binding(
        managed,
        runtime_settings_bindings,
        selected_name,
        key,
        "mir-max-level-" .. tostring(key),
        "base-continuation",
        "runtime-settings-transport")
    end
  end
end

local function add_runtime_settings_policy(managed, runtime_settings_bindings)
  add_generated_runtime_bindings(managed, runtime_settings_bindings)
  add_base_continuation_runtime_bindings(managed, runtime_settings_bindings)
end

local function v3_binding_admission_error(binding)
  if type(binding) ~= "table" or binding.schema ~= 3
      or binding.record_type ~= "MaximumLevelBinding"
      or not bounded_string(binding.technology_id) then
    return "maximum_level_binding_shape_invalid"
  end
  local diagnostics = binding.diagnostics or {}
  local finalizer = binding.finalizer_observation or {}
  local prototype_strategy = binding.prototype_strategy or {}
  local strategy = binding.runtime_strategy or {}
  local requirements = binding.target_requirements or {}
  local cap = type(binding.cap) == "table" and binding.cap.effective or nil
  local finite = finite_positive_integer(cap)
  local unbounded = cap == "infinite"
  if not bounded_string(binding.binding_fingerprint) then
    return "maximum_level_binding_fingerprint_missing"
  elseif not fingerprint_matches(binding, "binding_fingerprint") then
    return "maximum_level_binding_fingerprint_invalid"
  elseif type(binding.setting) ~= "table" or not bounded_string(binding.setting.name)
      or (not finite and not unbounded) then
    return "maximum_level_binding_policy_fields_invalid"
  elseif type(binding.diagnostics) ~= "table" then
    return "maximum_level_binding_diagnostics_invalid"
  elseif diagnostics.status ~= "accepted" then
    return diagnostics.active_code or "maximum_level_binding_conflict"
  elseif type(binding.prototype_strategy) ~= "table"
      or type(binding.runtime_strategy) ~= "table"
      or type(binding.target_requirements) ~= "table"
      or type(binding.finalizer_observation) ~= "table" then
    return "maximum_level_binding_strategy_shape_invalid"
  elseif prototype_strategy.mode ~= "lossless-infinite-prototype"
      or prototype_strategy.max_level ~= "infinite" then
    return "maximum_level_prototype_strategy_mismatch"
  elseif (finite and strategy.mode ~= "absolute-cap-controller")
      or (unbounded and strategy.mode ~= "unbounded") then
    return "maximum_level_runtime_strategy_mismatch"
  elseif requirements.scripted_techs ~= finite
      or requirements.scripted_techs_supported ~= true
      or requirements.mod_data_transport_supported ~= true
      or requirements.finalizer_adapter ~= MAXIMUM_LEVEL_FINALIZER_ADAPTER then
    return "maximum_level_target_requirements_mismatch"
  elseif finalizer.status ~= "accepted"
      or finalizer.adapter ~= MAXIMUM_LEVEL_FINALIZER_ADAPTER
      or finalizer.observed_prototype_max_level ~= "infinite" then
    return "maximum_level_finalizer_observation_invalid"
  end
  return nil
end

local function normalized_v3_binding(binding, policy_blocked_reason)
  if type(binding) ~= "table" or not bounded_string(binding.technology_id) then
    return nil, "maximum_level_binding_identity_invalid"
  end
  local binding_error = v3_binding_admission_error(binding)
  local binding_detail = type(binding.binding) == "table" and binding.binding or {}
  local setting = type(binding.setting) == "table" and binding.setting or {}
  local cap = type(binding.cap) == "table" and binding.cap or {}
  local blocked_reason
  if policy_blocked_reason then blocked_reason = policy_blocked_reason
  elseif binding_error then blocked_reason = binding_error end
  return {
    technology = tostring(binding.technology_id),
    source = binding_detail.source or binding.source,
    operation = binding_detail.operation or binding.operation,
    setting = setting.name or binding.setting_name,
    selected = cap.effective or binding.selected,
    blocked_reason = blocked_reason,
    binding_fingerprint = binding.binding_fingerprint,
    policy_transport = "transported-v3",
    ownership_kind = "transported-v3",
    legacy = false
  }, binding_error
end

local function normalized_v2_binding(binding)
  if type(binding) ~= "table" then return nil end
  -- A transported V2 artifact carries insufficient finalizer and ownership
  -- provenance for player mutation. It is retained only to identify an old
  -- installation while an accepted V3 artifact migrates persisted state.
  return {
    technology = tostring(binding.technology),
    source = binding.source,
    operation = binding.operation,
    setting = binding.setting,
    selected = binding.selected,
    blocked_reason = "maximum_level_legacy_transport_read_only",
    policy_transport = "legacy-v2-read-only",
    ownership_kind = "legacy-v2-read-only",
    legacy = true
  }
end

local function transported_policy()
  local policy_prototype = prototypes and prototypes.mod_data
    and prototypes.mod_data[POLICY_DATA_NAME]
  local artifact = policy_prototype and policy_prototype.data or nil
  if type(artifact) ~= "table" then
    -- F200 has no mod-data prototype surface, so its V3 controller derives a
    -- structured policy from settings. A modern target that does expose
    -- mod-data must not silently downgrade a missing policy into that path.
    if target_line.mod_data_supported() then return {}, true, {} end
    return nil, false, {}
  end

  local managed = {}
  local runtime_settings_bindings = {}
  if artifact.schema == 3 and artifact.kind == "MIRMaximumLevelPolicyV3" then
    local policy_blocked_reason
    if artifact.finalizer_status ~= "accepted" then
      policy_blocked_reason = "maximum_level_policy_finalizer_conflict"
    elseif artifact.finalizer_adapter ~= MAXIMUM_LEVEL_FINALIZER_ADAPTER then
      policy_blocked_reason = "maximum_level_policy_finalizer_adapter_invalid"
    elseif not bounded_string(artifact.artifact_fingerprint) then
      policy_blocked_reason = "maximum_level_policy_fingerprint_missing"
    elseif not fingerprint_matches(artifact, "artifact_fingerprint") then
      policy_blocked_reason = "maximum_level_policy_fingerprint_invalid"
    elseif not dense_array(artifact.bindings) then
      policy_blocked_reason = "maximum_level_policy_bindings_invalid"
    end
    local transport_blocked = policy_blocked_reason ~= nil
    local bindings = type(artifact.bindings) == "table" and artifact.bindings or {}
    local counts = {}
    for _, binding in ipairs(bindings) do
      if type(binding) == "table" and bounded_string(binding.technology_id) then
        counts[binding.technology_id] = (counts[binding.technology_id] or 0) + 1
      end
    end
    for _, binding in ipairs(bindings) do
      local duplicate_reason = type(binding) == "table"
        and counts[binding.technology_id] ~= nil
        and counts[binding.technology_id] ~= 1
        and "maximum_level_policy_duplicate_binding" or nil
      local normalized, binding_error = normalized_v3_binding(
        binding, policy_blocked_reason or duplicate_reason)
      if normalized and normalized.technology ~= "" then
        managed[normalized.technology] = normalized
        local semantic = type(binding) == "table" and binding.semantic or nil
        local declared_key = type(semantic) == "table" and semantic.stream_id or nil
        -- The raw semantic ID is copied into the non-persistent presentation
        -- cache only after the complete V3 binding and outer transport passed.
        -- A duplicate or blocked artifact cannot nominate browser settings.
        if not policy_blocked_reason and not duplicate_reason and not binding_error
            and bounded_string(declared_key) then
          runtime_settings_bindings[normalized.technology] = {
            source = normalized.source,
            policy_transport = normalized.policy_transport,
            declared_key = declared_key,
            setting = normalized.setting
          }
        end
      end
    end
    return managed, transport_blocked, runtime_settings_bindings
  end

  -- V2 is a read-only migration bridge for already installed packages. New
  -- V3 transport never falls back through this path, particularly if it has
  -- a finalizer conflict.
  if artifact.schema == 2 and artifact.kind == "MIRMaximumLevelPolicyV2" then
    for _, binding in ipairs(artifact.bindings or {}) do
      local normalized = normalized_v2_binding(binding)
      if normalized and normalized.technology ~= "" then
        managed[normalized.technology] = normalized
      end
    end
    return managed, false, runtime_settings_bindings
  end

  -- An unrecognized transported policy is deliberately authoritative enough
  -- to disable settings-derived normalization. It is not safe to guess caps.
  return managed, true, runtime_settings_bindings
end

local function log_policy_refusal(policy, observed)
  local reason = policy.blocked_reason or "late_prototype_mutation"
  log("[more-infinite-research] Maximum-level conflict technology="
    .. tostring(policy.technology)
    .. " selected=" .. tostring(policy.selected)
    .. " final-observed=" .. tostring(observed)
    .. " binding-operation=" .. tostring(policy.operation)
    .. " source=" .. tostring(policy.source)
    .. " reason=" .. tostring(reason)
    .. " setting=" .. tostring(policy.setting)
    .. "; runtime queue normalization was refused.")
end

local function ownership_key(policy)
  if not policy then return nil end
  return table.concat({
    tostring(policy.technology),
    tostring(policy.setting),
    tostring(policy.source),
    tostring(policy.operation)
  }, "\0")
end

local RUNTIME_SETTINGS_BINDING_ENTRY_LIMIT = 30000
local RUNTIME_SETTINGS_BINDING_ALIAS_LIMIT = 60000
local AMBIGUOUS_RUNTIME_SETTINGS_STREAM_ALIAS = {}
local AMBIGUOUS_RUNTIME_SETTINGS_BASE_ALIAS = {}

local function new_runtime_settings_registry_index()
  return {
    streams = {aliases = {}, direct = {}, ambiguous = AMBIGUOUS_RUNTIME_SETTINGS_STREAM_ALIAS},
    bases = {aliases = {}, direct = {}, ambiguous = AMBIGUOUS_RUNTIME_SETTINGS_BASE_ALIAS},
    entry_count = 0,
    alias_count = 0,
    over_limit = false
  }
end

local function add_runtime_settings_alias(index, section, alias, key)
  if index.over_limit or not bounded_string(alias) or not bounded_string(key) then return end
  local prior = section.aliases[alias]
  if prior == nil then
    index.alias_count = index.alias_count + 1
    if index.alias_count > RUNTIME_SETTINGS_BINDING_ALIAS_LIMIT then
      index.over_limit = true
      return
    end
    section.aliases[alias] = key
  elseif prior ~= key then
    section.aliases[alias] = section.ambiguous
  end
end

local function add_runtime_settings_registry_entry(index, section, key, spec, base)
  index.entry_count = index.entry_count + 1
  if index.entry_count > RUNTIME_SETTINGS_BINDING_ENTRY_LIMIT then
    index.over_limit = true
    return
  end
  if not bounded_string(key) then return end
  section.direct[key] = true
  add_runtime_settings_alias(index, section, key, key)
  local manifest = type(spec) == "table" and spec.manifest_id or nil
  if manifest ~= nil then
    add_runtime_settings_alias(index, section, manifest, key)
  elseif base then
    -- This is the compiler's explicit V3 fallback, not a technology-name
    -- derivation. A configured (even malformed) manifest never gets it.
    add_runtime_settings_alias(index, section, "base-extension:" .. key, key)
  end
end

local function runtime_settings_registry_index()
  local index = new_runtime_settings_registry_index()
  local streams = stream_registry.view()
  if type(streams) ~= "table" then
    index.over_limit = true
    return index
  end
  for key, spec in pairs(streams) do
    add_runtime_settings_registry_entry(index, index.streams, key, spec, false)
    if index.over_limit then return index end
  end
  for key, spec in pairs(setting_defaults.base_extensions or {}) do
    add_runtime_settings_registry_entry(index, index.bases, key, spec, true)
    if index.over_limit then return index end
  end
  return index
end

local function resolved_runtime_settings_alias(section, declared_key)
  local resolved = bounded_string(declared_key) and section.aliases[declared_key] or nil
  return resolved ~= section.ambiguous and resolved or nil
end

local function expected_runtime_settings_name(source, key)
  if source == "generated-stream" then return "ips-max-level-" .. key end
  if source == "base-continuation" then return "mir-max-level-" .. key end
  return nil
end

-- Resolve browser-only stream/base keys once per controller cache epoch. The
-- controller continues to own caps and queues from the admitted policy alone;
-- an unknown, ambiguous, or oversized source map merely omits presentation.
local function runtime_settings_registry_keys(runtime_settings_bindings)
  local index = runtime_settings_registry_index()
  local resolved_keys, count = {}, 0
  if index.over_limit or type(runtime_settings_bindings) ~= "table" then return resolved_keys end
  for technology_name, binding in pairs(runtime_settings_bindings) do
    count = count + 1
    if count > RUNTIME_SETTINGS_BINDING_ENTRY_LIMIT then return {} end
    if bounded_string(technology_name) and type(binding) == "table"
        and bounded_string(binding.source) and bounded_string(binding.policy_transport)
        and bounded_string(binding.declared_key) and bounded_string(binding.setting) then
      local source, declared_key = binding.source, binding.declared_key
      local section = source == "generated-stream" and index.streams
        or source == "base-continuation" and index.bases or nil
      local key
      if section and binding.policy_transport == "settings-derived-v3"
          and section.direct[declared_key] then
        key = declared_key
      elseif section and binding.policy_transport == "transported-v3" then
        key = resolved_runtime_settings_alias(section, declared_key)
      end
      if key and binding.setting == expected_runtime_settings_name(source, key) then
        resolved_keys[technology_name] = key
      end
    end
  end
  return resolved_keys
end

local function build_validated_policy()
  local managed, transport_blocked, runtime_settings_bindings = transported_policy()
  if not managed then
    managed = {}
    runtime_settings_bindings = {}
    add_runtime_settings_policy(managed, runtime_settings_bindings)
    transport_blocked = false
  end

  local caps = {}
  for name, policy in pairs(managed) do
    local cap = finite_cap(policy.selected)
    if policy.blocked_reason then
      log_policy_refusal(policy, observed_max_level(name))
    elseif cap then
      local observed = observed_max_level(name)
      if prototype_is_infinite(observed) then
        caps[name] = cap
      else
        policy.blocked_reason = "maximum_level_late_prototype_mutation"
        log_policy_refusal(policy, observed)
      end
    end
  end
  return {
    managed = managed,
    caps = caps,
    transport_blocked = transport_blocked,
    runtime_settings_bindings = runtime_settings_bindings,
    runtime_settings_registry_keys = runtime_settings_registry_keys(runtime_settings_bindings)
  }
end

local function invalidate_validated_policy()
  validated_policy_cache = nil
end

local function current_policy()
  if not validated_policy_cache then
    validated_policy_cache = build_validated_policy()
  end
  return validated_policy_cache.managed,
    validated_policy_cache.caps,
    validated_policy_cache.transport_blocked
end

local function copied_runtime_settings_binding(technology_name, policy, cap,
    runtime_settings_binding, registry_key)
  if type(policy) ~= "table" or policy.legacy
      or not bounded_string(technology_name) or not bounded_string(policy.source)
      or not bounded_string(policy.policy_transport) or not bounded_string(policy.setting)
      or type(runtime_settings_binding) ~= "table" or not bounded_string(registry_key)
      or runtime_settings_binding.source ~= policy.source
      or runtime_settings_binding.policy_transport ~= policy.policy_transport
      or runtime_settings_binding.setting ~= policy.setting
      or not bounded_string(runtime_settings_binding.declared_key) then
    return nil
  end
  if policy.source ~= "generated-stream" and policy.source ~= "base-continuation" then
    return nil
  end

  local selected = policy.selected
  local selected_is_finite = finite_positive_integer(selected)
  local selected_is_infinite = selected == "infinite"
  if not selected_is_finite and not selected_is_infinite then return nil end

  local blocked_reason = bounded_string(policy.blocked_reason) and policy.blocked_reason or nil
  local state
  if blocked_reason then
    state = "disabled"
  elseif selected_is_infinite then
    state = "infinite"
  elseif cap == selected then
    state = "finite"
  else
    -- A finite setting without the exact accepted cap is not browser evidence.
    -- Keep controller behaviour unchanged and omit this presentation-only row.
    return nil
  end

  return {
    schema = 1,
    source = policy.source,
    policy_transport = policy.policy_transport,
    binding = {
      technology_id = technology_name,
      declared_key = registry_key,
      setting_name = policy.setting
    },
    selected_effective = selected,
    state = state,
    blocked_reason = blocked_reason
  }
end

-- Read-only presentation bridge for the research browser. It exposes a fresh,
-- bounded plain copy of the policy that this controller has already admitted;
-- it does not read a Force, persistent state, queue, or compiler artifact and
-- cannot change normalization behaviour. The normal lifecycle invalidation
-- above clears its shared policy source on init/configuration changes.
function M.runtime_settings_bindings()
  local managed, caps = current_policy()
  local policy_cache = validated_policy_cache or {}
  local binding_inputs = policy_cache.runtime_settings_bindings or {}
  local registry_keys = policy_cache.runtime_settings_registry_keys or {}
  local out, count = {}, 0
  for technology_name, policy in pairs(managed) do
    count = count + 1
    if count > 30000 then return {} end
    local binding = copied_runtime_settings_binding(technology_name, policy, caps[technology_name],
      binding_inputs[technology_name], registry_keys[technology_name])
    if binding then out[technology_name] = binding end
  end
  return out
end

local function force_cap_state(force)
  local state = ensure_state()
  state.disabled_by_cap = state.disabled_by_cap or {}
  state.disabled_by_cap[force.index] = state.disabled_by_cap[force.index] or {}
  state.visibility_by_cap = state.visibility_by_cap or {}
  state.visibility_by_cap[force.index] = state.visibility_by_cap[force.index] or {}
  state.unowned_disabled_by_cap = state.unowned_disabled_by_cap or {}
  state.unowned_disabled_by_cap[force.index] = state.unowned_disabled_by_cap[force.index] or {}
  return state.disabled_by_cap[force.index], state.visibility_by_cap[force.index],
    state.unowned_disabled_by_cap[force.index]
end

local function captured_visibility(value, force, policy)
  return {
    policy_version = POLICY_VERSION,
    force_index = force.index,
    ownership_key = ownership_key(policy),
    ownership_kind = policy and policy.ownership_kind or nil,
    value = value
  }
end

local function owns_visibility(record, force, policy)
  if type(record) ~= "table" then return false end
  local expected_kind = policy and policy.ownership_kind or nil
  local kind_matches = record.ownership_kind == expected_kind
    -- Preserve existing exact F210 V3 records written before the ownership
    -- discriminator existed. Settings-derived F200 records never use this
    -- compatibility path, so ambiguous old fallback state remains unowned.
    or (expected_kind == "transported-v3" and record.ownership_kind == nil)
  return record.policy_version == POLICY_VERSION
    and record.force_index == force.index
    and record.ownership_key == ownership_key(policy)
    and kind_matches
end

local function owns_disable(record, force, policy)
  return owns_visibility(record, force, policy)
    and record.enabled_before_cap == true
    and policy and policy.legacy ~= true
end

local function owns_unowned_disable_continuity(record, force, policy)
  return owns_visibility(record, force, policy)
    and record.enabled_before_cap == false
    and record.migrated_from_policy_version == 2
    and policy and policy.legacy ~= true
end

local function migrate_legacy_force_state(disabled_by_cap, visibility_by_cap,
    unowned_disabled_by_cap,
    technology_name, force, policy, cap)
  -- V2 stored only values written by its own cap controller: true for a
  -- disable it performed and the original visibility boolean. Upgrade those
  -- exact shapes once a V3 policy is accepted. A boolean visibility record
  -- paired with no V2 disable record proves that V2 did not own enablement.
  -- That exact pair retains the foreign false state V2 observed even if
  -- Factorio has reset enabled before the V3 configuration callback. Restore
  -- it once here, before V3 cap enforcement can mistake that reset for its
  -- own enabled-to-disabled write. This is continuity, never MIR ownership.
  -- Do not infer either ownership or continuity from any other legacy shape.
  if not policy or policy.blocked_reason
      or policy.policy_transport ~= "transported-v3" then return end
  local migrated_visibility = type(visibility_by_cap[technology_name]) == "boolean"
  local legacy_disable = disabled_by_cap[technology_name]
  local migrated_disable = legacy_disable == true
  local technology = force.technologies[technology_name]
  local migrated_unowned_disable = migrated_visibility and legacy_disable == nil
    and unowned_disabled_by_cap[technology_name] == nil
  if migrated_visibility then
    visibility_by_cap[technology_name] = captured_visibility(
      visibility_by_cap[technology_name], force, policy)
  end
  if migrated_disable then
    disabled_by_cap[technology_name] = {
      policy_version = POLICY_VERSION,
      force_index = force.index,
      cap = cap,
      binding_fingerprint = policy.binding_fingerprint,
      ownership_key = ownership_key(policy),
      ownership_kind = policy.ownership_kind,
      enabled_before_cap = true,
      migrated_from_policy_version = 2
    }
  end
  if migrated_unowned_disable then
    unowned_disabled_by_cap[technology_name] = {
      policy_version = POLICY_VERSION,
      force_index = force.index,
      cap = cap,
      binding_fingerprint = policy.binding_fingerprint,
      ownership_key = ownership_key(policy),
      ownership_kind = policy.ownership_kind,
      enabled_before_cap = false,
      migrated_from_policy_version = 2
    }
    -- Do this only on the exact V2-to-V3 migration. While the cap remains
    -- active, ordinary normalization must not override later foreign writes.
    -- When the cap is relaxed, restore_unowned_disable_continuity applies the
    -- same persisted state once more and clears this record.
    technology.enabled = false
    log("[more-infinite-research] Captured maximum-level V2 unowned-disable"
      .. " continuity force=" .. tostring(force.name)
      .. " technology=" .. tostring(technology_name)
      .. " original-enabled=false policy-version=" .. tostring(POLICY_VERSION) .. ".")
  end
  if migrated_visibility or migrated_disable then
    log("[more-infinite-research] Migrated maximum-level V2 ownership"
      .. " force=" .. tostring(force.name)
      .. " technology=" .. tostring(technology_name)
      .. " enablement-owned=" .. tostring(migrated_disable)
      .. " visibility-owned=" .. tostring(migrated_visibility)
      .. " policy-version=" .. tostring(POLICY_VERSION) .. ".")
  end
end

local function preserve_valid_queue(force, caps)
  local next_level = {}
  for technology_name, _ in pairs(caps) do
    local technology = force.technologies[technology_name]
    if technology then next_level[technology_name] = technology.level end
  end

  local prior_current = force.current_research
  local prior_current_name = prior_current and prior_current.name or nil
  local prior_progress = prior_current and force.research_progress or nil
  local filtered, removed = {}, {}
  for _, technology in ipairs(force.research_queue or {}) do
    local cap = caps[technology.name]
    local level = next_level[technology.name]
    if not cap or not level or level <= cap then
      table.insert(filtered, technology)
      if level then next_level[technology.name] = level + 1 end
    else
      table.insert(removed, technology.name .. "@" .. tostring(level))
    end
  end

  if #removed > 0 then
    force.research_queue = filtered
    local current = force.current_research
    if prior_current_name and current and current.name == prior_current_name and prior_progress then
      force.research_progress = prior_progress
    end
    log("[more-infinite-research] Normalized research above configured maximum"
      .. " force=" .. tostring(force.name)
      .. " removed=" .. table.concat(removed, ",")
      .. " retained-current=" .. tostring(current and current.name or "none")
      .. " completed-levels=retained.")
  end
end

local function restore_visibility(technology, visibility_by_cap, technology_name, force, policy)
  local record = visibility_by_cap[technology_name]
  if owns_visibility(record, force, policy) then
    technology.visible_when_disabled = record.value
    visibility_by_cap[technology_name] = nil
  end
end

local function restore_unowned_disable_continuity(technology, unowned_disabled_by_cap,
    technology_name, force, policy, cap)
  local record = unowned_disabled_by_cap[technology_name]
  if not cap and owns_unowned_disable_continuity(record, force, policy) then
    -- This restores one exact V2 state captured before Factorio's
    -- cap-relaxation transition, but does not give MIR enablement ownership.
    technology.enabled = false
    unowned_disabled_by_cap[technology_name] = nil
  end
end

local function normalize_force(force, managed, caps, transport_blocked, prior_managed)
  if not (force and force.valid) then return end
  local disabled_by_cap, visibility_by_cap, unowned_disabled_by_cap = force_cap_state(force)
  preserve_valid_queue(force, caps)

  local all_managed = {}
  for technology_name, _ in pairs(managed) do all_managed[technology_name] = true end
  for technology_name, _ in pairs(prior_managed or {}) do
    all_managed[technology_name] = true
  end
  for technology_name, _ in pairs(all_managed) do
    local technology = force.technologies[technology_name]
    local current_policy = managed[technology_name]
    local prior_policy = prior_managed and prior_managed[technology_name] or nil
    -- A binding removed by a stream/mod transition gets its previously
    -- persisted V3 policy only to prove an owned restoration. It never gets
    -- a cap from that prior policy. A current policy, even one that is
    -- blocked, remains authoritative for the technology.
    local policy = current_policy or prior_policy
    local cap = current_policy and caps[technology_name] or nil
    if technology and not transport_blocked
        and not (current_policy and current_policy.blocked_reason) then
      migrate_legacy_force_state(
        disabled_by_cap, visibility_by_cap, unowned_disabled_by_cap,
        technology_name, force, policy, cap)
      restore_unowned_disable_continuity(
        technology, unowned_disabled_by_cap, technology_name, force, policy, cap)
      if cap and technology.level > cap then
        if visibility_by_cap[technology_name] == nil then
          visibility_by_cap[technology_name] = captured_visibility(
            technology.visible_when_disabled, force, policy)
        end
        technology.visible_when_disabled = true
        if technology.enabled then
          disabled_by_cap[technology_name] = {
            policy_version = POLICY_VERSION,
            force_index = force.index,
            cap = cap,
            binding_fingerprint = policy and policy.binding_fingerprint or nil,
            ownership_key = ownership_key(policy),
            ownership_kind = policy and policy.ownership_kind or nil,
            enabled_before_cap = true
          }
          technology.enabled = false
        end
      else
        -- Visibility was MIR-owned even where enablement was not. Restore it
        -- independently. Enablement has a stricter record: only an exact
        -- F210/F200 V3 MIR enabled-to-disabled write for this force and
        -- binding transition is eligible for restoration. In particular,
        -- pre-disabled, unrecognized legacy, blocked, and mismatched state
        -- is left alone. Recognized V2 booleans were migrated above.
        restore_visibility(technology, visibility_by_cap, technology_name, force, policy)
        local disabled_record = disabled_by_cap[technology_name]
        if owns_disable(disabled_record, force, policy) then
          if not technology.enabled then technology.enabled = true end
          disabled_by_cap[technology_name] = nil
        end
      end

      if cap then
        local observation = table.concat({
          tostring(cap),
          tostring(observed_max_level(technology_name)),
          tostring(technology.level),
          tostring(technology.enabled),
          tostring(technology.visible_when_disabled)
        }, "|")
        local state = ensure_state()
        state.observations = state.observations or {}
        local key = tostring(force.index) .. "/" .. technology_name
        if state.observations[key] ~= observation then
          state.observations[key] = observation
          log("[more-infinite-research] Maximum-level state"
            .. " force=" .. tostring(force.name)
            .. " technology=" .. technology_name
            .. " selected-cap=" .. tostring(cap)
            .. " effective-cap=" .. tostring(cap)
            .. " prototype-max=" .. tostring(observed_max_level(technology_name))
            .. " current-or-next-level=" .. tostring(technology.level)
            .. " next-level-valid=" .. tostring(technology.level <= cap)
            .. " enabled=" .. tostring(technology.enabled)
            .. " visible-when-disabled=" .. tostring(technology.visible_when_disabled) .. ".")
        end
      end
    end
  end
end

local function remember_managed(managed)
  local state = ensure_state()
  state.managed_technologies = managed
  state.policy_version = POLICY_VERSION
end

local function clear_force_index(index)
  if not index then return end
  local state = ensure_state()
  if state.disabled_by_cap then state.disabled_by_cap[index] = nil end
  if state.visibility_by_cap then state.visibility_by_cap[index] = nil end
  if state.unowned_disabled_by_cap then state.unowned_disabled_by_cap[index] = nil end
  for key, _ in pairs(state.observations or {}) do
    if key:sub(1, #tostring(index) + 1) == tostring(index) .. "/" then
      state.observations[key] = nil
    end
  end
end

local function clear_force_state(force)
  clear_force_index(force and force.index)
end

local function normalize_all()
  local prior_managed = ensure_state().managed_technologies or {}
  local managed, caps, transport_blocked = current_policy()
  for _, force in pairs(game.forces) do
    normalize_force(force, managed, caps, transport_blocked, prior_managed)
  end
  remember_managed(managed)
end

local function force_from_event(event)
  if event and event.research and event.research.valid and event.research.force then
    return event.research.force
  end
  if event and event.destination and event.destination.valid then return event.destination end
  if event and event.force and event.force.valid then return event.force end
  return nil
end

local function normalize_event_force(event, research_only)
  local force = force_from_event(event)
  if not force then return end
  local prior_managed = ensure_state().managed_technologies or {}
  local managed, caps, transport_blocked = current_policy()
  if research_only then
    local name = event and event.research and event.research.name
    -- An unrelated research event changes no MIR-managed level or cap. Its
    -- queue transition preserves the cap validity checked when queued.
    if not name or (not managed[name] and not prior_managed[name]) then return end
  end
  normalize_force(force, managed, caps, transport_blocked, prior_managed)
  remember_managed(managed)
end

function M.on_init()
  invalidate_validated_policy()
  normalize_all()
end

function M.on_configuration_changed()
  invalidate_validated_policy()
  normalize_all()
end

function M.on_research_finished(event) normalize_event_force(event, true) end
function M.on_research_reversed(event) normalize_event_force(event, true) end
function M.on_research_queued(event) normalize_event_force(event, true) end
function M.on_technology_effects_reset(event) normalize_event_force(event) end
function M.on_force_created(event)
  clear_force_state(event and event.force)
  normalize_event_force(event)
end

function M.on_force_reset(event)
  local force = force_from_event(event)
  -- LuaForce.reset discards the force's research state. Any ownership record
  -- captured before that reset is no longer evidence about the reset state;
  -- clear only this force, then apply the current policy without restoring a
  -- pre-reset foreign value.
  clear_force_state(force)
  normalize_event_force(event)
end

function M.on_forces_merged(event)
  clear_force_index(event and event.source_index)
  normalize_event_force(event)
end

return M
