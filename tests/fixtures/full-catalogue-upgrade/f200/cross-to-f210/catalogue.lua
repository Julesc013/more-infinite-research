-- The cross source starts from the exact F200 Base state while sharing the
-- intentionally literal F210 fixture table.  This adapter removes only the
-- two F210-only force fields and restores the F200 science-pack row/recipes.
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
      if row.group ~= "recipe-productivity" then fail("cross source science row group differs") end
    end
  end
  if found == 1 then return end
  if found ~= 0 then fail("cross source science row is duplicated") end
  for index, row in ipairs(rows) do
    if row.name == after then
      table.insert(rows, index + 1, {name=SCIENCE, group="recipe-productivity"})
      return
    end
  end
  fail("cross source catalogue anchor is absent: " .. after)
end
local function insert_recipe(recipes, name)
  local found = 0
  for _, value in ipairs(recipes) do if value == name then found = found + 1 end end
  if found == 0 then recipes[#recipes + 1] = name
  elseif found ~= 1 then fail("cross source recipe is duplicated: " .. name) end
end
local function remove_field(name)
  local found = 0
  for index = #plan.force_fields, 1, -1 do
    if plan.force_fields[index] == name then table.remove(plan.force_fields, index); found = found + 1 end
  end
  if found ~= 1 then fail("cross source F210-only force field differs: " .. name) end
end

if plan.target.id ~= "f210" or plan.target.version ~= "2.1.23" then fail("cross source target differs") end
plan.target = {
  id="f200", version="2.0.77", published_mir="4.7.20003", mir5="5.0.20000",
  source_fixture_version="0.2.1", space_age_closure={"elevated-rails", "quality", "space-age"},
}
remove_field("cargo_landing_pad_limit")
remove_field("max_cargo_bay_unloading_distance")
insert_row(plan.base.public, "recipe-prod-research_rockets-1")
insert_row(plan.base.state, "recipe-prod-research_rockets-1")
for _, name in ipairs(RECIPES) do insert_recipe(plan.base.recipes, name) end
return plan
