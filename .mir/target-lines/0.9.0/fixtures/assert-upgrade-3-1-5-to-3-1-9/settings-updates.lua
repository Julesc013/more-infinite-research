local values = {
  ["ips-enable-research_low_density_structure"] = {type = "bool-setting", value = true},
  ["ips-cost-base-research_low_density_structure"] = {type = "int-setting", value = 1234},
  ["ips-cost-growth-research_low_density_structure"] = {type = "double-setting", value = 1.7},
  ["ips-max-level-research_low_density_structure"] = {type = "int-setting", value = 0},
  ["ips-research-time-research_low_density_structure"] = {type = "int-setting", value = 77},
  ["ips-effect-per-level-research_low_density_structure"] = {type = "double-setting", value = 13}
}

for name, row in pairs(values) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting then error("missing native-owner startup setting " .. name) end
  setting.default_value = row.value
end
