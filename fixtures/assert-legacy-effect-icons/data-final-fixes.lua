local techs = data.raw.technology or {}

local direct_effect_technologies = {
  "recipe-prod-research_electric_shooting_speed-1",
  "recipe-prod-research_rocket_shooting_speed-1"
}

local forbidden_icon_prefixes = {
  "__core__/graphics/icons/technology/constants/",
  "__core__/graphics/icons/technology/effect-constant/",
  "__space-age__/"
}

local function fail(message)
  error("MIR validation failed: " .. message)
end

local function has_prefix(value, prefix)
  return type(value) == "string" and string.find(value, prefix, 1, true) == 1
end

local function has_synthetic_old_line_badge(layer)
  return layer
    and layer.scale == 0.42
    and layer.shift
    and layer.shift[1] == 44
    and layer.shift[2] == 44
    and layer.floating == true
end

local function assert_not_forbidden_icon_path(tech_name, icon)
  for _, prefix in ipairs(forbidden_icon_prefixes) do
    if has_prefix(icon, prefix) then
      fail("generated old-line technology " .. tech_name .. " uses unavailable newer badge icon " .. icon .. ".")
    end
  end
end

local function assert_no_unavailable_or_synthetic_badges(tech_name)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated old-line direct-effect technology " .. tech_name .. ".")
  end

  assert_not_forbidden_icon_path(tech_name, tech.icon)
  for _, layer in ipairs(tech.icons or {}) do
    assert_not_forbidden_icon_path(tech_name, layer.icon)
    if has_synthetic_old_line_badge(layer) then
      fail("generated old-line technology " .. tech_name .. " uses a synthetic target-era tile badge overlay.")
    end
  end

  for _, effect in ipairs(tech.effects or {}) do
    if effect.icon or effect.icons then
      fail("generated old-line technology " .. tech_name
        .. " emits unsupported native modifier icon metadata for " .. tostring(effect.type) .. ".")
    end
  end
end

for _, tech_name in ipairs(direct_effect_technologies) do
  assert_no_unavailable_or_synthetic_badges(tech_name)
end
