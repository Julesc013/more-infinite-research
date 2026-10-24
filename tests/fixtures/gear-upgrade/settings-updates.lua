-- This fixture changes only the gear stream's documented startup defaults.
-- It deliberately uses values accepted by both the published 4.7 package and
-- the private 5.0 native slice so a saved 4.7 state has a common setting
-- contract when the runner changes only MIR's selected archive.
local expected = {
  {name = "ips-cost-base-research_gears", type = "int-setting", value = 1},
  {name = "ips-cost-linear-increment-research_gears", type = "int-setting", value = 0},
  {name = "ips-cost-growth-research_gears", type = "double-setting", value = 1},
  {name = "ips-research-time-research_gears", type = "int-setting", value = 1},
  {name = "ips-effect-per-level-research_gears", type = "double-setting", value = 10},
  {name = "ips-max-level-research_gears", type = "int-setting", value = 2}
}

for _, row in ipairs(expected) do
  local prototype = data.raw[row.type] and data.raw[row.type][row.name]
  if not prototype then
    error("[mir5-gear-upgrade] expected startup setting is absent: " .. row.name)
  end
  prototype.default_value = row.value
end