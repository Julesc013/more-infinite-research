-- Narrow decoder for restoration rights left by the pinned MIR 4.7 cap
-- controller.  This module is deliberately pure: the configuration-change
-- owner supplies the old bucket, current Force, already-admitted candidates,
-- and any current MIR5 ownership rows.  It never reads storage/global or
-- writes a LuaForce or LuaTechnology.
local M = {}

local POLICY_VERSION = 3
local TRANSPORTED_KIND = "transported-v3"
local MAX_STRING_BYTES = 512

local GEAR = {
  name = "recipe-prod-research_gears-1",
  setting = "ips-max-level-research_gears",
  source = "generated-stream",
  -- This is the released F210 V3 binding operation, not MIR5's current
  -- settings-transport provenance. See the accepted 4.7.21000 archive,
  -- `prototypes/mir/domain/technology/maximum_level_binding.lua:264-277`.
  operation = "emit"
}

-- The direct-effect continuations used the same generated-stream emitter as
-- gear in the published F210 V3 maximum-level binding. These are distinct
-- historic identities; accepting a family prefix or a present prototype here
-- would turn a one-shot import into a new ownership claim.
local AGRICULTURE = {
  name = "recipe-prod-research_agricultural_growth_speed-1",
  setting = "ips-max-level-research_agricultural_growth_speed",
  source = "generated-stream",
  operation = "emit"
}

local SPOILAGE = {
  name = "recipe-prod-research_spoilage_preservation-1",
  setting = "ips-max-level-research_spoilage_preservation",
  source = "generated-stream",
  operation = "emit"
}

local WORKER = {
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

local function admitted_candidate(candidate)
  if type(candidate) ~= "table" or candidate.admitted ~= true
      or not bounded_string(candidate.name) then return false end
  if candidate.name == GEAR.name then
    return candidate.setting == GEAR.setting and candidate.source == GEAR.source
      and candidate.operation == GEAR.operation
  end
  if candidate.name == AGRICULTURE.name then
    return candidate.setting == AGRICULTURE.setting and candidate.source == AGRICULTURE.source
      and candidate.operation == AGRICULTURE.operation
  end
  if candidate.name == SPOILAGE.name then
    return candidate.setting == SPOILAGE.setting and candidate.source == SPOILAGE.source
      and candidate.operation == SPOILAGE.operation
  end
  if candidate.name == "worker-robots-speed-6" or candidate.name == "worker-robots-speed-7" then
    -- `admitted` is the caller's result of the current native-owner selector;
    -- this decoder must not inspect prototypes or infer worker ownership.
    return candidate.setting == WORKER.setting and candidate.source == WORKER.source
      and candidate.operation == WORKER.operation
  end
  return false
end

local function candidate_list(candidates)
  if type(candidates) ~= "table" then
    error("MIR legacy caps candidates must be a table", 3)
  end
  local entries, count = {}, 0
  -- This bounded iteration deliberately validates the caller boundary without
  -- ever traversing historical saved maps. The four named admissions are
  -- gear, the two direct continuations, and the current worker tail.
  for index, candidate in pairs(candidates) do
    count = count + 1
    if count > 4 then error("MIR legacy caps accepts at most four candidates", 3) end
    if type(index) ~= "number" or index ~= math.floor(index)
        or index < 1 or index > 4 or entries[index] ~= nil then
      error("MIR legacy caps candidates must be a dense array", 3)
    end
    entries[index] = candidate
  end
  for index = 1, count do
    if entries[index] == nil then error("MIR legacy caps candidates must be a dense array", 3) end
  end
  return entries, count
end

local function policy_matches(policy, candidate)
  if type(policy) ~= "table" then return false end
  return policy.technology == candidate.name
    and policy.setting == candidate.setting
    and policy.source == candidate.source
    and policy.operation == candidate.operation
    and policy.policy_transport == TRANSPORTED_KIND
    and policy.ownership_kind == TRANSPORTED_KIND
    and policy.legacy == false
    and policy.blocked_reason == nil
    and positive_integer(policy.selected)
    and mir32_fingerprint(policy.binding_fingerprint)
end

local function visibility_matches(record, force_index, candidate)
  return type(record) == "table"
    and record.policy_version == POLICY_VERSION
    and record.force_index == force_index
    and record.ownership_key == exact_key(candidate)
    and record.ownership_kind == TRANSPORTED_KIND
    and type(record.value) == "boolean"
end

local function disable_matches(record, policy, force_index, candidate)
  return type(record) == "table"
    and record.policy_version == POLICY_VERSION
    and record.force_index == force_index
    and positive_integer(record.cap)
    and record.cap == policy.selected
    and record.binding_fingerprint == policy.binding_fingerprint
    and mir32_fingerprint(record.binding_fingerprint)
    and record.ownership_key == exact_key(candidate)
    and record.ownership_kind == TRANSPORTED_KIND
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
-- bucket. `candidates` is a dense list of at most four current admissions,
-- each shaped `{name, setting, source, operation, admitted=true}`. For worker
-- candidates `admitted` must come from the caller's current native-tail
-- validation. `current_owned` is the MIR5 map for this force; existing rows
-- always win. The returned name-keyed rows are new plain tables suitable for
-- the caller to merge into that map.
function M.import_for_force(legacy_bucket, force, candidates, current_owned)
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
    if not admitted_candidate(candidate) then
      set_decision(facts, index, candidate, "candidate_not_admitted")
    elseif current_owned and current_owned[candidate.name] ~= nil then
      set_decision(facts, index, candidate, "current_mir5_ownership_retained")
    else
      local policy = managed and managed[candidate.name] or nil
      local disabled_record = type(disabled) == "table" and disabled[candidate.name] or nil
      local visibility_record = type(visibility) == "table" and visibility[candidate.name] or nil
      local unowned_record = type(unowned) == "table" and unowned[candidate.name] or nil
      local technology = native_technology(force, candidate.name)
      if not policy_matches(policy, candidate) then
        set_decision(facts, index, candidate, "policy_mismatch")
      elseif not visibility_matches(visibility_record, force_index, candidate) then
        set_decision(facts, index, candidate, "visibility_record_mismatch")
      elseif not current_visibility_owned_state(technology) then
        set_decision(facts, index, candidate, "visibility_state_changed")
      elseif disable_matches(disabled_record, policy, force_index, candidate)
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
        elseif disable_matches(disabled_record, policy, force_index, candidate) then
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
