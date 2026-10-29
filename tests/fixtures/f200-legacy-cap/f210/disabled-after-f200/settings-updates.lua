local expected = {
  {name = "ips-enable-research_gears", type = "bool-setting", value = false},
  {name = "ips-effect-per-level-research_gears", type = "double-setting", value = 1},
  {name = "ips-max-level-research_gears", type = "int-setting", value = 40},
}

for _, row in ipairs(expected) do
  local setting = data.raw[row.type] and data.raw[row.type][row.name]
  if setting == nil then error("[mir5-f200-legacy-cap-disabled] setting is absent: " .. row.name) end
  setting.default_value = row.value
end
