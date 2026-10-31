for _, family in ipairs({"research_agricultural_growth_speed", "research_spoilage_preservation"}) do
  local setting = assert(data.raw["bool-setting"] and data.raw["bool-setting"]["ips-enable-" .. family])
  assert(setting.default_value == true)
  setting.default_value = false
end
