local values = {
  ["ips-enable-research_landfill"] = {type = "bool-setting", value = true},
  ["ips-cost-base-research_landfill"] = {type = "int-setting", value = 4321},
  ["ips-enable-research_ice"] = {type = "bool-setting", value = true},
  ["ips-cost-base-research_ice"] = {type = "int-setting", value = 2345}
}

for name, row in pairs(values) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting then error("missing 3.2.2 to 3.2.3 upgrade setting " .. name) end
  setting.default_value = row.value
end
