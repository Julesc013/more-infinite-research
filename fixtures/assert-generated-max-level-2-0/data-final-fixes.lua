local technologies = {
  "recipe-prod-research_processing_unit-1",
  "recipe-prod-research_plastic-1",
  "recipe-prod-research_low_density_structure-1",
  "recipe-prod-research_rocket_fuel-1",
  "recipe-prod-research_steel-1"
}

local setting_names = {
  "ips-max-level-research_processing_unit",
  "ips-max-level-research_plastic",
  "ips-max-level-research_low_density_structure",
  "ips-max-level-research_rocket_fuel",
  "ips-max-level-research_steel"
}

local expected_maximum = settings.startup[setting_names[1]].value
for _, setting_name in ipairs(setting_names) do
  if settings.startup[setting_name].value ~= expected_maximum then
    error("MIR Factorio 2.0 maximum-level fixture requires one shared family cap")
  end
end

local function contains(value, expected)
  if tostring(value) == tostring(expected) then return true end
  if type(value) ~= "table" then return false end
  for _, child in pairs(value) do if contains(child, expected) then return true end end
  return false
end

for _, name in ipairs(technologies) do
  local technology = data.raw.technology[name]
  if not technology then error("MIR Factorio 2.0 maximum-level fixture is missing " .. name) end
  if technology.max_level ~= "infinite" then
    error("MIR Factorio 2.0 maximum-level fixture requires a lossless infinite prototype for " .. name)
  end
  if expected_maximum == 0 then
    if technology.show_levels_info == false then
      error("MIR Factorio 2.0 infinite fixture hides native level information for " .. name)
    end
  else
    if technology.show_levels_info ~= false then
      error("MIR Factorio 2.0 maximum-level fixture still exposes infinity for " .. name)
    end
    if not contains(technology.localised_description, expected_maximum) then
      error("MIR Factorio 2.0 maximum-level fixture does not disclose maximum "
        .. tostring(expected_maximum) .. " for " .. name)
    end
  end
end
