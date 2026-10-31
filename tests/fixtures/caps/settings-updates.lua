-- Keep the native run short without changing the emitted technology's
-- infinite prototype form.  The cap is enforced only by MIR runtime code.
local selected = {
  ["ips-cost-base-research_gears"] = {type = "int-setting", value = 1},
  ["ips-cost-linear-increment-research_gears"] = {type = "int-setting", value = 0},
  ["ips-cost-growth-research_gears"] = {type = "double-setting", value = 1},
  ["ips-max-level-research_gears"] = {type = "int-setting", value = 2},
  ["ips-research-time-research_gears"] = {type = "int-setting", value = 1},
  ["ips-effect-per-level-research_gears"] = {type = "double-setting", value = 10}
}

for name, row in pairs(selected) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting then error("MIR 5 caps fixture missing startup setting " .. name) end
  setting.default_value = row.value
end
