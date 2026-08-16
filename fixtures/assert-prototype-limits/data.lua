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
local ignored_item = clone_item("steel-plate", "mir-fixture-ignored-productivity-item")
local nonstandard_item = clone_item("battery", "mir-fixture-nonstandard-return-item")
local fixture_prototypes = {}
if not (data.raw["recipe-category"] and data.raw["recipe-category"].recycling) then
  table.insert(fixture_prototypes, {type = "recipe-category", name = "recycling"})
end
if safe_item then table.insert(fixture_prototypes, safe_item) end
if unsafe_item then table.insert(fixture_prototypes, unsafe_item) end
if ignored_item then table.insert(fixture_prototypes, ignored_item) end
if nonstandard_item then table.insert(fixture_prototypes, nonstandard_item) end

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

if safe_item and unsafe_item and ignored_item and nonstandard_item then
  local function boundary_recipe(name, ingredients, results, extra)
    local recipe = {
      type = "recipe",
      name = name,
      categories = {"crafting"},
      enabled = true,
      allow_productivity = true,
      icon = "__base__/graphics/icons/iron-plate.png",
      icon_size = 64,
      ingredients = ingredients,
      results = results
    }
    for key, value in pairs(extra or {}) do recipe[key] = value end
    table.insert(fixture_prototypes, recipe)
  end

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
    name = "mir-fixture-preexisting-high-productivity-cap",
    categories = {"crafting"},
    enabled = true,
    allow_productivity = true,
    maximum_productivity = 50,
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

  boundary_recipe("mir-fixture-boundary-multiple-path-candidate",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "iron-stick", amount = 1}})
  boundary_recipe("mir-fixture-boundary-multiple-path-a",
    {{type = "item", name = "iron-stick", amount = 1}},
    {{type = "item", name = "iron-stick", amount = 1, independent_probability = 0.25}})
  boundary_recipe("mir-fixture-boundary-multiple-path-b",
    {{type = "item", name = "iron-stick", amount = 1}},
    {{type = "item", name = "iron-stick", amount = 1, independent_probability = 0.20}})

  boundary_recipe("mir-fixture-boundary-byproduct-candidate",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "copper-cable", amount = 1}})
  boundary_recipe("mir-fixture-boundary-byproduct-return",
    {{type = "item", name = "copper-cable", amount = 1}},
    {
      {type = "item", name = "copper-cable", amount = 1, independent_probability = 0.25},
      {type = "item", name = "stone", amount = 1, independent_probability = 0.10}
    })

  boundary_recipe("mir-fixture-boundary-probabilistic-candidate",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "steel-plate", amount = 1, independent_probability = 0.5}})

  boundary_recipe("mir-fixture-boundary-ignored-candidate",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = ignored_item.name, amount = 1}})
  boundary_recipe("mir-fixture-boundary-ignored-return",
    {{type = "item", name = ignored_item.name, amount = 1}},
    {{type = "item", name = ignored_item.name, amount = 1, independent_probability = 0.25, ignored_by_productivity = 0.10}})

  boundary_recipe("mir-fixture-boundary-fluid-candidate",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "fluid", name = "water", amount = 10}},
    {categories = {"chemistry"}})

  table.insert(fixture_prototypes, {
    type = "recipe",
    name = "mir-fixture-boundary-variant-candidate",
    enabled = true,
    allow_productivity = true,
    icon = "__base__/graphics/icons/iron-plate.png",
    icon_size = 64,
    normal = {
      ingredients = {{type = "item", name = "iron-plate", amount = 1}},
      results = {{type = "item", name = "battery", amount = 1}}
    },
    expensive = {
      ingredients = {{type = "item", name = "iron-plate", amount = 2}},
      results = {{type = "item", name = "battery", amount = 1}}
    }
  })

  boundary_recipe("mir-fixture-boundary-conversion-candidate",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "advanced-circuit", amount = 1}})
  boundary_recipe("mir-fixture-boundary-conversion-return",
    {{type = "item", name = "advanced-circuit", amount = 1}},
    {{type = "item", name = "advanced-circuit", amount = 1, independent_probability = 0.25}})
  boundary_recipe("mir-fixture-boundary-conversion-to-input",
    {{type = "item", name = "advanced-circuit", amount = 1}},
    {{type = "item", name = "iron-plate", amount = 1}})

  boundary_recipe("mir-fixture-boundary-nonstandard-candidate",
    {{type = "item", name = "copper-plate", amount = 1}},
    {{type = "item", name = nonstandard_item.name, amount = 1}})
  boundary_recipe("mir-fixture-boundary-nonstandard-return",
    {{type = "item", name = nonstandard_item.name, amount = 1}},
    {{type = "item", name = nonstandard_item.name, amount = 1, independent_probability = 0.10}})
end
if #fixture_prototypes > 0 then data:extend(fixture_prototypes) end
