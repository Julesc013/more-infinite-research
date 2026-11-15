local C=require("contract")
local lab=table.deepcopy(data.raw.lab.lab)
local source=data.raw["assembling-machine"] and data.raw["assembling-machine"]["assembling-machine-1"]
C.require(source and source.type=="assembling-machine" and source.name=="assembling-machine-1","stock assembler source missing")
local assembler=table.deepcopy(source)
lab.name=C.lab
lab.minable=nil
lab.energy_source={type="void"}
lab.researching_speed=3600
lab.inputs=table.deepcopy(C.packs)
assembler.name=C.assembler
assembler.minable=nil
assembler.energy_source={type="void"}
assembler.energy_usage="1W"
assembler.crafting_speed=1
assembler.module_slots=0
assembler.allowed_effects={}
assembler.crafting_categories={"crafting"}
data:extend({lab,assembler})
