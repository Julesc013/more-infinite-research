-- Private native mechanism control.  These carriers are fixture-owned,
-- disabled and hidden; player MIR code neither discovers nor writes them.
local FISH = "fish-breeding"
local POSITIVE = "mir5-native-credit-control-fish-positive"
local NEGATIVE = "mir5-native-credit-control-fish-negative"

assert(mods.base == "2.0.77" and mods["elevated-rails"] == "2.0.77"
  and mods.quality == "2.0.77" and mods["space-age"] == "2.0.77"
  and mods["more-infinite-research"] == "5.0.20000",
  "native credit control loaded with an unexpected F200 Space Age closure")

local function carrier(name, change)
  return {
    type = "technology",
    name = name,
    icon = "__space-age__/graphics/technology/fish-breeding.png",
    icon_size = 256,
    hidden = true,
    enabled = false,
    visible_when_disabled = false,
    upgrade = true,
    max_level = "infinite",
    effects = {{type = "change-recipe-productivity", recipe = FISH, change = change}},
    unit = {
      count_formula = "1",
      time = 1,
      ingredients = {{"automation-science-pack", 1}}
    },
    order = "z[mir5-native-credit-control]-" .. name
  }
end

data:extend({
  carrier(POSITIVE, 0.1),
  carrier(NEGATIVE, -0.1)
})
