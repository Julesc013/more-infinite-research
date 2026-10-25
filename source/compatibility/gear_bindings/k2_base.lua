-- Exact retained F200 and independently captured F210 K2 core bindings.
-- Alternative K2 gear recipes remain with the shared product collector after
-- this named seed route; this map never substitutes the K2SO tuple.
local target = require("platform.target")

local profiles = {f200 = "k2-base-f200", f210 = "k2-base-f210"}
local profile = profiles[target.id]
if profile == nil then error("MIR K2 Base gear binding has no admitted target", 2) end

-- The percentage effect consumes this recipe identity and its gear product.
-- Its ingredients, batch yield, byproducts and item reskins may be changed
-- by other mods without changing that binding. Keep the authored K2 Asset
-- icon rather than certifying an unrelated item presentation field.
local function preflight_f210(raw)
  local recipe = raw.recipe["iron-gear-wheel"]
  for _, product in ipairs(type(recipe.results) == "table" and recipe.results or {}) do
    if type(product) == "table" and (product.type == nil or product.type == "item")
        and (product.name or product[1]) == "iron-gear-wheel" then
      return
    end
  end
  error("MIR F210 K2 gear binding recipe has no iron-gear-wheel product", 2)
end

return {
  profile = profile,
  icon = "__Krastorio2Assets__/icons/items/iron-gear-wheel.png",
  recipes = {"iron-gear-wheel"},
  preflight = target.id == "f210" and preflight_f210 or nil,
}
