-- The F210 Base catalogue has no science-pack productivity row in the
-- historical fixture input.  This narrow successor view retains only the
-- F200 saved identity and its six declared recipe effects; it does not alter
-- the ordinary F210 Base or Space Age fixture catalogues.
local plan = require("__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
local SCIENCE = "recipe-prod-research_science_pack_productivity-1"
local RECIPES = {
  "automation-science-pack", "chemical-science-pack", "logistic-science-pack",
  "military-science-pack", "production-science-pack", "utility-science-pack",
}

local function fail(message) error("[mir5-full-catalogue-upgrade] " .. message) end

local function insert_row(rows, after)
  local found = 0
  for _, row in ipairs(rows) do
    if row.name == SCIENCE then
      found = found + 1
      if row.group ~= "recipe-productivity" then fail("cross successor science row group differs") end
    end
  end
  if found == 1 then return end
  if found ~= 0 then fail("cross successor science row is duplicated") end
  for index, row in ipairs(rows) do
    if row.name == after then
      table.insert(rows, index + 1, {name=SCIENCE, group="recipe-productivity"})
      return
    end
  end
  fail("cross successor catalogue anchor is absent: " .. after)
end

local function insert_recipe(recipes, name)
  local found = 0
  for _, value in ipairs(recipes) do if value == name then found = found + 1 end end
  if found == 0 then
    recipes[#recipes + 1] = name
  elseif found ~= 1 then
    fail("cross successor recipe is duplicated: " .. name)
  end
end

if plan.target.id ~= "f210" or plan.target.version ~= "2.1.23" then
  fail("cross successor target differs")
end
insert_row(plan.base.public, "recipe-prod-research_rockets-1")
insert_row(plan.base.state, "recipe-prod-research_rockets-1")
for _, name in ipairs(RECIPES) do insert_recipe(plan.base.recipes, name) end
return plan
