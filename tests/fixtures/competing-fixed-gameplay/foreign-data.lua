-- Exact independent F200 Space Age foreign rows. Every transition stage
-- validates these captured rows before applying the fixture-only acceleration.
local function fail(message) error("[mir5-competing-fixed-gameplay] " .. message) end
local function close(actual, expected) return type(actual) == "number" and math.abs(actual - expected) <= 0.00000001 end
local function equal_names(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count changed") end
  for index, name in ipairs(expected) do if actual[index] ~= name then fail(label .. " changed at " .. tostring(index)) end end
end
local function equal_ingredients(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count changed") end
  for index, wanted in ipairs(expected) do
    local value = actual[index]
    if type(value) ~= "table" or value[1] ~= wanted[1] or value[2] ~= wanted[2] or value[3] ~= nil then
      fail(label .. " changed at " .. tostring(index))
    end
  end
end
local function equal_effects(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count changed") end
  for index, wanted in ipairs(expected) do
    local value = actual[index]
    if type(value) ~= "table" or value.type ~= "change-recipe-productivity" or value.recipe ~= wanted[1]
        or not close(value.change, 0.1) then fail(label .. " changed at " .. tostring(index)) end
  end
end
local ROWS = {
  {name="automation-science-productivity-4", prerequisites={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack","space-science-pack","productivity-module-3","promethium-science-pack","automation-science-productivity-3"}, effects={{"automation-science-pack"}}, formula="100000*(L - 3)", time=60, ingredients={{"automation-science-pack",2},{"logistic-science-pack",1},{"chemical-science-pack",1},{"production-science-pack",1},{"utility-science-pack",1},{"space-science-pack",1},{"promethium-science-pack",1}}, upgrade=true},
  {name="basic-plate-productivity", prerequisites={"advanced-material-processing"}, effects={{"copper-plate"},{"iron-plate"}}, formula="2500+2500*(L-1)", time=30, ingredients={{"automation-science-pack",1},{"logistic-science-pack",1}}},
  {name="bioflux-productivity", prerequisites={"bioflux","production-science-pack"}, effects={{"bioflux"}}, formula="2^L*600", time=60, ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},{"chemical-science-pack",1},{"production-science-pack",1},{"agricultural-science-pack",1}}, upgrade=true},
  {name="fish-breeding-productivity", prerequisites={"fish-breeding"}, effects={{"fish-breeding"}}, formula="1.5^L*1000-500", time=60, ingredients={{"space-science-pack",1},{"agricultural-science-pack",1}}, upgrade=true},
}
local mir = mods["more-infinite-research"]
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77" and (mir == "4.7.20002" or mir == "5.0.20000")
  and mods["plates-n-circuit-productivity"] == "0.0.2" and mods.Science_packs_productivity == "0.0.1"
  and mods["bioflux-productivity"] == "0.1.0" and mods["fish-productivity"] == "1.0.0", "unexpected captured fixed-provider closure")
for _, expected in ipairs(ROWS) do
  local value = assert(data.raw.technology[expected.name], "captured row is absent: " .. expected.name)
  if value.type ~= "technology" or value.name ~= expected.name or value.level ~= nil or value.max_level ~= "infinite"
      or value.enabled ~= nil or value.visible_when_disabled ~= nil or value.hidden ~= nil
      or value.unit == nil or value.unit.count ~= nil or value.unit.count_formula ~= expected.formula or value.unit.time ~= expected.time
      or value.upgrade ~= expected.upgrade then fail("captured identity/progression changed: " .. expected.name) end
  equal_names(value.prerequisites, expected.prerequisites, expected.name .. " prerequisites")
  equal_effects(value.effects, expected.effects, expected.name .. " effects")
  equal_ingredients(value.unit.ingredients, expected.ingredients, expected.name .. " science")
  value.unit.count, value.unit.count_formula, value.unit.time = nil, "1", 1
end
return true
