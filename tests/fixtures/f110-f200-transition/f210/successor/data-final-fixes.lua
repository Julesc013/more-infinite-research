if mods.base ~= "2.1.23" or mods["more-infinite-research"] ~= "5.0.21000"
    or mods["mir-fixture-mir5-f110-f200-transition"] ~= "0.4.0" then
  error("[mir5-f110-f200-transition] F210 successor closure differs")
end
local direct = assert(data.raw.technology["recipe-prod-research_character_mining_speed-1"],
  "[mir5-f110-f200-transition] F210 successor mining technology is absent")
local unit = assert(direct.unit, "[mir5-f110-f200-transition] F210 successor mining unit is absent")
assert(direct.name == "recipe-prod-research_character_mining_speed-1" and direct.level == 1
  and direct.upgrade == true and direct.max_level == "infinite" and direct.enabled ~= false,
  "[mir5-f110-f200-transition] F210 successor mining identity differs")
assert(unit.count == nil and unit.count_formula == "8000*2^(L-1)" and unit.time == 60
  and type(unit.ingredients) == "table" and #unit.ingredients == 2
  and unit.ingredients[1][1] == "utility-science-pack" and unit.ingredients[1][2] == 1
  and unit.ingredients[2][1] == "military-science-pack" and unit.ingredients[2][2] == 1,
  "[mir5-f110-f200-transition] F210 successor mining unit differs")
assert(type(direct.effects) == "table" and #direct.effects == 1
  and direct.effects[1].type == "character-mining-speed" and direct.effects[1].modifier == .05,
  "[mir5-f110-f200-transition] F210 successor mining effect differs")

-- The exact target input is preflighted before acceleration. This does not
-- compare a full F110/F210 catalogue: their ordinary tail costs may differ.
unit.count_formula = nil
unit.count = 1
unit.time = 1
return require("__mir-fixture-mir5-f110-f200-transition__/fixture_data_final")
