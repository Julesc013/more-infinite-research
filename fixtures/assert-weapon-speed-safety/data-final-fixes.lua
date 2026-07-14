local function fail(message)
  error("MIR weapon speed validation failed: " .. message)
end

local techs = data.raw.technology or {}

local function has_gun_speed(tech, ammo_category)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "gun-speed" and effect.ammo_category == ammo_category then return true end
  end
  return false
end

local function gun_speed_modifier(tech, ammo_category)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "gun-speed" and effect.ammo_category == ammo_category then
      return tonumber(effect.modifier)
    end
  end
  return nil
end

local function has_prerequisite(tech, prerequisite)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local function recipe_outputs(recipe, item_name)
  if recipe.result == item_name then return true end
  for _, result in ipairs(recipe.results or {}) do
    if (result.name or result[1]) == item_name then return true end
  end
  return false
end

local function recipe_is_unlocked(recipe_name)
  for _, technology in pairs(techs) do
    if technology.enabled ~= false then
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "unlock-recipe" and effect.recipe == recipe_name then return true end
      end
    end
  end
  return false
end

local function pack_has_crafting_path(pack_name)
  for recipe_name, recipe in pairs(data.raw.recipe or {}) do
    if recipe_outputs(recipe, pack_name)
      and (recipe.enabled ~= false or recipe_is_unlocked(recipe_name))
    then
      return true
    end
  end
  return false
end

local function lab_accepts(pack_name)
  for _, lab in pairs(data.raw.lab or {}) do
    for _, input in ipairs(lab.inputs or {}) do
      if input == pack_name then return true end
    end
  end
  return false
end

local function technology_is_researchable_infinite(technology)
  if not technology or technology.enabled == false or technology.max_level ~= "infinite" then return false end
  if not technology.unit or not technology.unit.ingredients or #technology.unit.ingredients == 0 then return false end
  if technology.unit.count == nil and technology.unit.count_formula == nil then return false end
  for _, ingredient in ipairs(technology.unit.ingredients) do
    local pack_name = ingredient.name or ingredient[1]
    if not lab_accepts(pack_name) or not pack_has_crafting_path(pack_name) then return false end
  end
  return true
end

local function exact_infinite_owner(name, category)
  local technology = techs[name]
  return technology_is_researchable_infinite(technology)
    and gun_speed_modifier(technology, category) == 0.1
end

local dedicated_names = {
  rocket = "recipe-prod-research_rocket_shooting_speed-1",
  ["cannon-shell"] = "recipe-prod-research_cannon_shooting_speed-1"
}

local prefer_mir_setting = settings.startup["mir-prefer-this-mod-for-competing-techs"]
local prefer_mir = not prefer_mir_setting or prefer_mir_setting.value ~= false

local function replacement_coverage(category)
  local dedicated = techs[dedicated_names[category]]
  local dedicated_modifier = gun_speed_modifier(dedicated, category)
  if technology_is_researchable_infinite(dedicated) and dedicated_modifier and dedicated_modifier > 0 then return true end
  if prefer_mir then return false end
  for name, _ in pairs(techs) do
    if not string.match(name, "^recipe%-prod%-")
      and not string.match(name, "^weapon%-shooting%-speed%-%d+$")
      and exact_infinite_owner(name, category)
    then
      return true
    end
  end
  return false
end

for category, tech_name in pairs(dedicated_names) do
  local technology = techs[tech_name]
  if technology then
    local setting = settings.startup["ips-effect-per-level-research_" ..
      (category == "rocket" and "rocket" or "cannon") .. "_shooting_speed"]
    local expected = setting and tonumber(setting.value) and tonumber(setting.value) / 100 or 0.1
    local actual = gun_speed_modifier(technology, category)
    if not actual or math.abs(actual - expected) > 0.000001 then
      fail(tech_name .. " emitted " .. tostring(actual) .. " for " .. category
        .. ", expected selected value " .. tostring(expected))
    end
  end
end

for _, tech_name in ipairs({"weapon-shooting-speed-5", "weapon-shooting-speed-6"}) do
  if not has_gun_speed(techs[tech_name], "cannon-shell") then
    fail("finite vanilla " .. tech_name .. " lost cannon-shell shooting-speed")
  end
end

local mode_setting = settings.startup["mir-adjust-vanilla-weapon-speed-techs"]
local mode = mode_setting and mode_setting.value or "only-when-dedicated-tech-enabled"
local generated_count = 0
for name, tech in pairs(techs) do
  if name ~= "weapon-shooting-speed-99"
    and string.match(name, "^weapon%-shooting%-speed%-%d+$")
    and tech.unit
    and tech.unit.count_formula
  then
    generated_count = generated_count + 1
    for _, category in ipairs({"rocket", "cannon-shell"}) do
      local should_strip = mode == "always"
        or (mode == "only-when-dedicated-tech-enabled" and replacement_coverage(category))
      local present = has_gun_speed(tech, category)
      if should_strip and present then
        fail(name .. " retained " .. category .. " despite replacement coverage in mode " .. mode)
      elseif not should_strip and not present then
        fail(name .. " lost " .. category .. " without accepted replacement coverage in mode " .. mode)
      end
    end
  end
end
if generated_count == 0 then fail("generated weapon shooting speed continuation was not found") end

local expected_prerequisites = {
  ["recipe-prod-research_rocket_shooting_speed-1"] = {{"rocketry"}},
  ["recipe-prod-research_cannon_shooting_speed-1"] = {{"tank", "tanks"}, {"weapon-shooting-speed-5"}},
  ["recipe-prod-research_flamethrower_shooting_speed-1"] = {{"flamethrower"}},
  ["recipe-prod-research_electric_shooting_speed-1"] = {{"discharge-defense-equipment"}}
}

for tech_name, prerequisite_groups in pairs(expected_prerequisites) do
  local tech = techs[tech_name]
  if tech then
    for _, candidates in ipairs(prerequisite_groups) do
      local found = false
      for _, prerequisite in ipairs(candidates) do
        if has_prerequisite(tech, prerequisite) then found = true break end
      end
      if not found then fail(tech_name .. " is missing prerequisite candidate " .. table.concat(candidates, ",")) end
    end
  end
end

local external_owner = techs["mir-fixture-external-weapon-speed-owner"]
if external_owner then
  if prefer_mir then fail("external-owner scenario did not disable MIR ownership preference") end
  if techs[dedicated_names.rocket] or techs[dedicated_names["cannon-shell"]] then
    fail("MIR dedicated rocket or cannon technology was not suppressed by exact external coverage")
  end
  if not exact_infinite_owner("mir-fixture-external-weapon-speed-owner", "rocket")
    or not exact_infinite_owner("mir-fixture-external-weapon-speed-owner", "cannon-shell")
  then
    fail("external owner does not provide exact reachable infinite replacement coverage")
  end
  if technology_is_researchable_infinite(techs["mir-fixture-unreachable-weapon-speed-owner"]) then
    fail("science-unreachable external owner was accepted as replacement coverage")
  end
  local continuation = techs["weapon-shooting-speed-99"]
  if not has_gun_speed(continuation, "rocket") or not has_gun_speed(continuation, "cannon-shell") then
    fail("external numbered weapon shooting speed continuation was mutated")
  end
  techs["weapon-shooting-speed-99"] = nil
end
