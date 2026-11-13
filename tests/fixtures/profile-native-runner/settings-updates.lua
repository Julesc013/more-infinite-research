-- Opposing raw dropdown defaults remain valid native values. Only the normal
-- public profile import supplies these non-dropdown numeric percentages.
local raw = {
  ["mir-pipeline-extent-multiplier"] = "100",
  ["mir-prototype-productivity-cap"] = "engine-default",
  ["mir-prototype-efficiency-cap"] = "engine-default",
  ["mir-prototype-pollution-cap"] = "engine-default",
  ["mir-prototype-speed-floor"] = "engine-default",
  ["mir-prototype-speed-cap"] = "engine-default",
  ["mir-prototype-quality-cap"] = "engine-default",
  ["mir-recycling-return-chance"] = "percent-25",
}
for name, value in pairs(raw) do
  local prototype = assert(data.raw["string-setting"][name], "numeric profile raw setting missing: " .. name)
  prototype.default_value = value
end
assert(data.raw["string-setting"]["mir-settings-profile-import"]).default_value =
  [[{"schema":1,"kind":"mir-settings-profile","settings":{"mir-pipeline-extent-multiplier":123.45,"mir-prototype-productivity-cap":4321.5,"mir-prototype-efficiency-cap":-83.25,"mir-prototype-pollution-cap":-91.125,"mir-prototype-speed-floor":-75.5,"mir-prototype-speed-cap":1234.5,"mir-prototype-quality-cap":678.9,"mir-recycling-return-chance":12.34}}]]
