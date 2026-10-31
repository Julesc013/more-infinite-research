-- Observation only: do not turn the Defaults comparator into a forced policy.
local policy = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir-science-pack-ingredient-policy"],
  "agriculture Defaults science policy is absent")
local gate = assert(data.raw["bool-setting"] and data.raw["bool-setting"]["ips-require-space-gate"],
  "agriculture Defaults gate is absent")
assert(policy.setting_type == "startup" and policy.default_value == "configured"
  and gate.setting_type == "startup" and gate.default_value == false,
  "agriculture Defaults startup definitions differ")
