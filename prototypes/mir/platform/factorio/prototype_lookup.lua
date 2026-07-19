local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")

local L = {}

local FALLBACK_ENTITY_TYPES = {
  "accumulator", "ammo-turret", "artillery-turret", "assembling-machine", "beacon", "boiler",
  "burner-generator", "car", "container", "electric-energy-interface", "electric-pole", "electric-turret",
  "fluid-turret", "furnace", "generator", "inserter", "lab", "loader", "loader-1x1",
  "logistic-container", "mining-drill", "pipe", "pipe-to-ground", "pump", "radar", "reactor",
  "rocket-silo", "roboport", "solar-panel", "splitter", "storage-tank", "transport-belt",
  "underground-belt"
}

local ITEM_TYPES = {
  "item",
  "tool",
  "module",
  "ammo",
  "capsule",
  "gun",
  "armor",
  "repair-tool",
  "item-with-entity-data",
  "item-with-inventory",
  "item-with-label",
  "item-with-tags",
  "selection-tool",
  "copy-paste-tool",
  "blueprint",
  "blueprint-book",
  "deconstruction-item",
  "upgrade-item",
  "spidertron-remote",
  "rail-planner",
  "space-platform-starter-pack"
}

function L.item_prototype(name)
  if not name then return nil end
  for _, type_name in ipairs(ITEM_TYPES) do
    local bucket = data_raw.prototypes(type_name)
    if bucket and bucket[name] then return bucket[name] end
  end
  return nil
end

function L.fluid_prototype(name)
  if not name then return nil end
  return data_raw.prototype("fluid", name)
end

function L.each_item_prototype(callback)
  for _, type_name in ipairs(ITEM_TYPES) do
    for name, prototype in pairs(data_raw.prototypes(type_name)) do
      callback(name, prototype, type_name)
    end
  end
end

function L.item_types()
  local out = {}
  for _, type_name in ipairs(ITEM_TYPES) do table.insert(out, type_name) end
  return out
end

function L.entity_types()
  local out = {}
  local prototype_defines = type(defines) == "table" and defines.prototypes or nil
  local entity_defines = type(prototype_defines) == "table" and prototype_defines.entity or nil
  if type(entity_defines) == "table" then
    for type_name, _ in pairs(entity_defines) do table.insert(out, type_name) end
  else
    for _, type_name in ipairs(FALLBACK_ENTITY_TYPES) do table.insert(out, type_name) end
  end
  table.sort(out)
  return out
end

function L.entity_prototype(name)
  if not name then return nil end
  for _, type_name in ipairs(L.entity_types()) do
    local prototype = data_raw.prototype(type_name, name)
    if prototype then return prototype end
  end
  return nil
end

function L.each_entity_prototype(callback)
  for _, type_name in ipairs(L.entity_types()) do
    for name, prototype in pairs(data_raw.prototypes(type_name)) do
      callback(name, prototype, type_name)
    end
  end
end

function L.each_fluid_prototype(callback)
  for name, prototype in pairs(data_raw.prototypes("fluid")) do
    callback(name, prototype, "fluid")
  end
end

function L.technology_exists(name)
  return data_raw.technology(name) ~= nil
end

function L.ammo_category_exists(name)
  return data_raw.prototype("ammo-category", name) ~= nil
end

function L.is_space_age()
  return factorio_mods.exists("space-age")
end

function L.mod_exists(name)
  return name ~= nil and factorio_mods.exists(name)
end

return L
