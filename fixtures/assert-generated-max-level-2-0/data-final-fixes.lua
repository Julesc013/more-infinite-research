local technologies = {
  "recipe-prod-research_processing_unit-1",
  "recipe-prod-research_plastic-1",
  "recipe-prod-research_low_density_structure-1",
  "recipe-prod-research_rocket_fuel-1",
  "recipe-prod-research_steel-1"
}

for _, name in ipairs(technologies) do
  local technology = data.raw.technology[name]
  if not technology then error("MIR Factorio 2.0 maximum-level fixture is missing " .. name) end
  if technology.max_level ~= "infinite" then
    error("MIR Factorio 2.0 maximum-level fixture requires a lossless infinite prototype for " .. name)
  end
end
