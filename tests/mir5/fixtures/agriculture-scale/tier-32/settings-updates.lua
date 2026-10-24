local tier = assert(data.raw["int-setting"] and data.raw["int-setting"]["mir5-agriculture-scale-tier"],
  "agriculture scale core fixture setting is absent")
assert(tier.setting_type == "startup" and tier.default_value == 1,
  "agriculture scale core fixture setting contract differs")
tier.default_value = 32

local policy = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir-science-pack-ingredient-policy"],
  "MIR science policy setting is absent")
assert(policy.setting_type == "startup", "MIR science policy setting is not startup")
policy.default_value = "all-official"

local gate = assert(data.raw["bool-setting"] and data.raw["bool-setting"]["ips-require-space-gate"],
  "MIR Space Age gate setting is absent")
assert(gate.setting_type == "startup", "MIR Space Age gate setting is not startup")
gate.default_value = true