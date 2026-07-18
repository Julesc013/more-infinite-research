local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")

local L = {}

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
