-- The bounded cap withholds the public level-4 row.  It is the published
-- condition under which the 4.7 JSON-renamed tail remains a hidden carrier.
local setting = assert(data.raw["int-setting"]["ips-max-level-research_material_imersite"],
  "published Imersite cap setting is absent")
assert(setting.default_value == 0 or setting.default_value == 3, "published Imersite cap default changed")
setting.default_value = 3
