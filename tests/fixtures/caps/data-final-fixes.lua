local technology_name = "recipe-prod-research_gears-1"
local packs = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack"
}

local function fail(message)
  error("[mir5-caps-native] " .. message)
end

local technology = data.raw.technology and data.raw.technology[technology_name]
if not technology then fail("gear technology is absent") end
if technology.max_level ~= "infinite" then fail("finite cap changed native max_level") end
if not technology.unit or technology.unit.count_formula ~= "1" or technology.unit.time ~= 1 then
  fail("fixture startup settings did not produce one-unit native research")
end
if #(technology.unit.ingredients or {}) ~= #packs then fail("gear science pack count differs") end
for index, name in ipairs(packs) do
  local ingredient = technology.unit.ingredients[index]
  if not ingredient or ingredient[1] ~= name or ingredient[2] ~= 1 then
    fail("gear science pack differs at " .. index)
  end
end

local effects = technology.effects or {}
if #effects ~= 1 or effects[1].type ~= "change-recipe-productivity"
    or effects[1].recipe ~= "iron-gear-wheel" or effects[1].change ~= 0.1 then
  fail("gear productivity effect differs from ten percent")
end
