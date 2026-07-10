local function fail(message)
  error("MIR weapon speed validation failed: " .. message)
end

local function has_gun_speed(tech, ammo_category)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "gun-speed" and effect.ammo_category == ammo_category then
      return true
    end
  end
  return false
end

local function has_exact_gun_speed(tech, ammo_category)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "gun-speed"
      and effect.ammo_category == ammo_category
      and effect.modifier == 0.1
    then
      return true
    end
  end
  return false
end

local function has_prerequisite(tech, prerequisite)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local techs = data.raw.technology or {}

local function structurally_reachable(name, visiting, memo)
  if memo[name] ~= nil then return memo[name] end
  if visiting[name] then
    memo[name] = false
    return false
  end
  local tech = techs[name]
  if not tech or tech.enabled == false then
    memo[name] = false
    return false
  end
  visiting[name] = true
  for _, prerequisite in ipairs(tech.prerequisites or {}) do
    if not structurally_reachable(prerequisite, visiting, memo) then
      visiting[name] = nil
      memo[name] = false
      return false
    end
  end
  visiting[name] = nil
  memo[name] = true
  return true
end

local function exact_infinite_owner(name, category)
  local tech = techs[name]
  return tech ~= nil
    and tech.enabled ~= false
    and tech.max_level == "infinite"
    and tech.unit ~= nil
    and tech.unit.ingredients ~= nil
    and #tech.unit.ingredients > 0
    and (tech.unit.count ~= nil or tech.unit.count_formula ~= nil)
    and has_exact_gun_speed(tech, category)
    and structurally_reachable(name, {}, {})
end

local dedicated_names = {
  rocket = "recipe-prod-research_rocket_shooting_speed-1",
  ["cannon-shell"] = "recipe-prod-research_cannon_shooting_speed-1"
}

local prefer_mir_setting = settings.startup["mir-prefer-this-mod-for-competing-techs"]
local prefer_mir = not prefer_mir_setting or prefer_mir_setting.value ~= false

local function replacement_coverage(category)
  if exact_infinite_owner(dedicated_names[category], category) then return true end
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

for _, tech_name in ipairs({"weapon-shooting-speed-5", "weapon-shooting-speed-6"}) do
  if not has_gun_speed(techs[tech_name], "cannon-shell") then
    fail("finite vanilla " .. tech_name .. " lost cannon-shell shooting-speed")
  end
end

local mode_setting = settings.startup["mir-adjust-vanilla-weapon-speed-techs"]
local mode = mode_setting and mode_setting.value or "only-when-dedicated-tech-enabled"
local generated_count = 0
for name, tech in pairs(techs) do
  if string.match(name, "^weapon%-shooting%-speed%-%d+$") and tech.unit and tech.unit.count_formula then
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
if generated_count == 0 then
  fail("generated weapon shooting speed continuation was not found")
end

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
        if has_prerequisite(tech, prerequisite) then
          found = true
          break
        end
      end
      if not found then
        fail(tech_name .. " is missing prerequisite candidate " .. table.concat(candidates, ","))
      end
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
end
