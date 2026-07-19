local archetype_setting = data.raw["string-setting"] and data.raw["string-setting"]["mir-upgrade-archetype"]
if not archetype_setting then error("missing mir-upgrade-archetype selector") end
local archetype = archetype_setting.default_value
local values = {}

if archetype == "space-age-native-owner" then
  values = {
    ["ips-enable-research_low_density_structure"] = {type = "bool-setting", value = true},
    ["ips-cost-base-research_low_density_structure"] = {type = "int-setting", value = 1234},
    ["ips-cost-growth-research_low_density_structure"] = {type = "double-setting", value = 1.7},
    ["ips-max-level-research_low_density_structure"] = {type = "int-setting", value = 0},
    ["ips-research-time-research_low_density_structure"] = {type = "int-setting", value = 77},
    ["ips-effect-per-level-research_low_density_structure"] = {type = "double-setting", value = 13}
  }
elseif archetype == "automatic-family-creation" then
  values = {
    ["mir-automatic-productivity-action"] = {type = "string-setting", value = "apply"},
    ["mir-automatic-create-research"] = {type = "bool-setting", value = true},
    ["mir-automatic-require-reviewed-data"] = {type = "bool-setting", value = false},
    ["ips-enable-research_auto_assembling_machine"] = {type = "bool-setting", value = true}
  }
elseif archetype == "base-continuations" then
  values = {
    ["mir-enable-inserter-capacity-bonus"] = {type = "bool-setting", value = true}
  }
end

for name, row in pairs(values) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting then error("missing upgrade-matrix startup setting " .. name) end
  setting.default_value = row.value
end
