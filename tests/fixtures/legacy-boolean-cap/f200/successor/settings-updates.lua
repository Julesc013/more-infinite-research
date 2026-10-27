local fixture = "mir-fixture-mir5-legacy-boolean-cap"

assert(mods.base == "2.0.77" and mods["more-infinite-research"] == "5.0.20000"
  and mods[fixture] == "0.2.0", "[mir5-legacy-boolean-cap-f200] successor settings closure differs")

local cap = assert(data.raw["int-setting"] and data.raw["int-setting"]["ips-max-level-research_gears"],
  "[mir5-legacy-boolean-cap-f200] gear cap setting is absent")
local effect = assert(data.raw["double-setting"] and data.raw["double-setting"]["ips-effect-per-level-research_gears"],
  "[mir5-legacy-boolean-cap-f200] gear effect setting is absent")
assert(cap.default_value == 0 and cap.minimum_value <= 0,
  "[mir5-legacy-boolean-cap-f200] unlimited gear cap setting differs")
assert(effect.default_value == 10,
  "[mir5-legacy-boolean-cap-f200] gear effect setting differs")
