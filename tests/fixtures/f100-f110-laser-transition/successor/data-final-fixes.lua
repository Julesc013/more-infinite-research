if mods.base ~= "1.1.110" or mods["more-infinite-research"] ~= "5.0.11000"
    or mods["mir-fixture-mir5-f100-f110-laser-transition"] ~= "0.2.0" then
  error("[mir5-f100-f110-laser-transition] F110 successor closure differs")
end
return require("__mir-fixture-mir5-f100-f110-laser-transition__/fixture_data_final").apply({
  direct = "laser-shooting-speed-8", ammo = "laser", maximum = 40,
  formula = "1*(1025.15625*1.5^(L-8))",
  research_time = 120,
})
