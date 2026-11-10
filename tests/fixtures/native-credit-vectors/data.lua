local C=require("contract")
local lab=table.deepcopy(data.raw.lab.lab)
lab.name=C.lab
lab.minable=nil
lab.energy_source={type="void"}
lab.researching_speed=100001
lab.inputs=table.deepcopy(C.packs)
data:extend({lab,{type="technology",name=C.sentinel,icon="__base__/graphics/technology/automation-1.png",
  icon_size=256,effects={},prerequisites={},unit={count=100000,time=60,ingredients={{"automation-science-pack",1}}}}})
