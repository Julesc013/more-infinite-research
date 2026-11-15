local C=require("contract")
local lab=table.deepcopy(data.raw.lab.lab)
lab.name=C.lab
lab.minable=nil
lab.energy_source={type="void"}
lab.researching_speed=3600
lab.inputs=table.deepcopy(C.packs)
data:extend({lab,{type="technology",name=C.sentinel,icon="__base__/graphics/technology/automation-1.png",icon_size=256,
  effects={},unit={count=100,time=60,ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},
    {"chemical-science-pack",1},{"production-science-pack",1}}}}})
