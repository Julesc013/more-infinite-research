if mods.base ~= "1.0.0" or mods["more-infinite-research"] ~= "5.0.10000"
    or mods["mir-fixture-mir5-f100-f110-laser-transition"] ~= "0.1.0" then
  error("[mir5-f100-f110-laser-transition] F100 source closure differs")
end
return require("__mir-fixture-mir5-f100-f110-laser-transition__/fixture_data_final").apply({
  direct = "laser-turret-speed-8", ammo = "laser-turret", maximum = 8,
  formula = "1*(1025.15625*1.5^(L-8))",
  research_time = 60,
})
