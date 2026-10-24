local streams = {
  research_agricultural_growth_speed = 2,
  research_spoilage_preservation = 3
}

for family, maximum in pairs(streams) do
  assert(data.raw["int-setting"]["ips-cost-base-" .. family]).default_value = 1
  assert(data.raw["int-setting"]["ips-cost-linear-increment-" .. family]).default_value = 0
  assert(data.raw["double-setting"]["ips-cost-growth-" .. family]).default_value = 1
  assert(data.raw["int-setting"]["ips-max-level-" .. family]).default_value = maximum
  assert(data.raw["int-setting"]["ips-research-time-" .. family]).default_value = 1
  assert(data.raw["double-setting"]["ips-effect-per-level-" .. family]).default_value = 1
end

local policy = assert(data.raw["string-setting"]["mir-science-pack-ingredient-policy"])
assert(policy.default_value == "configured")
policy.default_value = "all-official"

local space_gate = assert(data.raw["bool-setting"]["ips-require-space-gate"])
assert(space_gate.default_value == false)
space_gate.default_value = true