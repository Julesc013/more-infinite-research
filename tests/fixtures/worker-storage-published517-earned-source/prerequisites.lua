-- Reviewed, literal SE 0.7.57 setup declaration for the published 5.0.20017
-- source fixture. Runtime may grant these finite rows for setup, but it never
-- discovers parents, recursively researches them, or treats them as work.
local ROW_TEXT = [[
burner-mechanics=
automation-science-pack=burner-mechanics
fuel-processing=automation-science-pack
electricity=fuel-processing
basic-fluid-handling=electricity
steel-processing=automation-science-pack
basic-logistics=burner-mechanics
logistic-science-pack=basic-logistics|electricity
fluid-handling=basic-fluid-handling|steel-processing|logistic-science-pack
oil-gathering=fluid-handling
sand-processing=automation-science-pack
glass-processing=sand-processing
automation=electricity
oil-processing=oil-gathering|glass-processing|automation
plastics=oil-processing
electronics=electricity
advanced-circuit=plastics|electronics
sulfur-processing=oil-processing
engine=steel-processing|logistic-science-pack
chemical-science-pack=advanced-circuit|sulfur-processing|engine
advanced-oil-processing=chemical-science-pack
lubricant=advanced-oil-processing
electric-engine=lubricant
battery=sulfur-processing
robotics=electric-engine|battery
rocket-control-unit=chemical-science-pack|battery
flammables=oil-processing
se-fuel-refining=oil-processing
rocket-fuel=flammables|advanced-oil-processing|se-fuel-refining
solar-energy=steel-processing|logistic-science-pack|electronics|glass-processing
automation-2=automation|steel-processing|logistic-science-pack|electronics
concrete=basic-fluid-handling|automation-2|sand-processing
medium-electric-pole=steel-processing|logistic-science-pack
electric-energy-distribution-1=concrete|medium-electric-pole
electric-energy-accumulators=electric-energy-distribution-1|battery
advanced-material-processing=steel-processing|logistic-science-pack
low-density-structure=advanced-material-processing|chemical-science-pack
se-heat-shielding=chemical-science-pack
radar=electronics
rocket-silo=electric-engine|rocket-control-unit|rocket-fuel|solar-energy|electric-energy-accumulators|low-density-structure|se-heat-shielding|radar
electric-lab=electronics|glass-processing
modules=electric-lab|automation-2
efficiency-module=modules
speed-module=modules|se-fuel-refining
advanced-material-processing-2=advanced-material-processing|concrete|se-heat-shielding
se-rocket-science-pack=rocket-silo|speed-module|advanced-material-processing-2
worker-robots-storage-1=robotics|se-rocket-science-pack
fast-inserter=electronics
logistics=basic-logistics|automation-science-pack
logistics-2=logistics|logistic-science-pack|electronics
military=automation-science-pack
heavy-armor=military|steel-processing
modular-armor=heavy-armor|advanced-circuit
solar-panel-equipment=modular-armor|solar-energy
jetpack-1=solar-panel-equipment|chemical-science-pack
battery-equipment=battery|solar-panel-equipment
se-recycling-facility=advanced-material-processing-2|electric-engine
se-lifesupport-facility=low-density-structure|se-recycling-facility
se-lifesupport-equipment-1=battery-equipment|se-rocket-science-pack|se-lifesupport-facility
se-thruster-suit=jetpack-1|se-lifesupport-equipment-1
se-rocket-launch-pad=se-thruster-suit
explosives=sulfur-processing
lamp=electricity|glass-processing
laser=lamp|chemical-science-pack
processing-unit=se-rocket-science-pack
se-meteor-point-defence=concrete|glass-processing
se-meteor-defence=laser|processing-unit|se-meteor-point-defence
se-delivery-cannon=explosives|se-meteor-defence
se-space-assembling=se-rocket-launch-pad|se-delivery-cannon
se-space-belt=logistics-2|se-space-assembling
se-space-science-lab=se-space-belt
se-space-pipe=se-space-assembling
se-space-decontamination-facility=se-space-pipe
space-science-pack=se-space-science-lab|se-space-decontamination-facility
se-space-manufactory=fast-inserter|space-science-pack
se-space-biochemical-laboratory=se-space-manufactory
se-space-data-card=se-space-biochemical-laboratory
se-space-radiator-1=se-space-biochemical-laboratory
se-space-supercomputer-1=se-space-data-card|se-space-radiator-1
industrial-furnace=space-science-pack
se-space-thermodynamics-laboratory=industrial-furnace|se-space-manufactory
se-space-plasma-generator=se-space-thermodynamics-laboratory
se-pulveriser=fluid-handling|concrete
se-processing-cryonite=se-pulveriser|industrial-furnace
utility-science-pack=se-space-supercomputer-1|se-processing-cryonite|efficiency-module
electric-mining-drill=electricity
se-core-miner=oil-processing|se-pulveriser|electric-mining-drill
se-centrifuge=processing-unit
se-processing-vulcanite=se-core-miner|industrial-furnace|se-centrifuge
se-pyroflux-smelting=se-processing-vulcanite
productivity-module=modules
production-science-pack=se-space-supercomputer-1|se-space-plasma-generator|se-pyroflux-smelting|productivity-module
worker-robots-storage-2=worker-robots-storage-1|production-science-pack
area-mining-drill=production-science-pack
se-processing-iridium=area-mining-drill
gun-turret=military
se-space-mechanical-laboratory=gun-turret|production-science-pack
se-space-catalogue-material-1=se-space-mechanical-laboratory
se-space-hypercooling-1=se-space-radiator-1
se-material-science-pack-1=se-processing-iridium|se-space-catalogue-material-1|se-space-hypercooling-1
worker-robots-storage-3=worker-robots-storage-2|se-material-science-pack-1
]]

local rows, by_name = {}, {}
for line in ROW_TEXT:gmatch("[^\r\n]+") do
  local name, parents = line:match("^([^=]+)=(.*)$")
  assert(type(name) == "string" and name ~= "" and by_name[name] == nil, "invalid fixed prerequisite declaration")
  local parent_rows = {}
  if parents ~= "" then for parent in parents:gmatch("[^|]+") do parent_rows[#parent_rows + 1] = parent end end
  local row = {name = name, parents = parent_rows}
  rows[#rows + 1], by_name[name] = row, row
end
assert(#rows == 101, "fixed prerequisite declaration count differs")
return {rows = rows, by_name = by_name}
