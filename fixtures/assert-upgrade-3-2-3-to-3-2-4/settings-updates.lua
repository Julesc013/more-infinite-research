local values = {
  ["ips-cost-base-research_gears"] = {type = "int-setting", value = 4321},
  ["ips-cost-growth-research_gears"] = {type = "double-setting", value = 1.25},
  ["mir-cost-base-worker-robots-storage"] = {type = "int-setting", value = 2345},
  ["mir-cost-growth-worker-robots-storage"] = {type = "double-setting", value = 1.1}
}

for name, row in pairs(values) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting then error("missing 3.2.3 to 3.2.4 upgrade setting " .. name) end
  setting.default_value = row.value
end
