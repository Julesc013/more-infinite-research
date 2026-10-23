-- This fixture selects a valid startup profile through the normal settings
-- stage. It changes defaults only for its disposable direct-library scenario;
-- it does not add, remove, or force any MIR setting prototype.
--
-- `forced_value` is deliberately not used. The current 2.1.23 local prototype
-- API has no documented setting-prototype forced-value contract, and this is a
-- valid scenario selection rather than a safety/deprecation override.
local raw_defaults = {
  {type = "bool-setting", name = "ips-enable-research_gears", value = false},
  {type = "int-setting", name = "ips-cost-base-research_gears", value = 13},
  {type = "int-setting", name = "ips-cost-linear-increment-research_gears", value = 11},
  {type = "double-setting", name = "ips-cost-growth-research_gears", value = 2},
  {type = "int-setting", name = "ips-max-level-research_gears", value = 5},
  {type = "int-setting", name = "ips-research-time-research_gears", value = 7},
  {type = "double-setting", name = "ips-effect-per-level-research_gears", value = 40},
  {type = "int-setting", name = "mir-max-level-worker-robots-speed", value = 7},
  {type = "bool-setting", name = "mir-enable-passive-repair", value = false}
}

for _, row in ipairs(raw_defaults) do
  local prototype = data.raw[row.type] and data.raw[row.type][row.name]
  if not prototype then
    error("[mir5-settings-repair] expected startup setting is absent: " .. row.name)
  end
  prototype.default_value = row.value
end

local import_name = "mir-settings-profile-import"
local import = data.raw["string-setting"] and data.raw["string-setting"][import_name]
if not import then error("[mir5-settings-repair] startup profile import setting is absent") end

-- The profile deliberately includes true, false-like zero, and numeric values
-- whose raw defaults above differ. Runtime observes its effective values only
-- through the shipped public settings interface.
import.default_value = [[{"schema":1,"kind":"mir-settings-profile","settings":{"ips-enable-research_gears":true,"ips-cost-base-research_gears":1,"ips-cost-linear-increment-research_gears":0,"ips-cost-growth-research_gears":1,"ips-max-level-research_gears":0,"ips-research-time-research_gears":1,"ips-effect-per-level-research_gears":10,"mir-max-level-worker-robots-speed":0,"mir-enable-passive-repair":true}}]]
