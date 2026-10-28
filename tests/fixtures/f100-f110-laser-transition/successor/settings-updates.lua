if mods.base ~= "1.1.110" or mods["more-infinite-research"] ~= "5.0.11000"
    or mods["mir-fixture-mir5-f100-f110-laser-transition"] ~= "0.2.0" then
  error("[mir5-f100-f110-laser-transition] F110 successor closure differs")
end
local settings = data.raw["int-setting"]
local maximum = assert(settings and settings["mir-max-level-laser-shooting-speed"],
  "[mir5-f100-f110-laser-transition] F110 laser cap setting is absent")
local effect = assert(settings["mir-effect-per-level-laser-shooting-speed"],
  "[mir5-f100-f110-laser-transition] F110 laser effect setting is absent")
maximum.default_value = 40
effect.default_value = 75
