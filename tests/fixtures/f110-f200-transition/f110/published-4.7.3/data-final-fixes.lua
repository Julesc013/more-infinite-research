if mods.base ~= "1.1.110" or mods["more-infinite-research"] ~= "4.7.11003"
    or mods["mir-fixture-mir5-f110-f200-transition"] ~= "0.1.0" then
  error("[mir5-f110-f200-transition] published F110 source closure differs")
end
local direct = assert(data.raw.technology["recipe-prod-research_character_mining_speed-1"],
  "[mir5-f110-f200-transition] published source mining technology is absent")
assert(direct.name == "recipe-prod-research_character_mining_speed-1" and direct.level == 1
  and direct.upgrade == true and direct.max_level == "infinite" and direct.enabled ~= false,
  "[mir5-f110-f200-transition] published source mining identity differs")
local unit = assert(direct.unit, "[mir5-f110-f200-transition] published source mining unit is absent")
assert(unit.count_formula == "8000*2^(L-1)" and unit.time == 60 and type(unit.ingredients) == "table"
  and #unit.ingredients == 2 and unit.ingredients[1][1] == "utility-science-pack" and unit.ingredients[1][2] == 1
  and unit.ingredients[2][1] == "military-science-pack" and unit.ingredients[2][2] == 1,
  "[mir5-f110-f200-transition] published source mining unit differs")
assert(type(direct.effects) == "table" and #direct.effects == 1
  and direct.effects[1].type == "character-mining-speed" and direct.effects[1].modifier == .05,
  "[mir5-f110-f200-transition] published source mining effect differs")

-- Fixture-only acceleration follows the published-source preflight. It does
-- not alter identity, level, science, effect or any of the other 16 rows.
unit.count_formula = nil
unit.count = 1
unit.time = 1
return require("__mir-fixture-mir5-f110-f200-transition__/fixture_data_final")
