local fixture = "mir-fixture-mir5-legacy-boolean-cap"

assert(mods.base == "2.0.77" and mods["more-infinite-research"] == "4.0.20000"
  and mods[fixture] == "0.1.0", "[mir5-legacy-boolean-cap-source] source settings closure differs")

local cap = assert(data.raw["int-setting"] and data.raw["int-setting"]["ips-max-level-research_gears"],
  "[mir5-legacy-boolean-cap-source] gear cap setting is absent")
local effect = assert(data.raw["double-setting"] and data.raw["double-setting"]["ips-effect-per-level-research_gears"],
  "[mir5-legacy-boolean-cap-source] gear effect setting is absent")
assert(cap.default_value == 0 and cap.minimum_value <= 2 and cap.maximum_value >= 2,
  "[mir5-legacy-boolean-cap-source] published gear cap setting differs")
assert(effect.default_value == 10,
  "[mir5-legacy-boolean-cap-source] published gear effect setting differs")
cap.default_value = 2
