local C=require("contract")
local lab=table.deepcopy(data.raw.lab.lab)
lab.name=C.lab
lab.minable=nil
lab.energy_source={type="void"}
lab.researching_speed=3600
lab.inputs=table.deepcopy(C.packs)
data:extend({lab})
