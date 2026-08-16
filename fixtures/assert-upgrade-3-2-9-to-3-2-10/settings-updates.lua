local selector = data.raw["string-setting"] and data.raw["string-setting"]["mir-upgrade-archetype"]
if not selector then error("missing mir-upgrade-archetype selector") end

local values = {
  ["ips-cost-base-research_gears"] = {type = "int-setting", value = 4321},
  ["ips-cost-growth-research_gears"] = {type = "double-setting", value = 1.25},
  ["mir-cost-base-worker-robots-storage"] = {type = "int-setting", value = 2345},
  ["mir-cost-growth-worker-robots-storage"] = {type = "double-setting", value = 1.1}
}

if selector.default_value == "space-age-native-owner" then
  values["ips-enable-research_low_density_structure"] = {type = "bool-setting", value = true}
  values["ips-cost-base-research_low_density_structure"] = {type = "int-setting", value = 1234}
  values["ips-cost-growth-research_low_density_structure"] = {type = "double-setting", value = 1.7}
  values["ips-max-level-research_low_density_structure"] = {type = "int-setting", value = 5}
  values["ips-research-time-research_low_density_structure"] = {type = "int-setting", value = 77}
  values["ips-effect-per-level-research_low_density_structure"] = {type = "double-setting", value = 13}
elseif selector.default_value == "automatic-family-creation" then
  values["mir-automatic-productivity-action"] = {type = "string-setting", value = "apply"}
  values["mir-automatic-create-research"] = {type = "bool-setting", value = true}
  values["mir-automatic-require-reviewed-data"] = {type = "bool-setting", value = false}
  values["ips-enable-research_auto_assembling_machine"] = {type = "bool-setting", value = true}
elseif selector.default_value == "base-continuations" then
  values["mir-enable-inserter-capacity-bonus"] = {type = "bool-setting", value = true}
end

for name, row in pairs(values) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting then error("missing 3.2.9 to 3.2.10 upgrade setting " .. name) end
  setting.default_value = row.value
end
