data:extend{
 {type="technology",name="mir-browser-progress",localised_name="Partial research fixture",icon="__base__/graphics/icons/iron-plate.png",icon_size=64,unit={count=100,time=1,ingredients={{"automation-science-pack",1}}}},
 {type="technology",name="mir-browser-test-finite",localised_name="Finite research fixture",icon="__base__/graphics/icons/iron-plate.png",icon_size=64,unit={count=1,time=1,ingredients={{"automation-science-pack",1}}}},
 {type="technology",name="mir-browser-test-infinite",localised_name="Infinite research fixture",icon="__base__/graphics/icons/iron-plate.png",icon_size=64,max_level="infinite",unit={count_formula="L",time=1,ingredients={{"automation-science-pack",1}}}},
 {type="technology",name="mir-browser-queue-later",localised_name="Later queue fixture",icon="__base__/graphics/icons/iron-plate.png",icon_size=64,unit={count=100,time=1,ingredients={{"automation-science-pack",1}}}}
}

-- One small native discovery subject exercises a composed translation beyond
-- the old 1 KiB callback boundary. These names are LocalisedStrings consumed by
-- the engine; none of the three search terms occurs in the technology name or
-- the stable recipe/product IDs.
local discovery_results = {}
for index = 1, 32 do
 local name = string.format("mir-browser-discovery-product-%02d", index)
 local label = index == 32 and "matière témoin ultime" or ("matière préparée " .. index)
 data:extend{{type="item",name=name,localised_name=label .. " pour la découverte native des recettes et des produits",
  icon="__base__/graphics/icons/iron-plate.png",icon_size=64,stack_size=100}}
 discovery_results[#discovery_results+1] = {type="item",name=name,amount=1}
end
data:extend{
 {type="fluid",name="mir-browser-discovery-fluid",localised_name="fluide témoin pour la découverte native",auto_barrel=false,
  icon="__base__/graphics/icons/fluid/water.png",icon_size=64,default_temperature=15,
  base_color={r=0.1,g=0.2,b=0.3},flow_color={r=0.2,g=0.3,b=0.4}}
}
discovery_results[#discovery_results+1] = {type="fluid",name="mir-browser-discovery-fluid",amount=1}
local discovery_recipe = {type="recipe",name="mir-browser-discovery-recipe",localised_name="préparation témoin des produits",
 enabled=false,ingredients={{type="item",name="iron-plate",amount=1}},
 results=discovery_results,main_product="mir-browser-discovery-product-01"}
local base_recipe = data.raw and data.raw.recipe and data.raw.recipe["iron-plate"]
if base_recipe and base_recipe.categories ~= nil then
 discovery_recipe.categories = {"chemistry"}
else
 discovery_recipe.category = "chemistry"
end
data:extend{
 discovery_recipe,
 {type="technology",name="mir-browser-discovery-native",localised_name="Native discovery witness",
  icon="__base__/graphics/icons/iron-plate.png",icon_size=64,
  effects={{type="unlock-recipe",recipe="mir-browser-discovery-recipe"}},
  unit={count=100,time=1,ingredients={{"automation-science-pack",1}}}}
}
