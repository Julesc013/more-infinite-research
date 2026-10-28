if mods.base ~= "1.0.0" or mods["more-infinite-research"] ~= "5.0.10000"
    or mods["mir-fixture-mir5-f100-f110-laser-transition"] ~= "0.1.0" then
  error("[mir5-f100-f110-laser-transition] F100 source closure differs")
end
local settings = data.raw["int-setting"]
local maximum = assert(settings and settings["mir-max-level-laser-shooting-speed"],
  "[mir5-f100-f110-laser-transition] F100 laser cap setting is absent")
local effect = assert(settings["mir-effect-per-level-laser-shooting-speed"],
  "[mir5-f100-f110-laser-transition] F100 laser effect setting is absent")
maximum.default_value = 8
effect.default_value = 75
