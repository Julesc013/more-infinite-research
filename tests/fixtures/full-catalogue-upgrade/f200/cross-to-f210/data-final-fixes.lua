if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "4.7.20003"
    or mods["mir-fixture-mir5-full-catalogue-upgrade"] ~= "0.2.1" then
  error("[mir5-full-catalogue-upgrade] cross source closure differs")
end
require("__mir-fixture-mir5-full-catalogue-upgrade__/fixture_data_final")
