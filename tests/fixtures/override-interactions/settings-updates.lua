-- Select one explicit F210 interaction policy through ordinary startup defaults.
-- It intentionally leaves self-recycling classification inactive: cap 1 <=
-- the return-chance threshold 4 for the selected 20% recycle chance.
local selected = {
  ["mir-unrestricted-modules"] = true,
  ["mir-pipeline-extent-multiplier"] = "150",
  ["mir-prototype-productivity-cap"] = "percent-100",
  ["mir-productivity-cap-self-recycling-only"] = true,
  ["mir-recycling-return-chance"] = "percent-20",
  ["mir-prototype-speed-floor"] = "saving-50",
  ["mir-prototype-speed-cap"] = "bonus-200",
  ["mir-prototype-quality-cap"] = "bonus-100",
  ["mir-prototype-positive-power-floor"] = true,
}
for name, value in pairs(selected) do
  local setting = assert(data.raw["bool-setting"] and data.raw["bool-setting"][name]
    or data.raw["string-setting"] and data.raw["string-setting"][name], "missing MIR setting " .. name)
  assert(setting.setting_type == "startup", "MIR setting is not startup: " .. name)
  setting.default_value = value
end
