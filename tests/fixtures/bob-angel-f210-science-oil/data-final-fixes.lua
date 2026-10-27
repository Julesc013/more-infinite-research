local facts = require("__mir-fixture-mir5-bob-angel-f210-science-oil__/fixture_facts")
local closure = facts.closure(mods)

local function fail(message) error("[mir5-bob-angel-f210-science-oil] " .. message) end
local function close(actual, expected) return type(actual) == "number" and math.abs(actual - expected) <= .0000001 end
local function array(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, value in ipairs(expected) do if actual[index] ~= value then fail(label .. " differs at " .. tostring(index)) end end
end
local function ingredients(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, name in ipairs(expected) do
    local value = actual[index]
    if type(value) ~= "table" or (value.name or value[1]) ~= name or (value.amount or value[2]) ~= 1 then
      fail(label .. " differs at " .. tostring(index))
    end
  end
end
local function effects(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, wanted in ipairs(expected) do
    local value = actual[index]
    if type(value) ~= "table" or value.type ~= wanted.type or value.recipe ~= wanted.recipe
        or not close(value.change, wanted.change) then fail(label .. " differs at " .. tostring(index)) end
  end
end
local function icon_rows(actual, icon, label)
  if type(actual) ~= "table" or #actual ~= 2 then fail(label .. " icon count differs") end
  local primary, badge = actual[1], actual[2]
  if type(primary) ~= "table" or primary.icon ~= icon or primary.icon_size ~= 256
      or type(badge) ~= "table" or badge.icon ~= "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"
      or badge.icon_size ~= 128 or badge.scale ~= .5 or badge.floating ~= true
      or type(badge.shift) ~= "table" or badge.shift[1] ~= 50 or badge.shift[2] ~= 50 then
    fail(label .. " icons differ")
  end
end
local function item_exists(raw, name)
  for _, kind in ipairs({"item", "tool", "mining-tool", "module", "ammo", "capsule", "gun", "armor"}) do
    local row = raw[kind] and raw[kind][name]
    if type(row) == "table" and row.name == name then return true end
  end
  return false
end
local function check_closure()
  for name, version in pairs(closure.mods) do if mods[name] ~= version then fail("declared closure differs: " .. name) end end
  for name in pairs(mods) do if closure.mods[name] == nil then fail("unexpected declared mod: " .. name) end end
end
local function check_science(raw)
  local row = raw.technology and raw.technology[facts.science]
  if type(row) ~= "table" or row.type ~= "technology" or row.name ~= facts.science or row.level ~= 1
      or row.upgrade ~= true or row.max_level ~= "infinite" or row.order ~= "p[research_science_pack_productivity]"
      or row.enabled == false or row.hidden ~= nil or row.visible_when_disabled ~= nil or row.show_levels_info ~= nil then
    fail("science identity or presentation differs")
  end
  icon_rows(row.icons, closure.science_icon, "science")
  array(row.localised_name, {"technology-name.more-infinite-research.research_science_pack_productivity"}, "science name")
  array(row.localised_description, {"technology-description.more-infinite-research.recipe_productivity"}, "science description")
  array(row.prerequisites, closure.prerequisites, "science prerequisites")
  effects(row.effects, closure.effects, "science effects")
  local unit = row.unit
  if type(unit) ~= "table" or unit.count ~= nil or unit.count_formula ~= "8000*2^(L-1)" or unit.time ~= 120 then
    fail("science ordinary tuning differs")
  end
  ingredients(unit.ingredients, closure.vector, "science ingredients")
  for _, name in ipairs(closure.vector) do if not item_exists(raw, name) then fail("science input is absent: " .. name) end end
  for _, effect in ipairs(closure.effects) do
    if type(raw.recipe) ~= "table" or type(raw.recipe[effect.recipe]) ~= "table" then
      fail("science producer is absent: " .. effect.recipe)
    end
  end
  return row
end
local function check_oil(raw)
  local row = raw.technology and raw.technology[facts.oil]
  if type(row) ~= "table" or row.type ~= "technology" or row.name ~= facts.oil or row.level ~= 1
      or row.upgrade ~= true or row.max_level ~= "infinite" or row.order ~= "p[research_oil_cracking_productivity]"
      or row.enabled ~= false or row.hidden ~= nil or row.visible_when_disabled ~= nil or row.show_levels_info ~= nil then
    fail("oil saved identity differs")
  end
  icon_rows(row.icons, "__base__/graphics/technology/oil-processing.png", "oil")
  array(row.localised_name, {"technology-name.more-infinite-research.research_oil_cracking_productivity"}, "oil name")
  array(row.localised_description, {"technology-description.more-infinite-research.recipe_productivity"}, "oil description")
  array(row.prerequisites, facts.oil_prerequisites, "oil prerequisites")
  effects(row.effects, facts.oil_effects, "oil effects")
  local unit = row.unit
  if type(unit) ~= "table" or unit.count ~= nil or unit.count_formula ~= "8000*2^(L-1)" or unit.time ~= 60 then
    fail("oil ordinary tuning differs")
  end
  ingredients(unit.ingredients, facts.oil_prerequisites, "oil ingredients")
  for _, effect in ipairs(facts.oil_effects) do
    if type(raw.recipe) ~= "table" or type(raw.recipe[effect.recipe]) ~= "table" then
      fail("oil producer is absent: " .. effect.recipe)
    end
  end
end

check_closure()
local science = check_science(data.raw)
check_oil(data.raw)
-- The fixture alters only the science family once every declared source field
-- has passed. Oil remains a disabled saved identity and no ordinary tuning is
-- qualified by this disposable workload.
science.unit.count_formula, science.unit.count, science.unit.time = nil, 1, 1
