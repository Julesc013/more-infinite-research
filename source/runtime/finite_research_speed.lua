-- Identity history for the one finite7 -> MIR8 alternative. Native research
-- remains authoritative; this marker stores no levels, effects or work.
local M = {}
local KEY = "mir_finite_research_speed"

local function refuse()
  error("MIR cannot safely change finite research-speed ownership on this existing save; restore the previous mod selection and original save", 3)
end

local function recorded()
  local value = storage[KEY]
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= 1 or value.technology ~= "research-speed-8"
      or value.predecessor ~= "research-speed-7" or type(value.provider) ~= "string"
      or value.provider == "" or value.provider == "more-infinite-research" then refuse() end
  return value
end

local function positive_integer(value)
  return type(value) == "number" and value == value and value > 0
    and value < math.huge and value == math.floor(value)
end

local function legacy_emitted_eight()
  local mir = storage.mir
  local bucket = type(mir) == "table" and mir.maximum_level_control
  local managed = type(bucket) == "table" and bucket.managed_technologies
  local row = type(managed) == "table" and managed["research-speed-8"]
  if type(bucket) ~= "table" or bucket.policy_version ~= 3 or type(row) ~= "table" then return false end
  -- The F200 settings-derived tuple only proves management. It cannot
  -- grant creation custody, even when its setting and selected cap match.
  return row.technology == "research-speed-8" and row.setting == "mir-max-level-research-speed"
    and row.source == "base-continuation" and row.operation == "emit_base_extension"
    and row.policy_transport == "transported-v3" and row.ownership_kind == "transported-v3"
    and row.legacy == false and row.blocked_reason == nil and row.native_finite_stage == false
    and type(row.binding_fingerprint) == "string" and #row.binding_fingerprint == 14
    and row.binding_fingerprint:match("^mir32%-[0-9a-f]+$") ~= nil
    and (row.selected == "infinite" or positive_integer(row.selected))
end

local function legacy_mentions_eight()
  local mir = storage.mir
  local bucket = type(mir) == "table" and mir.maximum_level_control
  local managed = type(bucket) == "table" and bucket.managed_technologies
  -- Insufficient positive authority is still evidence that this identity
  -- may have existed. Never turn an ambiguous managed8 into a fresh7 save.
  return type(managed) == "table" and managed["research-speed-8"] ~= nil
end

local function unchanged_legacy_selection(changes)
  -- The first transported record has no old provider identity. Admit that
  -- entry only with the same upstream selection/versions; once the marker
  -- exists, unrelated mod changes no longer need this one-time restriction.
  for name, change in pairs(changes) do
    if name ~= "more-infinite-research" and type(change) == "table"
        and change.old_version ~= change.new_version then return false end
  end
  return true
end

-- Known published F210 transported-V3 versions. F200's settings-derived
-- controller cannot establish this creator proof, even at the same patch.
local PUBLISHED_F210_PATCHES = {
  [2]={[0]=true,[1]=true,[2]=true}, [3]={[0]=true},
  [4]={[0]=true,[1]=true,[2]=true}, [5]={[0]=true,[1]=true,[2]=true},
  [6]={[0]=true}, [7]={[0]=true,[1]=true,[2]=true,[3]=true}
}

local function published_legacy(version)
  if type(version) ~= "string" then return false end
  local minor, distribution = version:match("^4%.(%d+)%.(%d+)$")
  minor, distribution = tonumber(minor), tonumber(distribution)
  local patches = minor and PUBLISHED_F210_PATCHES[minor]
  return patches ~= nil and distribution ~= nil
    and version == "4." .. tostring(minor) .. "." .. tostring(distribution)
    and math.floor(distribution / 100) == 210
    and patches[distribution % 100] == true
end

function M.preflight(event, provider)
  local prior = recorded()
  local changes = type(event) == "table" and event.mod_changes
  local mir = type(changes) == "table" and changes["more-infinite-research"]
  local change = provider and type(changes) == "table" and changes[provider]
  if prior ~= nil then
    if provider ~= prior.provider then refuse() end
    if type(change) == "table" and ((change.old_version == nil) ~= (change.new_version == nil)) then refuse() end
    return nil
  end
  local legacy = legacy_emitted_eight()
  if provider == nil then
    if legacy_mentions_eight() then refuse() end
    return nil
  end
  if type(mir) ~= "table" or mir.old_version ~= nil then
    -- No current-MIR5 version label, new prototype, cap-management tuple or
    -- already-truncated native level can stand in for prior emitted8 proof.
    if type(mir) ~= "table" or not published_legacy(mir.old_version) or not legacy
        or type(event.mod_startup_settings_changed) ~= "boolean" or event.mod_startup_settings_changed
        or not unchanged_legacy_selection(changes) then refuse() end
  end
  return {schema=1,technology="research-speed-8",predecessor="research-speed-7",provider=provider}
end

function M.apply(plan)
  if plan ~= nil then storage[KEY] = plan end
end

function M.on_init(provider)
  if recorded() ~= nil then refuse() end
  if provider ~= nil then
    M.apply({schema=1,technology="research-speed-8",predecessor="research-speed-7",provider=provider})
  end
end

function M.on_load(provider)
  local prior = recorded()
  -- Existing mods load before on_configuration_changed. A missing marker
  -- may be the first valid legacy entry; admission belongs to that callback.
  if prior ~= nil and prior.provider ~= provider then refuse() end
end

return M
