local values = {
  ["ips-enable-research_low_density_structure"] = {type = "bool-setting", value = true},
  ["ips-cost-base-research_low_density_structure"] = {type = "int-setting", value = 2000},
  ["ips-cost-growth-research_low_density_structure"] = {type = "double-setting", value = 2},
  ["ips-max-level-research_low_density_structure"] = {type = "int-setting", value = 0},
  ["ips-research-time-research_low_density_structure"] = {type = "int-setting", value = 60},
  ["ips-effect-per-level-research_low_density_structure"] = {type = "double-setting", value = 10}
}

for name, row in pairs(values) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting then error("missing native-owner startup setting " .. name) end
  setting.default_value = row.value
end
