local deepcopy = require("prototypes.mir.core.deepcopy")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
local SCHEMA = 1

local function append(index, key, value)
  index[key] = index[key] or {}
  table.insert(index[key], value)
end

local function build()
  local context = compiler_context.current()
  local cached = context:state_view("item_prototype_index")
  if cached then return cached end

  local entity_type_by_name = {}
  local entity_rows = 0
  lookup.each_entity_prototype(function(name, _, type_name)
    local previous = entity_type_by_name[name]
    if previous and previous ~= type_name then
      error("MIR entity prototype name resolves to multiple types: " .. tostring(name), 2)
    end
    entity_type_by_name[name] = type_name
    entity_rows = entity_rows + 1
  end)

  local placeable_items_by_entity_type = {}
  local module_items_by_tier = {}
  local item_rows, placeable_rows, module_rows = 0, 0, 0
  lookup.each_item_prototype(function(name, prototype, item_type)
    item_rows = item_rows + 1
    local entity_type = type(prototype) == "table"
      and prototype.place_result
      and entity_type_by_name[prototype.place_result]
      or nil
    if entity_type then
      append(placeable_items_by_entity_type, entity_type, name)
      placeable_rows = placeable_rows + 1
    end
    if item_type == "module" then
      local tier = type(prototype) == "table" and tonumber(prototype.tier) or nil
      if tier then
        append(module_items_by_tier, tier, name)
        module_rows = module_rows + 1
      end
    end
  end)

  for _, names in pairs(placeable_items_by_entity_type) do table.sort(names) end
  for _, names in pairs(module_items_by_tier) do table.sort(names) end

  local canonical = {
    schema = SCHEMA,
    entity_type_by_name = entity_type_by_name,
    placeable_items_by_entity_type = placeable_items_by_entity_type,
    module_items_by_tier = module_items_by_tier,
    metrics = {
      entity_rows = entity_rows,
      item_rows = item_rows,
      placeable_rows = placeable_rows,
      module_rows = module_rows
    }
  }
  telemetry.count("item_prototype_index_builds", 1)
  telemetry.count("entity_prototype_index_rows", entity_rows)
  telemetry.count("item_prototype_index_rows", item_rows)
  telemetry.count("placeable_item_index_rows", placeable_rows)
  telemetry.count("module_tier_index_rows", module_rows)
  context:set_state("item_prototype_index", canonical)
  context:freeze_state("item_prototype_index")
  return canonical
end

function M.entity_type(name)
  telemetry.count("entity_prototype_index_lookups", 1)
  return build().entity_type_by_name[name]
end

function M.placeable_items_for_entity_types(entity_types)
  telemetry.count("placeable_item_index_lookups", 1)
  local index, seen, out = build(), {}, {}
  for _, entity_type in ipairs(entity_types or {}) do
    for _, name in ipairs(index.placeable_items_by_entity_type[entity_type] or {}) do
      if not seen[name] then seen[name] = true; table.insert(out, name) end
    end
  end
  table.sort(out)
  return out
end

function M.module_items(options)
  telemetry.count("module_tier_index_lookups", 1)
  options = options or {}
  local tier_set = nil
  if type(options.module_tiers) == "table" then
    tier_set = {}
    for _, tier in ipairs(options.module_tiers) do tier_set[tonumber(tier)] = true end
  end
  local minimum = tonumber(options.module_tier_min)
  local maximum = tonumber(options.module_tier_max)
  local out = {}
  for tier, names in pairs(build().module_items_by_tier) do
    if (not tier_set or tier_set[tier])
      and (minimum == nil or tier >= minimum)
      and (maximum == nil or tier <= maximum)
    then
      for _, name in ipairs(names) do table.insert(out, name) end
    end
  end
  table.sort(out)
  return out
end

function M.snapshot()
  return deepcopy(build())
end

return M
