-- The two private fixture identities exercise the two owned setting profiles
-- without manufacturing a mod-settings.dat.  The archive builder may override
-- only info.json's fixture version: 0.1.0 retains published defaults; 0.2.0
-- sets the approved tuned defaults below.
local expected = {
  {type = "bool-setting", name = "ips-enable-research_gears"},
  {type = "int-setting", name = "ips-cost-base-research_gears"},
  {type = "int-setting", name = "ips-cost-linear-increment-research_gears"},
  {type = "double-setting", name = "ips-cost-growth-research_gears"},
  {type = "int-setting", name = "ips-research-time-research_gears"},
  {type = "double-setting", name = "ips-effect-per-level-research_gears"},
  {type = "string-setting", name = "mir-settings-profile-import"}
}

for _, row in ipairs(expected) do
  if not (data.raw[row.type] and data.raw[row.type][row.name]) then
    error("MIR 5 gear fixture missing startup setting " .. row.name)
  end
end

local fixture_version = mods["mir-fixture-mir5-gear-native"]
if fixture_version == "0.1.0" then
  return
end
if fixture_version ~= "0.2.0" then
  error("MIR 5 gear fixture has unsupported version " .. tostring(fixture_version))
end

local tuned = {
  ["ips-cost-base-research_gears"] = {type = "int-setting", value = 100},
  ["ips-cost-linear-increment-research_gears"] = {type = "int-setting", value = 25},
  ["ips-cost-growth-research_gears"] = {type = "double-setting", value = 1.5},
  ["ips-research-time-research_gears"] = {type = "int-setting", value = 30},
  ["ips-effect-per-level-research_gears"] = {type = "double-setting", value = 20}
}
for name, row in pairs(tuned) do
  data.raw[row.type][name].default_value = row.value
end
