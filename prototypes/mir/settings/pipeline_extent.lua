local S = {}

S.default_value = "100"
S.allowed_values = {"1000", "750", "500", "400", "300", "250", "200", "150", "125", "100", "75", "50", "25"}

local multiplier_by_value = {
  ["25"] = 0.25,
  ["50"] = 0.5,
  ["75"] = 0.75,
  ["100"] = 1,
  ["125"] = 1.25,
  ["150"] = 1.5,
  ["200"] = 2,
  ["250"] = 2.5,
  ["300"] = 3,
  ["400"] = 4,
  ["500"] = 5,
  ["750"] = 7.5,
  ["1000"] = 10
}

function S.parse(value)
  if value == nil then return 1 end

  -- Portable profiles may provide a validated numeric percentage outside the
  -- curated dropdown. Factorio's registered string setting remains a dropdown.
  if type(value) == "number" then return value / 100 end

  local key = tostring(value)
  if multiplier_by_value[key] then return multiplier_by_value[key] end

  local numeric = tonumber(value)
  if not numeric or numeric <= 0 then return 1 end
  if numeric > 10 then return numeric / 100 end
  return numeric
end

function S.multiplier(value)
  return S.parse(value)
end

return S
