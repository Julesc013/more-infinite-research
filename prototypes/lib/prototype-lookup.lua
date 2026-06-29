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
    local bucket = data.raw[type_name]
    if bucket and bucket[name] then return bucket[name] end
  end
  return nil
end

function L.each_item_prototype(callback)
  for _, type_name in ipairs(ITEM_TYPES) do
    for name, prototype in pairs(data.raw[type_name] or {}) do
      callback(name, prototype, type_name)
    end
  end
end

function L.technology_exists(name)
  return name ~= nil and (data.raw.technology or {})[name] ~= nil
end

function L.ammo_category_exists(name)
  return name ~= nil and (data.raw["ammo-category"] or {})[name] ~= nil
end

function L.is_space_age()
  return mods and mods["space-age"] ~= nil
end

return L
