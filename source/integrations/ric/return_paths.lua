-- Preserve the integration's fixed published process condition; the shared
-- checker reads only this phase's recipes and reached native item conversions.
local returns = require("compatibility.material_returns")
local M = {}
local products = {{type="item",name="ric-coke",amount=1}, {type="item",name="ric-ash",amount=1}}
local ingredients = {{type="item",name="ric-dried-marine-biomass",amount=1}}

function M.validate(raw, context)
  returns.validate(raw, products, ingredients, context, "ric-carbonise-marine-biomass")
end

return M
