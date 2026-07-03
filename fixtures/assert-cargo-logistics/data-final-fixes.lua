local official_pack_order = {
  "automation-science-pack",
  "logistic-science-pack",
  "chemical-science-pack",
  "production-science-pack",
  "military-science-pack",
  "utility-science-pack",
  "space-science-pack",
  "agricultural-science-pack",
  "metallurgic-science-pack",
  "electromagnetic-science-pack",
  "cryogenic-science-pack",
  "promethium-science-pack"
}

local function technology(name)
  local tech = data.raw.technology and data.raw.technology[name]
  if not tech then
    error("MIR cargo validation failed: missing technology " .. name .. ".")
  end
  return tech
end

local function ingredient_name(ingredient)
  return ingredient and (ingredient.name or ingredient[1])
end

local function effect_modifier(effect)
  return effect and (effect.modifier or effect.change)
end

local function assert_has_effect(tech, effect_type, expected_modifier)
  for _, effect in ipairs(tech.effects or {}) do
    if effect.type == effect_type and effect_modifier(effect) == expected_modifier then
      return
    end
  end
  error("MIR cargo validation failed: " .. tech.name .. " missing effect " .. effect_type .. " = " .. tostring(expected_modifier) .. ".")
end

local function assert_has_prerequisite(tech, prerequisite)
  for _, current in ipairs(tech.prerequisites or {}) do
    if current == prerequisite then return end
  end
  error("MIR cargo validation failed: " .. tech.name .. " missing prerequisite " .. prerequisite .. ".")
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

local function assert_uses_technology_icon(tech, source_tech_name)
  local source = data.raw.technology and data.raw.technology[source_tech_name]
  local expected_paths = prototype_icon_paths(source)
  if not next(expected_paths) then
    error("MIR cargo validation failed: missing technology icon source for " .. source_tech_name .. ".")
  end

  for _, layer in ipairs(tech.icons or {}) do
    if expected_paths[layer.icon] then return end
  end

  error("MIR cargo validation failed: " .. tech.name .. " does not use " .. source_tech_name .. " technology art.")
end

local function assert_unit(tech, expected_formula, expected_time)
  if not tech.unit then
    error("MIR cargo validation failed: " .. tech.name .. " has no research unit.")
  end
  if tech.unit.count_formula ~= expected_formula then
    error("MIR cargo validation failed: " .. tech.name .. " count formula was " .. tostring(tech.unit.count_formula) .. ".")
  end
  if tech.unit.time ~= expected_time then
    error("MIR cargo validation failed: " .. tech.name .. " research time was " .. tostring(tech.unit.time) .. ".")
  end
end

local function available_official_science_packs()
  local official = {}
  for _, name in ipairs(official_pack_order) do official[name] = true end

  local available = {}
  for _, lab in pairs(data.raw.lab or {}) do
    for _, input in ipairs(lab.inputs or {}) do
      if official[input] and data.raw.item and data.raw.item[input] then
        available[input] = true
      end
    end
  end

  local out = {}
  for _, name in ipairs(official_pack_order) do
    if available[name] then table.insert(out, name) end
  end
  return out
end

local function assert_exact_official_science(tech)
  local expected = available_official_science_packs()
  if #expected < 8 then
    error("MIR cargo validation failed: Space Age official science pack set looked incomplete.")
  end

  local expected_set = {}
  for _, name in ipairs(expected) do expected_set[name] = true end

  local actual_set = {}
  local actual_count = 0
  for _, ingredient in ipairs((tech.unit and tech.unit.ingredients) or {}) do
    local name = ingredient_name(ingredient)
    if not expected_set[name] then
      error("MIR cargo validation failed: " .. tech.name .. " used unexpected science pack " .. tostring(name) .. ".")
    end
    actual_set[name] = true
    actual_count = actual_count + 1
  end

  if actual_count ~= #expected then
    error("MIR cargo validation failed: " .. tech.name .. " used " .. tostring(actual_count) .. " science packs, expected " .. tostring(#expected) .. ".")
  end

  for _, name in ipairs(expected) do
    if not actual_set[name] then
      error("MIR cargo validation failed: " .. tech.name .. " missing official science pack " .. name .. ".")
    end
  end
end

local function assert_common(tech, expected_formula, expected_time)
  if tech.max_level ~= "infinite" then
    error("MIR cargo validation failed: " .. tech.name .. " is not infinite.")
  end
  if tech.level ~= 1 then
    error("MIR cargo validation failed: " .. tech.name .. " starts at level " .. tostring(tech.level) .. ".")
  end
  assert_unit(tech, expected_formula, expected_time)
  assert_exact_official_science(tech)
end

local distance = technology("recipe-prod-research_cargo_bay_unloading_distance-1")
assert_common(distance, "100000 * 3^(L-1)", 120)
assert_has_effect(distance, "max-cargo-bay-unloading-distance", 10)
assert_has_prerequisite(distance, "landing-pad-unloading-bay")
assert_uses_technology_icon(distance, "landing-pad-unloading-bay")

local count = technology("recipe-prod-research_cargo_landing_pad_count-1")
assert_common(count, "1000000 * 10^(L-1)", 240)
assert_has_effect(count, "cargo-landing-pad-count", 1)
assert_has_prerequisite(count, "rocket-silo")
assert_uses_technology_icon(count, "space-platform")
