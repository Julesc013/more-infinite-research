-- Minimal controlled upstream raw shapes for the all-five vector fixture.
-- Existing stock rows are never changed or replaced.
local families={
  {owner="low-density-structure-productivity",recipes={{"low-density-structure","low-density-structure"},{"casting-low-density-structure","low-density-structure"}}},
  {owner="plastic-bar-productivity",recipes={{"plastic-bar","plastic-bar"},{"bioplastic","plastic-bar"}}},
  {owner="processing-unit-productivity",recipes={{"processing-unit","processing-unit"}}},
  {owner="rocket-fuel-productivity",recipes={{"rocket-fuel","rocket-fuel"},{"rocket-fuel-from-jelly","rocket-fuel"},{"ammonia-rocket-fuel","rocket-fuel"}}},
  {owner="steel-plate-productivity",recipes={{"steel-plate","steel-plate"},{"casting-steel","steel-plate"}}},
}
local rows={}
local function recipe(name,product)
  if data.raw.recipe[name]then return end
  rows[#rows+1]={type="recipe",name=name,category="crafting",enabled=false,allow_productivity=true,
    ingredients={{type="item",name="iron-plate",amount=1}},results={{type="item",name=product,amount=1}},main_product=product}
end
for _,family in ipairs(families)do
  local effects={}
  for _,route in ipairs(family.recipes)do recipe(route[1],route[2]);effects[#effects+1]={type="change-recipe-productivity",recipe=route[1],change=.1}end
  if not data.raw.technology[family.owner]then
    rows[#rows+1]={type="technology",name=family.owner,max_level="infinite",effects=effects,
      unit={count_formula="1.5^L*1000",time=60}}
  end
end
recipe("scrap-recycling","scrap")
if not data.raw.technology["scrap-recycling-productivity"]then
  rows[#rows+1]={type="technology",name="scrap-recycling-productivity",max_level="infinite",
    effects={{type="change-recipe-productivity",recipe="scrap-recycling",change=.1}},unit={count_formula="1.5^L*1000",time=60}}
end
data:extend(rows)
