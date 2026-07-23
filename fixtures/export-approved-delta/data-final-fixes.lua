local function sorted_keys(values)
  local out = {}
  for key, _ in pairs(values or {}) do table.insert(out, key) end
  table.sort(out, function(left, right) return tostring(left) < tostring(right) end)
  return out
end

local function normalize(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return "<cycle>" end
  seen[value] = true
  local out = {}
  for _, key in ipairs(sorted_keys(value)) do out[key] = normalize(value[key], seen) end
  seen[value] = nil
  return out
end

local function normalized_ingredients(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    table.insert(out, {
      type = value.type or "item",
      name = value.name or value[1],
      amount = value.amount or value[2]
    })
  end
  table.sort(out, function(left, right)
    return tostring(left.type) .. "\0" .. tostring(left.name) .. "\0" .. tostring(left.amount)
      < tostring(right.type) .. "\0" .. tostring(right.name) .. "\0" .. tostring(right.amount)
  end)
  return out
end

local function normalized_names(values)
  local out = {}
  for _, value in ipairs(values or {}) do table.insert(out, tostring(value)) end
  table.sort(out)
  return out
end

local function normalized_technology(technology)
  local unit = technology.unit or {}
  return {
    name = technology.name,
    effects = normalize(technology.effects or {}),
    prerequisites = normalized_names(technology.prerequisites),
    science_ingredients = normalized_ingredients(unit.ingredients),
    count_formula = unit.count_formula,
    count = unit.count,
    research_time = unit.time,
    maximum_level = technology.max_level,
    upgrade = technology.upgrade ~= false,
    presentation = {
      localised_name = normalize(technology.localised_name),
      localised_description = normalize(technology.localised_description),
      icon = technology.icon,
      icon_size = technology.icon_size,
      icons = normalize(technology.icons),
      order = technology.order,
      level = technology.level,
      enabled = technology.enabled,
      hidden = technology.hidden
    },
    research_trigger = normalize(technology.research_trigger)
  }
end

local function shape(value, seen, depth)
  local value_type = type(value)
  if value_type ~= "table" then return value_type end
  depth = depth or 0
  if depth >= 4 then return {kind = "table", bounded = true} end
  seen = seen or {}
  if seen[value] then return {kind = "cycle"} end
  seen[value] = true
  local keys = sorted_keys(value)
  if #keys == 0 then
    seen[value] = nil
    return {kind = "empty-table"}
  end
  local is_array = true
  for index, key in ipairs(keys) do
    if type(key) ~= "number" or key ~= index then is_array = false; break end
  end
  local result
  if is_array then
    local item_shapes, identities = {}, {}
    local function shape_identity(item_shape)
      if type(item_shape) == "table" then return "table:" .. helpers.table_to_json(item_shape) end
      return type(item_shape) .. ":" .. tostring(item_shape)
    end
    for _, item in ipairs(value) do
      local item_shape = shape(item, seen, depth + 1)
      local identity = shape_identity(item_shape)
      if not identities[identity] and #item_shapes < 12 then
        identities[identity] = true
        table.insert(item_shapes, item_shape)
      end
    end
    table.sort(item_shapes, function(left, right)
      return shape_identity(left) < shape_identity(right)
    end)
    result = {kind = "array", item_shapes = item_shapes, bounded = #item_shapes == 12 or nil}
  elseif #keys > 32 then
    local value_shapes, identities = {}, {}
    local key_types = {}
    for _, key in ipairs(keys) do
      key_types[type(key)] = true
      local value_shape = shape(value[key], seen, depth + 1)
      local identity = type(value_shape) == "table" and helpers.table_to_json(value_shape)
        or type(value_shape) .. ":" .. tostring(value_shape)
      if not identities[identity] and #value_shapes < 12 then
        identities[identity] = true
        table.insert(value_shapes, value_shape)
      end
    end
    result = {kind = "map", key_types = sorted_keys(key_types), value_shapes = value_shapes, bounded = true}
  else
    local fields = {}
    for _, key in ipairs(keys) do fields[tostring(key)] = shape(value[key], seen, depth + 1) end
    result = {kind = "object", fields = fields}
  end
  seen[value] = nil
  return result
end

local plan_prototype = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-generation-plan"]
local plan = plan_prototype and plan_prototype.data
local evidence_prototype = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-compiler-evidence-internal"]
local evidence = evidence_prototype and evidence_prototype.data
local technology_names, registry_rows = {}, {}

local finalized_artifacts = plan
  and plan.schema == 1
  and plan.kind == "mir-generation-plan-public"
  and evidence
  and evidence.schema == 2
  and evidence.compiler_result

if finalized_artifacts then
  -- The C11 private generated registry belongs to the CompilerContext
  -- lifetime. Reconstruct its stable comparison projection from immutable
  -- artifacts emitted by the completed compiler run.
  for _, row in ipairs(plan.rows or {}) do
    if row.action == "emit" and row.technology_id then
      technology_names[row.technology_id] = true
      registry_rows[row.technology_id] = {
        name = row.technology_id,
        kind = "stream",
        key = row.stream_id
      }
    end
  end
  for _, candidate in ipairs(evidence.compiler_result.base_continuations or {}) do
    if candidate.action == "create" and candidate.technology_name then
      technology_names[candidate.technology_name] = true
      registry_rows[candidate.technology_name] = {
        name = candidate.technology_name,
        kind = "base_extension",
        key = candidate.key
      }
    end
  end
elseif mods and mods["more-infinite-research"] == "3.1.9" then
  -- The frozen 3.1.9 baseline predates finalized compiler artifacts and its
  -- registry is not context-scoped. This exact-version adapter exists only to
  -- reproduce the sealed baseline side of the governed delta.
  local legacy_registry = require(
    "__more-infinite-research__.prototypes.mir.domain.facts.generated_technology_registry"
  )
  for _, name in ipairs(legacy_registry.sorted_names()) do
    technology_names[name] = true
    local entry = legacy_registry.get(name)
    if entry then registry_rows[name] = normalize(entry) end
  end
else
  error("MIR approved-delta export requires finalized C11 compiler artifacts")
end

local adoption = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-productivity-family-adoption"]
for _, binding in ipairs((adoption and adoption.data and adoption.data.bindings) or {}) do
  if binding.owner then technology_names[binding.owner] = true end
end

local technologies = {}
for _, name in ipairs(sorted_keys(technology_names)) do
  local technology = data.raw.technology and data.raw.technology[name]
  if technology then technologies[name] = normalized_technology(technology) end
end

local setting_rows = {}
for name, current in pairs((settings and settings.startup) or {}) do
  if string.find(name, "^mir%-") or string.find(name, "^ips%-") then
    setting_rows[name] = {
      value_type = type(current.value),
      current_value = normalize(current.value)
    }
  end
end

local mod_data_rows = {}
for name, prototype in pairs(data.raw["mod-data"] or {}) do
  if string.find(name, "^more%-infinite%-research") then
    local payload = prototype.data
    mod_data_rows[name] = {
      data_type = prototype.data_type,
      schema = type(payload) == "table" and payload.schema or nil,
      version = type(payload) == "table" and payload.version or nil,
      contract_shape = shape(payload)
    }
  end
end

local active_mods = {}
for name, version in pairs(mods or {}) do active_mods[name] = version end

local artifact = {
  schema = 1,
  kind = "mir-approved-delta-runtime-export",
  active_mods = active_mods,
  technology_ids = sorted_keys(technology_names),
  technologies = technologies,
  generated_registry = registry_rows,
  settings = setting_rows,
  mod_data_contracts = mod_data_rows
}

log("[MIR_APPROVED_DELTA] " .. helpers.table_to_json(artifact))
