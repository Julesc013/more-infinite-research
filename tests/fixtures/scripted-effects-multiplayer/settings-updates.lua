local streams = {
  "research_agricultural_growth_speed",
  "research_spoilage_preservation"
}

for _, family in ipairs(streams) do
  assert(data.raw["int-setting"]["ips-cost-base-" .. family]).default_value = 1
  assert(data.raw["int-setting"]["ips-cost-linear-increment-" .. family]).default_value = 0
  assert(data.raw["double-setting"]["ips-cost-growth-" .. family]).default_value = 1
  assert(data.raw["int-setting"]["ips-max-level-" .. family]).default_value = 0
  assert(data.raw["int-setting"]["ips-research-time-" .. family]).default_value = 1
  assert(data.raw["double-setting"]["ips-effect-per-level-" .. family]).default_value = 1
end

local passive_repair = assert(data.raw["bool-setting"]["mir-enable-passive-repair"])
assert(passive_repair.default_value == false)
passive_repair.default_value = true
