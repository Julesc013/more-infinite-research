local tier = assert(data.raw["int-setting"] and data.raw["int-setting"]["mir5-agriculture-scale-tier"],
  "agriculture paired candidate core setting is absent")
assert(tier.setting_type == "startup" and tier.default_value == 1,
  "agriculture paired candidate requires the fixed single-tower tier")

local policy = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir-science-pack-ingredient-policy"],
  "MIR candidate science policy setting is absent")
assert(policy.setting_type == "startup", "MIR candidate science policy setting is not startup")
policy.default_value = "all-official"

local gate = assert(data.raw["bool-setting"] and data.raw["bool-setting"]["ips-require-space-gate"],
  "MIR candidate Space Age gate setting is absent")
assert(gate.setting_type == "startup", "MIR candidate Space Age gate setting is not startup")
gate.default_value = true
