-- Narrow decoder for restoration rights left by the pinned MIR 4.7 cap
-- controller.  This module is deliberately pure: the configuration-change
-- owner supplies the old bucket, current Force, already-admitted candidates,
-- and any current MIR5 ownership rows.  It never reads storage/global or
-- writes a LuaForce or LuaTechnology.
local M = {}

local POLICY_VERSION = 3
local TRANSPORTED_KIND = "transported-v3"
local SETTINGS_DERIVED_KIND = "settings-derived-v3"
local MAX_STRING_BYTES = 512
local MAX_CANDIDATES = 128

-- Exact native worker tails retained by the authored Base/Space Age and K2
-- bindings. Current native effect/predecessor admission still happens before
-- these predecessor restoration rights can be considered.
local WORKER = {
  names = {"worker-robots-speed-6", "worker-robots-speed-7"},
  setting = "mir-max-level-worker-robots-speed",
  source = "native-owner",
  operation = "native-owner-cap"
}

local function bounded_string(value)
  return type(value) == "string" and #value > 0 and #value <= MAX_STRING_BYTES
end

-- Published V3 bindings are always the MIR32 digest emitted by
-- `fingerprint.of`: the literal prefix plus eight lowercase hexadecimal
-- digits. The old controller's wider generic string limit was not its
-- producer contract, so accepting it here would widen historical authority.
local function mir32_fingerprint(value)
  return type(value) == "string" and #value == 14
    and value:match("^mir32%-%x+$") ~= nil and value == string.lower(value)
end

local function positive_integer(value)
  return type(value) == "number" and value == value and value > 0
    and value < math.huge and value == math.floor(value)
end

local function field(object, name)
  local ok, value = pcall(function() return object[name] end)
  if ok then return value end
  return nil
end

local function exact_key(candidate)
  return table.concat({candidate.name, candidate.setting, candidate.source,
    candidate.operation}, "\0")
end

-- F200's published 4.7.20002 controller could not use the finalizer transport:
-- its named generated streams and base continuations stored this exact
-- settings-derived tuple instead.  It is deliberately an authored target
-- binding, not a broad acceptance of an older policy shape.
local function binding_authority(binding, target_id)
  local source = type(binding) == "table" and binding.source or nil
  local operation = type(binding) == "table" and binding.operation or nil
  local transport = type(binding) == "table" and binding.policy_transport or TRANSPORTED_KIND
  local ownership = type(binding) == "table" and binding.ownership_kind or TRANSPORTED_KIND
  if transport == TRANSPORTED_KIND and ownership == TRANSPORTED_KIND then
    return {policy_transport = transport, ownership_kind = ownership}
  end
  if target_id == "f200" and binding and binding.target == "f200" and transport == SETTINGS_DERIVED_KIND
      and ownership == SETTINGS_DERIVED_KIND and operation == "runtime-settings-transport"
      and (source == "generated-stream" or source == "base-continuation") then
    return {policy_transport = transport, ownership_kind = ownership}
  end
  return nil
end

-- Build once at control parse time from the current authored declarations.
-- The returned map admits only exact published V3 tuple identities; candidate
-- rows never establish authority by merely asserting their own fields.
function M.allowlist(declarations, target_id)
  if type(declarations) ~= "table" then error("MIR legacy caps declarations must be a table", 2) end
  if target_id ~= nil and type(target_id) ~= "string" then
    error("MIR legacy caps target must be a string or nil", 2)
  end
  local allowed, count = {}, 0
  for index = 1, #declarations do
    local declaration = declarations[index]
    local binding = type(declaration) == "table" and declaration.legacy_binding or nil
    local name = type(declaration) == "table" and declaration.id or nil
    local setting = type(declaration) == "table" and declaration.cap_setting or nil
    local source = type(binding) == "table" and binding.source or nil
    local operation = type(binding) == "table" and binding.operation or nil
    local authority = binding_authority(binding, target_id)
    if not (bounded_string(name) and bounded_string(setting) and bounded_string(source)
        and bounded_string(operation) and authority ~= nil) then
      error("MIR legacy caps declaration lacks an exact binding", 2)
    end
    local key = table.concat({name, setting, source, operation}, "\0")
    if allowed[key] then error("MIR legacy caps declarations duplicate a binding", 2) end
    allowed[key] = authority
    count = count + 1
    if count > MAX_CANDIDATES then error("MIR legacy caps declarations exceed bound", 2) end
  end
  for index = 1, #WORKER.names do
    local key = table.concat({WORKER.names[index], WORKER.setting, WORKER.source, WORKER.operation}, "\0")
    if allowed[key] then error("MIR legacy caps worker binding collides", 2) end
    -- Published F200 4.7.20002 used this exact settings-derived runtime
    -- binding for the verified native worker-speed tail. Other targets retain
    -- their transported provenance; a legacy bucket never selects this path.
    allowed[key] = target_id == "f200"
      and {policy_transport = SETTINGS_DERIVED_KIND, ownership_kind = SETTINGS_DERIVED_KIND}
      or {policy_transport = TRANSPORTED_KIND, ownership_kind = TRANSPORTED_KIND}
  end
  return allowed
end

local function admitted_candidate(candidate, allowed)
  if not (type(candidate) == "table" and candidate.admitted == true
    and bounded_string(candidate.name) and bounded_string(candidate.setting)
    and bounded_string(candidate.source) and bounded_string(candidate.operation)
    and type(allowed) == "table") then return nil end
  local authority = allowed[exact_key(candidate)]
  if type(authority) ~= "table" or authority.policy_transport == nil
      or authority.ownership_kind == nil then return nil end
  return authority
end

local function candidate_list(candidates)
  if type(candidates) ~= "table" then
    error("MIR legacy caps candidates must be a table", 3)
  end
  local entries, count = {}, 0
  -- This bounded iteration validates the parse-time authored admission list
  -- without ever traversing historical saved maps.
  for index, candidate in pairs(candidates) do
    count = count + 1
    if count > MAX_CANDIDATES then error("MIR legacy caps candidates exceed bound", 3) end
    if type(index) ~= "number" or index ~= math.floor(index)
        or index < 1 or index > MAX_CANDIDATES or entries[index] ~= nil then
      error("MIR legacy caps candidates must be a dense array", 3)
    end
    entries[index] = candidate
  end
  for index = 1, count do
    if entries[index] == nil then error("MIR legacy caps candidates must be a dense array", 3) end
  end
  return entries, count
end

local function policy_matches(policy, candidate, authority)
  if type(policy) ~= "table" then return false end
  local identity_matches
  if authority.policy_transport == SETTINGS_DERIVED_KIND then
    -- The exact F200 producer never stored technology or a binding digest.
    -- Its name is the managed map key, independently selected by the caller.
    identity_matches = policy.technology == nil and policy.binding_fingerprint == nil
      and type(policy.native_finite_stage) == "boolean"
  else
    identity_matches = policy.technology == candidate.name
      and mir32_fingerprint(policy.binding_fingerprint)
  end
  return identity_matches and policy.setting == candidate.setting
    and policy.source == candidate.source
    and policy.operation == candidate.operation
    and policy.policy_transport == authority.policy_transport
    and policy.ownership_kind == authority.ownership_kind
    and policy.legacy == false
    and policy.blocked_reason == nil
    and positive_integer(policy.selected)
end

local function persisted_key(candidate, authority)
  if authority.policy_transport == SETTINGS_DERIVED_KIND then
    -- Historical ownership_key used tostring(policy.technology), hence the
    -- literal "nil" for this producer. Never accept this key on F210.
    return table.concat({"nil", candidate.setting, candidate.source, candidate.operation}, "\0")
  end
  return exact_key(candidate)
end

local function visibility_matches(record, force_index, candidate, authority)
  return type(record) == "table"
    and record.policy_version == POLICY_VERSION
    and record.force_index == force_index
    and record.ownership_key == persisted_key(candidate, authority)
    and record.ownership_kind == authority.ownership_kind
    and type(record.value) == "boolean"
end

local function disable_matches(record, policy, force_index, candidate, authority)
  return type(record) == "table"
    and record.policy_version == POLICY_VERSION
    and record.force_index == force_index
    and positive_integer(record.cap)
    and record.cap == policy.selected
    and record.binding_fingerprint == policy.binding_fingerprint
    and ((authority.policy_transport == SETTINGS_DERIVED_KIND and record.binding_fingerprint == nil)
      or (authority.policy_transport == TRANSPORTED_KIND and mir32_fingerprint(record.binding_fingerprint)))
    and record.ownership_key == persisted_key(candidate, authority)
    and record.ownership_kind == authority.ownership_kind
    and record.enabled_before_cap == true
    -- Do not bridge rights that were themselves reconstructed from V2 state.
    and record.migrated_from_policy_version == nil
end

local function native_technology(force, name)
  local technologies = field(force, "technologies")
  if technologies == nil then return nil end
  local ok, technology = pcall(function() return technologies[name] end)
  if ok then return technology end
  return nil
end

local function current_visibility_owned_state(technology)
  return technology ~= nil and field(technology, "visible_when_disabled") == true
end

local function current_disable_owned_state(technology)
  return technology ~= nil and field(technology, "enabled") == false
end

local function set_decision(facts, index, candidate, outcome)
  facts.decisions[index] = {
    name = type(candidate) == "table" and candidate.name or nil,
    outcome = outcome
  }
end

-- Decode restoration rights for one current force.
--
-- `legacy_bucket` is exactly the historical `storage.mir.maximum_level_control`
-- bucket. `candidates` is a dense list from the parse-time authored allowlist,
-- each shaped `{name, setting, source, operation, admitted=true}`. For worker
-- candidates `admitted` comes from its current native-tail validation.
-- `current_owned` is the MIR5 map for this force; existing rows always win.
-- The returned name-keyed rows are new plain tables suitable for the caller to
-- merge into that map.
function M.import_for_force(legacy_bucket, force, candidates, current_owned, allowed)
  local entries, count = candidate_list(candidates)
  if current_owned ~= nil and type(current_owned) ~= "table" then
    error("MIR legacy caps current ownership must be a table or nil", 2)
  end

  local rows = {}
  local facts = {legacy_policy3 = false, candidates_checked = count, imported = 0, decisions = {}}
  if type(legacy_bucket) ~= "table" or legacy_bucket.policy_version ~= POLICY_VERSION then
    for index = 1, count do set_decision(facts, index, entries[index], "legacy_policy_unrecognized") end
    return rows, facts
  end
  facts.legacy_policy3 = true

  if force == nil or field(force, "valid") == false then
    for index = 1, count do set_decision(facts, index, entries[index], "force_unavailable") end
    return rows, facts
  end
  local force_index = field(force, "index")
  if not positive_integer(force_index) then
    for index = 1, count do set_decision(facts, index, entries[index], "force_index_invalid") end
    return rows, facts
  end

  local saved_managed = field(legacy_bucket, "managed_technologies")
  local saved_disabled = field(legacy_bucket, "disabled_by_cap")
  local saved_visibility = field(legacy_bucket, "visibility_by_cap")
  local saved_unowned = field(legacy_bucket, "unowned_disabled_by_cap")
  local managed = type(saved_managed) == "table" and saved_managed or nil
  local disabled = type(saved_disabled) == "table" and saved_disabled[force_index] or nil
  local visibility = type(saved_visibility) == "table" and saved_visibility[force_index] or nil
  local unowned = type(saved_unowned) == "table" and saved_unowned[force_index] or nil

  for index = 1, count do
    local candidate = entries[index]
    local authority = admitted_candidate(candidate, allowed)
    if authority == nil then
      set_decision(facts, index, candidate, "candidate_not_admitted")
    elseif current_owned and current_owned[candidate.name] ~= nil then
      set_decision(facts, index, candidate, "current_mir5_ownership_retained")
    else
      local policy = managed and managed[candidate.name] or nil
      local disabled_record = type(disabled) == "table" and disabled[candidate.name] or nil
      local visibility_record = type(visibility) == "table" and visibility[candidate.name] or nil
      local unowned_record = type(unowned) == "table" and unowned[candidate.name] or nil
      local technology = native_technology(force, candidate.name)
      if not policy_matches(policy, candidate, authority) then
        set_decision(facts, index, candidate, "policy_mismatch")
      elseif not visibility_matches(visibility_record, force_index, candidate, authority) then
        set_decision(facts, index, candidate, "visibility_record_mismatch")
      elseif not current_visibility_owned_state(technology) then
        set_decision(facts, index, candidate, "visibility_state_changed")
      elseif disable_matches(disabled_record, policy, force_index, candidate, authority)
          and unowned_record == nil and current_disable_owned_state(technology) then
        rows[candidate.name] = {disabled = true, visible_when_disabled = visibility_record.value}
        facts.imported = facts.imported + 1
        set_decision(facts, index, candidate, "owned_disable_imported")
      else
        -- Visibility is a separately captured MIR write. It stays restorable
        -- when another actor has re-enabled the technology or when the old
        -- V2 foreign-disable continuity row coexists, but neither condition
        -- can establish an enablement restoration right.
        rows[candidate.name] = {visible_when_disabled = visibility_record.value}
        facts.imported = facts.imported + 1
        if unowned_record ~= nil then
          set_decision(facts, index, candidate, "visibility_imported_unowned_disable_excluded")
        elseif disable_matches(disabled_record, policy, force_index, candidate, authority) then
          set_decision(facts, index, candidate, "visibility_imported_enablement_reenabled")
        elseif disabled_record == nil then
          set_decision(facts, index, candidate, "visibility_only_imported")
        else
          set_decision(facts, index, candidate, "visibility_imported_disable_unproven")
        end
      end
    end
  end
  return rows, facts
end

return M
