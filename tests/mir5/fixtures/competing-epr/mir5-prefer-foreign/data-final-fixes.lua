-- Exact independent F200 Expanded Productivity Research 1.3.8 facts.
-- The fixture validates the captured named tail before changing only count/time.
local NAME = "epr_iron-gear-wheel-productivity-5"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack",
}
local function equals(actual, expected, label)
  assert(type(actual) == type(expected), label .. " type changed")
  if type(expected) ~= "table" then assert(actual == expected, label .. " changed") return end
  for key, value in pairs(expected) do equals(actual[key], value, label .. "." .. tostring(key)) end
  for key in pairs(actual) do assert(expected[key] ~= nil, label .. " gained " .. tostring(key)) end
end
local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do assert(actual[index] == name, label .. " changed at " .. tostring(index)) end
end
assert(mods.base == "2.0.77" and mods.ExpandedProductivityResearch == "1.3.8"
  and (mods["more-infinite-research"] == "4.7.20002" or mods["more-infinite-research"] == "5.0.20000")
  and mods["space-age"] == nil, "unexpected F200 EPR fixture closure")
local technology = assert(data.raw.technology[NAME], "captured EPR gear tail is absent")
assert(technology.type == "technology" and technology.name == NAME and technology.level == nil
  and technology.upgrade == true and technology.max_level == "infinite"
  and technology.enabled == nil and technology.visible_when_disabled == nil and technology.hidden == nil,
  "captured EPR gear tail identity or progression changed")
names(technology.prerequisites, {"space-science-pack", "epr_iron-gear-wheel-productivity-4"},
  "captured EPR gear prerequisites")
local unit = assert(technology.unit, "captured EPR gear tail unit is absent")
assert(unit.count == nil and unit.count_formula == "1.5^(L-4)*1000" and unit.time == 60,
  "captured EPR gear tail cost or time changed")
assert(type(unit.ingredients) == "table" and #unit.ingredients == #SCIENCE,
  "captured EPR gear tail science count changed")
for index, science in ipairs(SCIENCE) do
  local ingredient = unit.ingredients[index]
  assert(type(ingredient) == "table" and ingredient[1] == science and ingredient[2] == 1
    and ingredient[3] == nil, "captured EPR gear tail science changed at " .. tostring(index))
end
assert(type(technology.effects) == "table" and #technology.effects == 1
  and technology.effects[1].type == "change-recipe-productivity"
  and technology.effects[1].recipe == "iron-gear-wheel" and technology.effects[1].change == 0.1,
  "captured EPR gear tail effect changed")
equals(technology.icons, {
  {icon="__base__/graphics/icons/iron-gear-wheel.png"},
  {icon="__core__/graphics/icons/technology/effect-constant/effect-constant-recipe-productivity.png", icon_size=64},
}, "captured EPR gear icons")
equals(technology.localised_name, {"technology-name.epr_productivity_tech_final",
  {"?", {"item-name.iron-gear-wheel"}, {"fluid-name.iron-gear-wheel"},
    {"entity-name.iron-gear-wheel"}, {"equipment-name.iron-gear-wheel"}}},
  "captured EPR gear locale name")
equals(technology.localised_description, {"technology-description.epr_productivity_tech",
  {"?", {"item-name.iron-gear-wheel"}, {"fluid-name.iron-gear-wheel"},
    {"entity-name.iron-gear-wheel"}, {"equipment-name.iron-gear-wheel"}}},
  "captured EPR gear locale description")
-- No science, effect, prerequisite, presentation, owner, or progression field changes.
unit.count, unit.count_formula, unit.time = nil, "1", 1
