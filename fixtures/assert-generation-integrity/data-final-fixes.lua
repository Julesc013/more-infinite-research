local techs = data.raw.technology or {}
local recipes = data.raw.recipe or {}
local is_space_age = mods and mods["space-age"] ~= nil

local function fail(message)
  error("MIR validation failed: " .. message)
end

local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

local function has_prerequisite(tech, prerequisite)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local function startup_setting_bool(name, fallback)
  local setting = settings and settings.startup and settings.startup[name]
  if setting and setting.value ~= nil then return setting.value == true end
  return fallback == true
end

local function sorted_csv(values)
  table.sort(values)
  return table.concat(values, ", ")
end

local function chain_levels(key)
  local pattern = "^" .. escape_pattern(key) .. "%-(%d+)$"
  local finite = {}
  local infinite = {}

  for name, tech in pairs(techs) do
    local level = tonumber(string.match(name, pattern))
    if level then
      local row = {
        name = name,
        level = level,
        tech = tech
      }
      if tech.max_level == "infinite" then
        table.insert(infinite, row)
      else
        table.insert(finite, row)
      end
    end
  end

  table.sort(finite, function(a, b) return a.level < b.level end)
  table.sort(infinite, function(a, b) return a.level < b.level end)
  return finite, infinite
end

local function assert_chain_extended_once(key)
  local finite, infinite = chain_levels(key)
  if #finite == 0 then
    fail("expected vanilla chain " .. key .. " to have finite levels before MIR extends it.")
  end
  if #infinite ~= 1 then
    local names = {}
    for _, row in ipairs(infinite) do table.insert(names, row.name) end
    fail("expected vanilla chain " .. key .. " to have exactly one infinite continuation; got "
      .. tostring(#infinite) .. " (" .. sorted_csv(names) .. ").")
  end

  local base = finite[#finite]
  local generated = infinite[1]
  local expected_name = key .. "-" .. tostring(base.level + 1)
  if generated.name ~= expected_name then
    fail("expected vanilla chain " .. key .. " to continue as " .. expected_name .. ", got " .. generated.name .. ".")
  end

  if not generated.tech.unit or not generated.tech.unit.count_formula then
    fail("generated continuation " .. generated.name .. " does not use an infinite count formula.")
  end
  if generated.tech.upgrade ~= true then
    fail("generated continuation " .. generated.name .. " is not marked as an upgrade.")
  end
  if not has_prerequisite(generated.tech, base.name) then
    fail("generated continuation " .. generated.name .. " does not depend on prior finite level " .. base.name .. ".")
  end
  if not generated.tech.effects or #generated.tech.effects == 0 then
    fail("generated continuation " .. generated.name .. " has no effects.")
  end
end

local function assert_chain_not_extended(key)
  local _, infinite = chain_levels(key)
  if #infinite > 0 then
    local names = {}
    for _, row in ipairs(infinite) do table.insert(names, row.name) end
    fail("expected disabled vanilla chain " .. key .. " to have no MIR infinite continuation; got " .. sorted_csv(names) .. ".")
  end
end

local base_extension_defaults = {
  ["braking-force"] = true,
  ["research-speed"] = true,
  ["worker-robots-storage"] = true,
  ["inserter-capacity-bonus"] = false,
  ["weapon-shooting-speed"] = true,
  ["laser-shooting-speed"] = true
}

for key, default_enabled in pairs(base_extension_defaults) do
  if startup_setting_bool("mir-enable-" .. key, default_enabled) then
    assert_chain_extended_once(key)
  else
    assert_chain_not_extended(key)
  end
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function recipe_productivity_owners(recipe_name)
  local owners = {}
  for tech_name, tech in pairs(techs) do
    if tech.max_level == "infinite" and has_recipe_productivity_effect(tech, recipe_name) then
      table.insert(owners, tech_name)
    end
  end
  table.sort(owners)
  return owners
end

local constant_overlay_by_kind = {
  ["recipe-productivity"] = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
  speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["movement-speed"] = "__core__/graphics/icons/technology/constants/constant-movement-speed.png",
  mining = "__core__/graphics/icons/technology/constants/constant-mining.png",
  capacity = "__core__/graphics/icons/technology/constants/constant-capacity.png",
  damage = "__core__/graphics/icons/technology/constants/constant-damage.png",
  range = "__core__/graphics/icons/technology/constants/constant-range.png",
  ["braking-force"] = "__core__/graphics/icons/technology/constants/constant-braking-force.png",
  equipment = "__core__/graphics/icons/technology/constants/constant-equipment.png",
  count = "__core__/graphics/icons/technology/constants/constant-count.png"
}

local function expected_icon_badge(tech)
  local saw_recipe_productivity = false
  for _, effect in ipairs((tech and tech.effects) or {}) do
    local effect_type = effect.type
    if effect_type == "change-recipe-productivity" then
      saw_recipe_productivity = true
    elseif effect_type == "gun-speed" or effect_type == "character-crafting-speed" then
      return "speed"
    elseif effect_type == "character-running-speed" then
      return "movement-speed"
    elseif effect_type == "character-mining-speed" then
      return "mining"
    elseif effect_type == "character-reach-distance"
      or effect_type == "character-build-distance"
      or effect_type == "character-resource-reach-distance"
      or effect_type == "character-item-drop-distance" then
      return "range"
    elseif effect_type == "character-inventory-slots-bonus"
      or effect_type == "character-logistic-trash-slots"
      or effect_type == "worker-robot-battery" then
      return "capacity"
    elseif effect_type == "max-cargo-bay-unloading-distance" then
      return "range"
    elseif effect_type == "cargo-landing-pad-count" then
      return "count"
    elseif effect_type == "braking-force" then
      return "braking-force"
    elseif effect_type == "ammo-damage" or effect_type == "turret-attack" then
      return "damage"
    end
  end

  if saw_recipe_productivity then return "recipe-productivity" end
  return nil
end

local function icon_constant_kinds(tech)
  local kinds = {}
  for _, layer in ipairs((tech and tech.icons) or {}) do
    for kind, icon_path in pairs(constant_overlay_by_kind) do
      if layer.icon == icon_path then
        kinds[kind] = true
      end
    end
  end
  return kinds
end

local function assert_generated_icon_badge(tech_name, tech)
  local expected = expected_icon_badge(tech)
  if not expected then return end

  if not tech.icons or #tech.icons == 0 then
    fail("generated technology " .. tech_name .. " has no icon layers.")
  end

  local kinds = icon_constant_kinds(tech)
  if not kinds[expected] then
    fail("generated technology " .. tech_name .. " is missing expected " .. expected .. " icon badge.")
  end

  for kind, _ in pairs(kinds) do
    if kind ~= expected then
      fail("generated technology " .. tech_name .. " has unexpected " .. kind
        .. " icon badge; expected only " .. expected .. ".")
    end
  end
end

local function prototype_icon_paths(prototype)
  local paths = {}
  if not prototype then return paths end
  if prototype.icons then
    for _, layer in ipairs(prototype.icons) do
      if layer.icon then paths[layer.icon] = true end
    end
  elseif prototype.icon then
    paths[prototype.icon] = true
  end
  return paths
end

local function assert_tech_uses_item_icon(tech_name, item_name)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated technology " .. tech_name .. " for icon assertion.")
  end

  local item = (data.raw.item or {})[item_name] or (data.raw.ammo or {})[item_name]
  local expected_paths = prototype_icon_paths(item)
  if not next(expected_paths) then
    fail("missing item icon source for " .. item_name .. ".")
  end

  for _, layer in ipairs(tech.icons or {}) do
    if expected_paths[layer.icon] then return end
  end

  fail("generated technology " .. tech_name .. " does not use " .. item_name .. " item art.")
end

local function assert_tech_uses_technology_icon(tech_name, source_tech_name)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated technology " .. tech_name .. " for icon assertion.")
  end

  local source = techs[source_tech_name]
  local expected_paths = prototype_icon_paths(source)
  if not next(expected_paths) then
    fail("missing technology icon source for " .. source_tech_name .. ".")
  end

  for _, layer in ipairs(tech.icons or {}) do
    if expected_paths[layer.icon] then return end
  end

  fail("generated technology " .. tech_name .. " does not use " .. source_tech_name .. " technology art.")
end

local owners_by_recipe = {}
for tech_name, tech in pairs(techs) do
  if string.match(tech_name, "^recipe%-prod%-") then
    if tech.max_level ~= "infinite" then
      fail("generated stream technology " .. tech_name .. " is not infinite.")
    end
    if not tech.unit or not tech.unit.count_formula then
      fail("generated stream technology " .. tech_name .. " does not use an infinite count formula.")
    end
    if tech.upgrade ~= true then
      fail("generated stream technology " .. tech_name .. " is not marked as an upgrade.")
    end
    if not tech.effects or #tech.effects == 0 then
      fail("generated stream technology " .. tech_name .. " has no effects.")
    end
    assert_generated_icon_badge(tech_name, tech)
  end

  if tech.max_level == "infinite" then
    local owner_recipes = {}
    for _, effect in ipairs(tech.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe then
        owner_recipes[effect.recipe] = true
      end
    end
    for recipe_name, _ in pairs(owner_recipes) do
      owners_by_recipe[recipe_name] = owners_by_recipe[recipe_name] or {}
      table.insert(owners_by_recipe[recipe_name], tech_name)
    end
  end
end

assert_tech_uses_item_icon("recipe-prod-research_heavy_ammo-1", "cannon-shell")
assert_tech_uses_item_icon("recipe-prod-research_cannon_shooting_speed-1", "cannon-shell")

for recipe_name, owners in pairs(owners_by_recipe) do
  table.sort(owners)
  if #owners > 1 then
    fail("recipe " .. recipe_name .. " has multiple infinite productivity owners: " .. table.concat(owners, ", "))
  end
end

local function assert_recipe_owner(recipe_name, expected_owner)
  if not recipes[recipe_name] then return end

  local owner = techs[expected_owner]
  if not owner or owner.max_level ~= "infinite" then
    fail("missing expected infinite productivity owner " .. expected_owner .. " for recipe " .. recipe_name .. ".")
  end
  if not has_recipe_productivity_effect(owner, recipe_name) then
    fail("expected owner " .. expected_owner .. " does not cover recipe " .. recipe_name .. ".")
  end

  local owners = recipe_productivity_owners(recipe_name)
  if #owners ~= 1 or owners[1] ~= expected_owner then
    fail("recipe " .. recipe_name .. " should have exactly one infinite productivity owner. Expected "
      .. expected_owner .. ", got: " .. table.concat(owners, ", "))
  end
end

for _, expectation in ipairs({
  { recipe = "electronic-circuit", owner = "recipe-prod-research_electronic_circuit-1" },
  { recipe = "advanced-circuit", owner = "recipe-prod-research_advanced_circuit-1" }
}) do
  assert_recipe_owner(expectation.recipe, expectation.owner)
end

if is_space_age then
  if techs["recipe-prod-research_agricultural_growth_speed-1"] then
    assert_tech_uses_technology_icon("recipe-prod-research_agricultural_growth_speed-1", "agriculture")
  end

  for _, tech_name in ipairs({
    "recipe-prod-research_processing_unit-1",
    "recipe-prod-research_low_density_structure-1",
    "recipe-prod-research_plastic-1",
    "recipe-prod-research_rocket_fuel-1"
  }) do
    if techs[tech_name] then
      fail("Space Age should not create parallel MIR productivity technology " .. tech_name .. ".")
    end
  end

  for _, expectation in ipairs({
    { recipe = "processing-unit", owner = "processing-unit-productivity" },
    { recipe = "low-density-structure", owner = "low-density-structure-productivity" },
    { recipe = "casting-low-density-structure", owner = "low-density-structure-productivity" },
    { recipe = "plastic-bar", owner = "plastic-bar-productivity" },
    { recipe = "bioplastic", owner = "plastic-bar-productivity" },
    { recipe = "rocket-fuel", owner = "rocket-fuel-productivity" },
    { recipe = "rocket-fuel-from-jelly", owner = "rocket-fuel-productivity" },
    { recipe = "ammonia-rocket-fuel", owner = "rocket-fuel-productivity" }
  }) do
    assert_recipe_owner(expectation.recipe, expectation.owner)
  end
else
  for _, expectation in ipairs({
    { recipe = "processing-unit", owner = "recipe-prod-research_processing_unit-1" },
    { recipe = "low-density-structure", owner = "recipe-prod-research_low_density_structure-1" },
    { recipe = "plastic-bar", owner = "recipe-prod-research_plastic-1" },
    { recipe = "rocket-fuel", owner = "recipe-prod-research_rocket_fuel-1" }
  }) do
    assert_recipe_owner(expectation.recipe, expectation.owner)
  end
end
