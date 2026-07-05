local R = {}

local function same_number(a, b)
  local left = tonumber(a)
  local right = tonumber(b)
  if not left or not right then return false end
  return math.abs(left - right) < 0.000000001
end

local function same_value(actual, expected)
  if type(expected) == "number" then
    return same_number(actual, expected)
  end
  return actual == expected
end

local function effect_matches(effect, requirement)
  for field, expected in pairs(requirement or {}) do
    if field ~= "technology" and field ~= "max_level" then
      if not same_value(effect[field], expected) then
        return false
      end
    end
  end
  return true
end

function R.technology_effect_requirement_matches(requirement)
  if not requirement or not requirement.technology then return false end

  local tech = data.raw.technology and data.raw.technology[requirement.technology]
  if not tech then return false end
  if requirement.max_level ~= nil and tech.max_level ~= requirement.max_level then return false end

  for _, effect in ipairs(tech.effects or {}) do
    if effect_matches(effect, requirement) then return true end
  end
  return false
end

function R.skip_reason(spec)
  for _, tech_name in ipairs(spec.skip_if_technologies or {}) do
    if data.raw.technology and data.raw.technology[tech_name] then
      return "existing technology " .. tech_name
    end
  end

  for _, requirement in ipairs(spec.skip_if_technology_effects or {}) do
    if R.technology_effect_requirement_matches(requirement) then
      return "existing technology effect " .. requirement.technology .. " " .. tostring(requirement.type)
    end
  end

  return nil
end

return R
