-- Exercise the bounded all-official policy. The foreign native science remains
-- confined to the cryogenic owner; it is not an input MIR may discover.
local setting = assert(data.raw["string-setting"] and
  data.raw["string-setting"]["mir-science-pack-ingredient-policy"],
  "MIR 5 cryogenic fixture requires the science policy setting")
setting.default_value = "all-official"
