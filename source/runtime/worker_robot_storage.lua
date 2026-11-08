-- History for an admitted foreign finite worker-storage chain. This records
-- identities and creators only; Factorio retains levels, effects and work.
local M = {}
local KEY, MIR = "mir_worker_storage_route", "more-infinite-research"

local function refuse(reason, route)
  error("MIR worker storage history: " .. reason .. "; restore the previous mod selection and original save"
    .. " [MIR-WORKER-HISTORY technology=" .. tostring(route and route.technology or "default") .. "]", 3)
end

local function integer(value)
  return type(value) == "number" and value > 0 and value < 4294967295 and value == math.floor(value)
end

local function provider(value)
  return type(value) == "string" and value ~= "" and value ~= MIR
end

local function checked(value)
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= 1 or type(value.route) ~= "table" then
    refuse("invalid saved route")
  end
  for key in pairs(value) do
    if key ~= "schema" and key ~= "route" then refuse("unknown saved route field") end
  end
  local route = value.route
  if not integer(route.level) or route.level <= 4
      or route.technology ~= "worker-robots-storage-" .. route.level
      or type(route.owned) ~= "boolean" or type(route.finite) ~= "table" or #route.finite == 0
      or route.owned and route.provider ~= nil or not route.owned and not provider(route.provider) then
    refuse("invalid saved continuation", route)
  end
  for key in pairs(route) do
    if key ~= "technology" and key ~= "level" and key ~= "predecessor" and key ~= "owned"
        and key ~= "provider" and key ~= "finite" and key ~= "legacy_compatible" then
      refuse("unknown saved continuation field", route)
    end
  end
  if route.legacy_compatible ~= nil and type(route.legacy_compatible) ~= "boolean" then
    refuse("invalid legacy compatibility fact", route)
  end
  local count = 0
  for key in pairs(route.finite) do
    if not integer(key) or key > #route.finite then refuse("invalid finite chain array", route) end
    count = count + 1
  end
  if count ~= #route.finite then refuse("sparse finite chain", route) end
  local next_level, predecessor = 4, nil
  for _, stage in ipairs(route.finite) do
    if type(stage) ~= "table" or stage.name ~= "worker-robots-storage-" .. next_level
        or not integer(stage.max_level) or stage.max_level < next_level or not provider(stage.provider) then
      refuse("invalid saved finite chain", route)
    end
    for key in pairs(stage) do
      if key ~= "name" and key ~= "max_level" and key ~= "provider" then
        refuse("unknown finite chain field", route)
      end
    end
    next_level, predecessor = stage.max_level + 1, stage.name
  end
  if next_level ~= route.level or predecessor ~= route.predecessor then refuse("invalid saved endpoint", route) end
  return route
end

local function copy(route)
  local out = {technology=route.technology, level=route.level, predecessor=route.predecessor,
    owned=route.owned, provider=route.provider, finite={}}
  for index, stage in ipairs(route.finite) do
    out.finite[index] = {name=stage.name, max_level=stage.max_level, provider=stage.provider}
  end
  return out
end

local function same(left, right)
  if left == nil or right == nil then return left == right end
  for _, key in ipairs({"technology", "level", "predecessor", "owned", "provider"}) do
    if left[key] ~= right[key] then return false end
  end
  if #left.finite ~= #right.finite then return false end
  for index, stage in ipairs(left.finite) do
    local other = right.finite[index]
    if stage.name ~= other.name or stage.max_level ~= other.max_level or stage.provider ~= other.provider then return false end
  end
  return true
end

-- Published F2104.7.3's transported-V3 emission record can prove the old
-- continuation. A current prototype, settings-derived row or version alone
-- cannot. Keep the upstream selection and startup settings unchanged here.
local function legacy_emission(event, route)
  if not route.owned or route.legacy_compatible ~= true or type(event) ~= "table"
      or event.mod_startup_settings_changed ~= false then return false end
  local changes = event.mod_changes
  local change = type(changes) == "table" and changes[MIR]
  local active = script and script.active_mods or {}
  if type(change) ~= "table" or change.old_version ~= "4.7.21003"
      or change.new_version ~= active[MIR] or type(change.new_version) ~= "string"
      or not change.new_version:match("^5%.0%.210%d%d$") then return false end
  for name, item in pairs(changes) do
    if name ~= MIR and type(item) == "table" and item.old_version ~= item.new_version then return false end
  end
  local mir = storage.mir
  local bucket = type(mir) == "table" and mir.maximum_level_control
  local managed = type(bucket) == "table" and bucket.managed_technologies
  local row = type(managed) == "table" and managed[route.technology]
  return type(bucket) == "table" and bucket.policy_version == 3 and type(row) == "table"
    and row.technology == route.technology and row.setting == "mir-max-level-worker-robots-storage"
    and row.source == "base-continuation" and row.operation == "emit_base_extension"
    and row.policy_transport == "transported-v3" and row.ownership_kind == "transported-v3"
    and row.legacy == false and row.blocked_reason == nil and row.native_finite_stage == false
    and type(row.binding_fingerprint) == "string" and #row.binding_fingerprint == 14
    and row.binding_fingerprint:match("^mir32%-[0-9a-f]+$") ~= nil
    and (row.selected == "infinite" or integer(row.selected))
end

function M.preflight(event, route)
  local prior = checked(storage[KEY])
  if prior ~= nil then
    if not same(prior, route) then refuse("finite endpoint or creator changed", route) end
    return nil
  end
  if route == nil then return nil end
  checked({schema=1, route=route})
  local changes = type(event) == "table" and event.mod_changes
  local mir = type(changes) == "table" and changes[MIR]
  local first_install = type(mir) == "table" and mir.old_version == nil
    and script and script.active_mods and mir.new_version == script.active_mods[MIR]
  if not first_install and not legacy_emission(event, route) then
    refuse("previous continuation ownership is unknown", route)
  end
  return {schema=1, route=copy(route)}
end

function M.apply(plan)
  if plan ~= nil then storage[KEY] = plan end
end

function M.on_init(route)
  if storage[KEY] ~= nil then refuse("unexpected initial history", route) end
  if route ~= nil then
    checked({schema=1, route=route})
    M.apply({schema=1, route=copy(route)})
  end
end

function M.on_load(route)
  local prior = checked(storage[KEY])
  if prior ~= nil and not same(prior, route) then refuse("finite endpoint or creator changed", route) end
end

return M
