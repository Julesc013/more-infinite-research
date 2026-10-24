-- The exact published 4.6 closure was observed with default cap 3. Release
-- that source cap explicitly so five real historical levels are available.
local setting = assert(data.raw["int-setting"]["ips-max-level-research_material_imersite"],
  "published predecessor Imersite cap setting is absent")
assert(setting.default_value == 3,
  "published predecessor Imersite cap default changed")
setting.default_value = 0
