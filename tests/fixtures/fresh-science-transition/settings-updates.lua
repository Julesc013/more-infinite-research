-- Accelerate exactly the one existing science-productivity row after both
-- source defaults have been checked. The source fixture owns the all-policy
-- science shape; this companion neither adds packs nor changes effects.
local BASE = "ips-cost-base-research_science_pack_productivity"
local TIME = "ips-research-time-research_science_pack_productivity"

assert(mods.base == "2.1.23" and mods["space-age"] == "2.1.23", "fresh science transition requires F210")
assert(mods["more-infinite-research"] == "4.7.21003" or mods["more-infinite-research"] == "5.0.21000",
  "fresh science transition requires the selected published or current MIR archive")

local function source_setting(name, expected)
  local row = (data.raw["int-setting"] or {})[name]
  assert(type(row) == "table" and row.type == "int-setting" and row.default_value == expected,
    "fresh science transition source setting changed: " .. name)
  return row
end

-- Complete both preflights before either fixture-owned write.
local base = source_setting(BASE, 8000)
local time = source_setting(TIME, 120)
base.default_value = 1
time.default_value = 1
