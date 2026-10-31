local fixture = "mir-fixture-mir5-legacy-boolean-cap"

assert(mods.base == "2.1.23" and mods["more-infinite-research"] == "5.0.21000"
  and mods[fixture] == "0.3.0", "[mir5-legacy-boolean-cap-f210] successor settings closure differs")
assert(mods["space-age"] == nil and mods["elevated-rails"] == nil and mods.quality == nil and mods.recycler == nil,
  "[mir5-legacy-boolean-cap-f210] Base successor has Space Age companions")

local cap = assert(data.raw["int-setting"] and data.raw["int-setting"]["ips-max-level-research_gears"],
  "[mir5-legacy-boolean-cap-f210] gear cap setting is absent")
local effect = assert(data.raw["double-setting"] and data.raw["double-setting"]["ips-effect-per-level-research_gears"],
  "[mir5-legacy-boolean-cap-f210] gear effect setting is absent")
assert(cap.default_value == 0 and cap.minimum_value <= 0,
  "[mir5-legacy-boolean-cap-f210] unlimited gear cap setting differs")
assert(effect.default_value == 10,
  "[mir5-legacy-boolean-cap-f210] gear effect setting differs")
