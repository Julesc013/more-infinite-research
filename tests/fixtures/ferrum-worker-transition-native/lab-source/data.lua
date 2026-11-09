-- Disposable data-only lab. Never mutates foreign or MIR technology contracts.
local lab = table.deepcopy(data.raw.lab.lab)
lab.name, lab.researching_speed, lab.energy_source = "mir-ferrum-transition-lab", 1001, {type="void"}
lab.inputs = {}
for _, name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack",
    "production-science-pack","utility-science-pack","space-science-pack","electromagnetic-science-pack"}) do
  if data.raw.item and data.raw.item[name] or data.raw.tool and data.raw.tool[name] then lab.inputs[#lab.inputs+1]=name end
end
-- Ferrum itself appends robotics to space-capable labs in final-fixes.
local rows = {lab}
for _, name in ipairs({"mir-ferrum-transition-sentinel","mir-ferrum-transition-count-6"}) do
  local calibration = name=="mir-ferrum-transition-count-6"
  rows[#rows+1] = {type="technology",name=name,icon="__base__/graphics/technology/automation-1.png",icon_size=256,
    level=calibration and 6 or nil, effects={},prerequisites={},hidden=calibration,enabled=not calibration,
    unit={count=1000,
      time=60,ingredients={{"automation-science-pack",1}}}}
  if calibration then rows[#rows].unit.count=nil; rows[#rows].unit.count_formula="1518.75" end
end
data:extend(rows)
