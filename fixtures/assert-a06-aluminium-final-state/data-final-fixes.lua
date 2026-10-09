local function profile()
  if mods.bobplates and mods.angelssmelting then return "combined" end
  if mods.bobplates then return "bob" end
  if mods.angelssmelting then return "angel" end
  return "unsupported"
end

local function bool(value)
  if value == nil then return "nil" end
  return value and "true" or "false"
end

local function sorted_keys(values)
  local out = {}
  for key in pairs(values or {}) do table.insert(out, key) end
  table.sort(out)
  return out
end

local function joined(values)
  return table.concat(values or {}, ",")
end

local function aluminium_name(value)
  local lower = string.lower(value or "")
  return string.find(lower, "aluminium", 1, true) ~= nil or string.find(lower, "aluminum", 1, true) ~= nil
end

local function entries(values, fallback_name, fallback_amount)
  local out = {}
  if values then
    for _, value in pairs(values) do
      local name = value.name or value[1]
      if name then
        table.insert(out, table.concat({
          value.type or "item", name, tostring(value.amount or value[2] or "nil"),
          tostring(value.amount_min or "nil"), tostring(value.amount_max or "nil"),
          tostring(value.probability or "nil"), tostring(value.ignored_by_productivity or "nil")
        }, ":"))
      end
    end
  elseif fallback_name then
    table.insert(out, table.concat({"item", fallback_name, tostring(fallback_amount or 1), "nil", "nil", "nil", "nil"}, ":"))
  end
  table.sort(out)
  return out
end

local function recipe_products(recipe)
  return entries(recipe.results, recipe.result, recipe.result_count)
end

local function mentions_material(entry_values, material_names)
  for _, value in pairs(entry_values or {}) do
    local name = value.name or value[1]
    if material_names[name] then return true end
  end
  return false
end

local function effect_values(effects)
  local out = {}
  for _, effect in pairs(effects or {}) do
    table.insert(out, table.concat({
      tostring(effect.type or "nil"), tostring(effect.recipe or "nil"),
      tostring(effect.modifier or "nil"), tostring(effect.unlock_formula or "nil")
    }, ":"))
  end
  table.sort(out)
  return out
end

local p = profile()
local material_names = {}
for _, prototype_type in ipairs({"item", "fluid"}) do
  for name in pairs(data.raw[prototype_type] or {}) do
    if aluminium_name(name) then material_names[name] = true end
  end
end

local recipe_names, recipe_categories = {}, {}
for name, recipe in pairs(data.raw.recipe or {}) do
  local products = recipe.results or (recipe.result and {{name = recipe.result, amount = recipe.result_count or 1}}) or {}
  if aluminium_name(name) or mentions_material(recipe.ingredients, material_names) or mentions_material(products, material_names) then
    recipe_names[name] = true
    for _, category in pairs(recipe.categories or (recipe.category and {recipe.category}) or {"crafting"}) do recipe_categories[category] = true end
  end
end

log("[mir-a06-aluminium] PROFILE name=" .. p .. " bobplates=" .. bool(mods.bobplates ~= nil) .. " angelssmelting=" .. bool(mods.angelssmelting ~= nil))
for _, prototype_type in ipairs({"item", "fluid"}) do
  for _, name in ipairs(sorted_keys(data.raw[prototype_type] or {})) do
    local prototype = data.raw[prototype_type][name]
    if material_names[name] then
      log("[mir-a06-aluminium] ITEM type=" .. prototype_type .. " name=" .. name .. " hidden=" .. bool(prototype.hidden) .. " subgroup=" .. tostring(prototype.subgroup or "nil"))
    end
  end
end

for _, name in ipairs(sorted_keys(recipe_names)) do
  local recipe = data.raw.recipe[name]
  local categories = recipe.categories or (recipe.category and {recipe.category}) or {"crafting"}
  log("[mir-a06-aluminium] RECIPE name=" .. name
    .. " enabled=" .. bool(recipe.enabled)
    .. " hidden=" .. bool(recipe.hidden)
    .. " categories=" .. joined(categories)
    .. " ingredients=" .. joined(entries(recipe.ingredients))
    .. " products=" .. joined(recipe_products(recipe))
    .. " allow_productivity=" .. bool(recipe.allow_productivity)
    .. " auto_recycle=" .. bool(recipe.auto_recycle))
end

for _, category in ipairs(sorted_keys(recipe_categories)) do
  local machines = {}
  for _, prototype_type in ipairs({"assembling-machine", "furnace", "rocket-silo"}) do
    for name, machine in pairs(data.raw[prototype_type] or {}) do
      for _, machine_category in pairs(machine.crafting_categories or {}) do
        if machine_category == category then table.insert(machines, prototype_type .. ":" .. name) end
      end
    end
  end
  table.sort(machines)
  log("[mir-a06-aluminium] MACHINE_CATEGORY category=" .. category .. " machines=" .. joined(machines))
end

local technology_names = { ["recipe-prod-research_material_aluminium-1"] = true }
for name, technology in pairs(data.raw.technology or {}) do
  if aluminium_name(name) then technology_names[name] = true end
  for _, effect in pairs(technology.effects or {}) do
    if effect.recipe and recipe_names[effect.recipe] then technology_names[name] = true end
  end
end

local native_owners, mir_owners = {}, {}
for _, name in ipairs(sorted_keys(technology_names)) do
  local technology = data.raw.technology[name]
  if technology then
    local science = entries(technology.unit and technology.unit.ingredients or {})
    log("[mir-a06-aluminium] TECHNOLOGY name=" .. name
      .. " enabled=" .. bool(technology.enabled)
      .. " hidden=" .. bool(technology.hidden)
      .. " prerequisites=" .. joined(technology.prerequisites or {})
      .. " science=" .. joined(science)
      .. " effects=" .. joined(effect_values(technology.effects)))
  end
end
for technology_name, technology in pairs(data.raw.technology or {}) do
  for _, effect in pairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and recipe_names[effect.recipe] then
      local row = technology_name .. ":" .. effect.recipe
      if string.find(technology_name, "^recipe%-prod%-research_material_aluminium") then
        table.insert(mir_owners, row)
      else
        table.insert(native_owners, row)
      end
    end
  end
end
table.sort(native_owners); table.sort(mir_owners)
log("[mir-a06-aluminium] OWNERS native=" .. joined(native_owners) .. " mir=" .. joined(mir_owners))
local stream = data.raw.technology["recipe-prod-research_material_aluminium-1"]
log("[mir-a06-aluminium] MATCHING stream=research_material_aluminium technology_present=" .. bool(stream ~= nil) .. " compiler_rows=inspect-more-infinite-research-generation-report")
log("[mir-a06-aluminium] SUMMARY items=" .. tostring(#sorted_keys(material_names)) .. " recipes=" .. tostring(#sorted_keys(recipe_names)) .. " technologies=" .. tostring(#sorted_keys(technology_names)) .. " observer=read-only-no-admission")
local function list_equal(actual, expected)
  if #actual ~= #expected then return false end
  for index, value in ipairs(expected) do
    if actual[index] ~= value then return false end
  end
  return true
end

local function sorted_values(values)
  local out = {}
  for _, value in pairs(values or {}) do table.insert(out, value) end
  table.sort(out)
  return out
end

local function ingredient_names(values)
  local out = {}
  for _, value in pairs(values or {}) do
    local name = value.name or value[1]
    if name then table.insert(out, name) end
  end
  table.sort(out)
  return out
end

local function structural_equal(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do
    if not structural_equal(value, right[key]) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

local expected = {
  bob = {
    item = "bob-aluminium-plate",
    effects = {"bob-aluminium-plate"},
    withheld = {},
    prerequisites = {"automation-science-pack", "bob-aluminium-processing", "logistic-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack"},
    permission_unset_intermediates = {}
  },
  angel = {
    item = "angels-plate-aluminium",
    effects = {"angels-plate-aluminium", "angels-plate-aluminium-2"},
    withheld = {},
    prerequisites = {"angels-aluminium-casting-2", "angels-aluminium-smelting-1", "automation-science-pack", "chemical-science-pack", "logistic-science-pack"},
    science = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack"},
    permission_unset_intermediates = {"angels-ingot-aluminium", "angels-liquid-molten-aluminium", "angels-roll-aluminium"}
  }
}

local function has_entry(values, expected_value)
  for _, value in ipairs(values or {}) do
    if value == expected_value then return true end
  end
  return false
end

local function productivity_owners(recipe_name)
  local owners = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    for _, effect in pairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
        table.insert(owners, technology_name .. ":" .. tostring(effect.change))
      end
    end
  end
  table.sort(owners)
  return owners
end

local function assert_item_presentation(technology, item_name)
  local item = data.raw.item[item_name]
  if not item then error("[mir-a06-aluminium] expected presentation item is absent: " .. item_name) end
  local expected_localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name." .. item_name}}
  if not structural_equal(technology.localised_name, expected_localised_name) then
    error("[mir-a06-aluminium] localisation does not select expected item: " .. item_name)
  end
  local base_icons = item.icons or (item.icon and {{icon = item.icon, icon_size = item.icon_size or 64}}) or nil
  if not base_icons or not technology.icons or #technology.icons < #base_icons then
    error("[mir-a06-aluminium] icon does not select expected item: " .. item_name)
  end
  for index, layer in ipairs(base_icons) do
    local actual = technology.icons[index]
    if not actual or actual.icon ~= layer.icon then
      error("[mir-a06-aluminium] icon layer does not select expected item: " .. item_name)
    end
  end
end

local technology_name = "recipe-prod-research_material_aluminium-1"
local combined_withheld = {
  routes = {"bob-aluminium-plate", "angels-plate-aluminium", "angels-plate-aluminium-2"},
  angel_permission_enabled = {"angels-plate-aluminium", "angels-plate-aluminium-2"},
  angel_permission_unset = {"angels-ingot-aluminium", "angels-liquid-molten-aluminium", "angels-roll-aluminium"}
}

local function assert_ownerless(recipe_name, description)
  if #productivity_owners(recipe_name) ~= 0 then
    error("[mir-a06-aluminium] " .. description .. " acquired productivity: " .. recipe_name)
  end
end

local function assert_combined_withheld()
  if data.raw.technology[technology_name] ~= nil then
    error("[mir-a06-aluminium] combined withheld profile unexpectedly emitted stable Aluminium technology")
  end
  local bob_route = data.raw.recipe["bob-aluminium-plate"]
  if not bob_route or bob_route.hidden ~= true then
    error("[mir-a06-aluminium] combined Bob route is not hidden")
  end
  for _, recipe_name in ipairs(combined_withheld.routes) do
    local recipe = data.raw.recipe[recipe_name]
    if not recipe then
      error("[mir-a06-aluminium] combined withheld route is absent: " .. recipe_name)
    end
    assert_ownerless(recipe_name, "combined withheld route")
  end
  for _, recipe_name in ipairs(combined_withheld.angel_permission_enabled) do
    local recipe = data.raw.recipe[recipe_name]
    if not recipe or recipe.allow_productivity ~= true then
      error("[mir-a06-aluminium] combined Angel route no longer has explicit productivity permission: " .. recipe_name)
    end
  end
  for _, recipe_name in ipairs(combined_withheld.angel_permission_unset) do
    local recipe = data.raw.recipe[recipe_name]
    if not recipe or recipe.allow_productivity ~= nil then
      error("[mir-a06-aluminium] combined permission-unset intermediate differs: " .. recipe_name)
    end
    assert_ownerless(recipe_name, "combined permission-unset intermediate")
  end
  log("[mir-a06-aluminium] ASSERTION profile=combined status=withheld technology=absent"
    .. " routes=" .. joined(combined_withheld.routes)
    .. " owners=none hidden=bob-aluminium-plate"
    .. " permission-enabled=" .. joined(combined_withheld.angel_permission_enabled)
    .. " permission-unset=" .. joined(combined_withheld.angel_permission_unset)
    .. " presentation=omitted progression=omitted")
end

local contract = expected[p]
if p == "combined" then
  assert_combined_withheld()
elseif contract then
  local technology = data.raw.technology[technology_name]
  if not technology then error("[mir-a06-aluminium] expected stable Aluminium technology is absent") end
  assert_item_presentation(technology, contract.item)

  local actual_effects = {}
  for _, effect in pairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" then
      if effect.change ~= 0.02 then error("[mir-a06-aluminium] Aluminium effect magnitude differs") end
      table.insert(actual_effects, effect.recipe)
    end
  end
  table.sort(actual_effects)
  if not list_equal(actual_effects, contract.effects) then
    error("[mir-a06-aluminium] exact Aluminium effect routes differ")
  end

  local actual_prerequisites = sorted_values(technology.prerequisites)
  local actual_science = ingredient_names(technology.unit and technology.unit.ingredients)
  if not list_equal(actual_prerequisites, contract.prerequisites) then
    error("[mir-a06-aluminium] exact Aluminium prerequisites differ")
  end
  if not list_equal(actual_science, contract.science) then
    error("[mir-a06-aluminium] exact Aluminium science differs")
  end

  for _, recipe_name in ipairs(contract.effects) do
    local owners = productivity_owners(recipe_name)
    if not list_equal(owners, {technology_name .. ":0.02"}) then
      error("[mir-a06-aluminium] Aluminium route does not have exactly one MIR owner: " .. recipe_name)
    end
  end
  for _, recipe_name in ipairs(contract.withheld) do
    local recipe = data.raw.recipe[recipe_name]
    if not recipe or recipe.hidden ~= true then
      error("[mir-a06-aluminium] combined Bob route is not hidden: " .. recipe_name)
    end
    if #productivity_owners(recipe_name) ~= 0 then
      error("[mir-a06-aluminium] combined hidden Bob route acquired productivity: " .. recipe_name)
    end
  end
  for _, recipe_name in ipairs(contract.permission_unset_intermediates) do
    local recipe = data.raw.recipe[recipe_name]
    if not recipe or recipe.allow_productivity ~= nil then
      error("[mir-a06-aluminium] expected permission-unset intermediate differs: " .. recipe_name)
    end
    if #productivity_owners(recipe_name) ~= 0 then
      error("[mir-a06-aluminium] permission-unset intermediate acquired productivity: " .. recipe_name)
    end
  end
  log("[mir-a06-aluminium] ASSERTION profile=" .. p
    .. " item=" .. contract.item
    .. " effects=" .. joined(actual_effects)
    .. " prerequisites=" .. joined(actual_prerequisites)
    .. " science=" .. joined(actual_science)
    .. " sole-mir-owner=" .. technology_name
    .. " withheld=" .. joined(contract.withheld)
    .. " permission-unset=" .. joined(contract.permission_unset_intermediates))
end
