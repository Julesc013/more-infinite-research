-- Disposable native-fixture acceleration only.  It leaves the authored gear
-- identity, prerequisites, effect and unlimited progression untouched so real
-- laboratory completions remain observable within the multiplayer deadline.
-- The ordinary Library fixture stays on its qualified GUI/rejoin path.  The
-- standalone identity discovery harness stages this one setting as true in a
-- separately hashed, temporary fixture archive; it then stops after the
-- actual 120-tick two-client predicate and before any GUI or research action.
local standalone_identity_setting = {
  type = "bool-setting",
  name = "mir5-library-standalone-identity-discovery",
  setting_type = "startup",
  default_value = false,
  hidden = true,
}
data:extend({standalone_identity_setting})

local values = {
  ["ips-cost-base-research_gears"] = {type="int-setting", initial=8000, value=1},
  ["ips-cost-linear-increment-research_gears"] = {type="int-setting", initial=0, value=0},
  ["ips-cost-growth-research_gears"] = {type="double-setting", initial=2, value=1},
  ["ips-research-time-research_gears"] = {type="int-setting", initial=60, value=1},
}

-- Finish the complete read-only preflight before any fixture mutation.  A
-- changed later setting must leave every original default intact for diagnosis.
for name, expected in pairs(values) do
  local setting = data.raw[expected.type] and data.raw[expected.type][name]
  assert(setting and setting.setting_type == "startup" and setting.default_value == expected.initial,
    "unexpected Library refresh fixture setting " .. name)
end

for name, expected in pairs(values) do
  data.raw[expected.type][name].default_value = expected.value
end
