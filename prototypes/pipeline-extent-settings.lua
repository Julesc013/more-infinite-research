local S = {}

S.default_value = "100"
S.allowed_values = {"50", "75", "100", "125", "150", "200", "250", "300", "400", "500"}

local multiplier_by_value = {
  ["50"] = 0.5,
  ["75"] = 0.75,
  ["100"] = 1,
  ["125"] = 1.25,
  ["150"] = 1.5,
  ["200"] = 2,
  ["250"] = 2.5,
  ["300"] = 3,
  ["400"] = 4,
  ["500"] = 5
}

local function startup_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

function S.parse(value)
  if value == nil then return 1 end

  local key = tostring(value)
  if multiplier_by_value[key] then return multiplier_by_value[key] end

  local numeric = tonumber(value)
  if not numeric or numeric <= 0 then return 1 end
  if numeric > 10 then return numeric / 100 end
  return numeric
end

function S.multiplier()
  return S.parse(startup_setting("mir-pipeline-extent-multiplier"))
end

return S
