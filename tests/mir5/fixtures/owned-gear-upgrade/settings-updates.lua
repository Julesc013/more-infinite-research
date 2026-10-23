-- Fixture-only defaults make the published gear continuation complete through
-- two one-unit native lab cycles. They are normal startup defaults, not a
-- settings-data overwrite, and remain valid under the successor selection.
local expected = {
  {name = "ips-enable-research_gears", type = "bool-setting", value = true},
  {name = "ips-cost-base-research_gears", type = "int-setting", value = 1},
  {name = "ips-cost-linear-increment-research_gears", type = "int-setting", value = 0},
  {name = "ips-cost-growth-research_gears", type = "double-setting", value = 1},
  {name = "ips-research-time-research_gears", type = "int-setting", value = 1},
  {name = "ips-effect-per-level-research_gears", type = "double-setting", value = 10},
  {name = "ips-max-level-research_gears", type = "int-setting", value = 2}
}

for _, row in ipairs(expected) do
  local prototype = data.raw[row.type] and data.raw[row.type][row.name]
  if prototype == nil then
    error("[mir5-owned-gear-upgrade] expected startup setting is absent: " .. row.name)
  end
  prototype.default_value = row.value
end
