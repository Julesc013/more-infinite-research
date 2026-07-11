local source = data.raw.beacon and data.raw.beacon.beacon
if source then
  local beacon = table.deepcopy(source)
  beacon.name = "mir-fixture-zero-watt-beacon"
  beacon.localised_name = {"entity-name.beacon"}
  beacon.minable = nil
  if settings.startup["mir-prototype-positive-power-floor"].value == true then
    beacon.energy_usage = "0W"
  else
    beacon.energy_usage = "1W"
  end
  data:extend({beacon})
end

local function clone_item(source_name, target_name)
  local source_item = data.raw.item and data.raw.item[source_name]
  if not source_item then return nil end
  local item = table.deepcopy(source_item)
  item.name = target_name
  item.localised_name = {"item-name." .. source_name}
  item.hidden = true
  return item
end

local safe_item = clone_item("iron-plate", "mir-fixture-self-recycling-item")
local unsafe_item = clone_item("copper-plate", "mir-fixture-non-recycling-item")
local fixture_prototypes = {}
if not (data.raw["recipe-category"] and data.raw["recipe-category"].recycling) then
  table.insert(fixture_prototypes, {type = "recipe-category", name = "recycling"})
end
if safe_item then table.insert(fixture_prototypes, safe_item) end
if unsafe_item then table.insert(fixture_prototypes, unsafe_item) end

local module_source = data.raw.module and data.raw.module["productivity-module-3"]
if module_source then
  local module = table.deepcopy(module_source)
  module.name = "mir-fixture-productivity-module-4"
  module.localised_name = {"item-name.productivity-module-3"}
  module.tier = 4
  table.insert(fixture_prototypes, module)
  table.insert(fixture_prototypes, {
    type = "recipe",
    name = "mir-fixture-productivity-module-4",
    enabled = true,
    ingredients = {{type = "item", name = "productivity-module-3", amount = 1}},
    results = {{type = "item", name = module.name, amount = 1}}
  })
end

if safe_item and unsafe_item then
  table.insert(fixture_prototypes, {
    type = "recipe",
    name = "mir-fixture-self-recycling-production",
    categories = {"crafting"},
    enabled = true,
    allow_productivity = true,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = safe_item.name, amount = 1}}
  })
  table.insert(fixture_prototypes, {
    type = "recipe",
    name = "mir-fixture-self-recycling-loop",
    categories = {"crafting"},
    enabled = true,
    allow_productivity = true,
    ingredients = {{type = "item", name = safe_item.name, amount = 1}},
    results = {{type = "item", name = safe_item.name, amount = 0.25}}
  })
  table.insert(fixture_prototypes, {
    type = "recipe",
    name = "mir-fixture-non-recycling-production",
    categories = {"crafting"},
    enabled = true,
    allow_productivity = true,
    ingredients = {{type = "item", name = "copper-plate", amount = 1}},
    results = {{type = "item", name = unsafe_item.name, amount = 1}}
  })
  table.insert(fixture_prototypes, {
    type = "recipe",
    name = "mir-fixture-generated-recycling",
    categories = {"recycling"},
    hidden = true,
    enabled = false,
    unlock_results = false,
    ingredients = {{type = "item", name = unsafe_item.name, amount = 1, ignored_by_stats = 1}},
    results = {{
      type = "item",
      name = unsafe_item.name,
      amount = 1,
      independent_probability = 0.25,
      ignored_by_stats = 1
    }}
  })
  table.insert(fixture_prototypes, {
    type = "recipe",
    name = "mir-fixture-visible-recycling",
    categories = {"recycling"},
    hidden = false,
    enabled = true,
    unlock_results = true,
    ingredients = {{type = "item", name = unsafe_item.name, amount = 1}},
    results = {{type = "item", name = "copper-plate", amount = 1, independent_probability = 0.25}}
  })
end
if #fixture_prototypes > 0 then data:extend(fixture_prototypes) end
