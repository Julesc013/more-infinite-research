-- Identical settings on both sides isolate the identity/engine migration.
local family = "laser-shooting-speed"
local values = {
  ["bool-setting"] = {["mir-enable-" .. family] = true},
  ["int-setting"] = {
    ["mir-cost-base-" .. family] = 1,
    ["mir-cost-linear-increment-" .. family] = 0,
    ["mir-max-level-" .. family] = 12,
    ["mir-research-time-" .. family] = 1,
    ["mir-effect-per-level-" .. family] = 1,
  },
  ["double-setting"] = {["mir-cost-growth-" .. family] = 1},
}
for kind, rows in pairs(values) do
  for name, value in pairs(rows) do
    local setting = assert(data.raw[kind][name], "laser fixture setting absent: " .. name)
    assert(setting.setting_type == "startup", "laser fixture setting lifecycle differs")
    setting.default_value = value
  end
end
