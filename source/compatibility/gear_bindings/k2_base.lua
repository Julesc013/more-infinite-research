-- Exact retained F200 and independently captured F210 K2 core bindings.
-- Alternative K2 gear recipes remain with the shared product collector after
-- this named seed route; this map never substitutes the K2SO tuple.
local target = require("platform.target")

local profiles = {f200 = "k2-base-f200", f210 = "k2-base-f210"}
local profile = profiles[target.id]
if profile == nil then error("MIR K2 Base gear binding has no admitted target", 2) end

-- F210 consumes this named native recipe and uses this item icon for the
-- generated technology. Retain the captured source shape instead of using
-- unrelated K2, flib, Base, or menu-simulation version strings as a proxy.
local function equal_stack(actual, expected)
  return type(actual) == "table" and #actual == 1 and type(actual[1]) == "table"
    and actual[1].type == expected.type and actual[1].name == expected.name and actual[1].amount == expected.amount
end

local function preflight_f210(raw)
  local recipe = raw.recipe["iron-gear-wheel"]
  if not equal_stack(recipe and recipe.ingredients, {type = "item", name = "iron-plate", amount = 1})
      or not equal_stack(recipe and recipe.results, {type = "item", name = "iron-gear-wheel", amount = 1}) then
    error("MIR F210 K2 gear binding source recipe changed", 2)
  end
  local item = type(raw.item) == "table" and raw.item["iron-gear-wheel"] or nil
  if type(item) ~= "table" or item.icon ~= "__Krastorio2Assets__/icons/items/iron-gear-wheel.png" then
    error("MIR F210 K2 gear binding source icon changed", 2)
  end
end

return {
  profile = profile,
  icon = "__Krastorio2Assets__/icons/items/iron-gear-wheel.png",
  recipes = {"iron-gear-wheel"},
  preflight = target.id == "f210" and preflight_f210 or nil,
}
