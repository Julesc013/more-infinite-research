local C=require("contract")
local lab=table.deepcopy(data.raw.lab.lab)
lab.name=C.lab
lab.minable=nil
lab.energy_source={type="void"}
-- Exactly 32 science units per tick at the unchanged 3600-tick research unit.
-- This keeps accelerated engine controls free of fractional pack draining.
lab.researching_speed=C.lab_speed
lab.inputs=table.deepcopy(C.packs)
data:extend({lab,{type="technology",name=C.sentinel,icon="__base__/graphics/technology/automation-1.png",
  icon_size=256,effects={},prerequisites={},unit={count=100000,time=60,ingredients={{"automation-science-pack",1}}}}})
