-- Release the source cap only in the candidate stage. The published stage
-- deliberately retains 3 so it can produce the hidden carrier input.
local setting = assert(data.raw["int-setting"]["ips-max-level-research_material_imersite"],
  "MIR5 Imersite cap setting is absent")
assert(setting.default_value == 0 or setting.default_value == 3, "MIR5 Imersite cap default changed")
setting.default_value = 0
