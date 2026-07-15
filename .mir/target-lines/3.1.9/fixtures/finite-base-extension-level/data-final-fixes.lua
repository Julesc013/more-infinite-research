local source = data.raw.technology and data.raw.technology["research-speed-6"]
if not source then
  error("MIR validation fixture failed: research-speed-6 was not available.")
end

if data.raw.technology["research-speed-7"] then
  error("MIR validation fixture failed: research-speed-7 already exists before fixture installation.")
end

local tech = table.deepcopy(source)
tech.name = "research-speed-7"
tech.level = 7
tech.max_level = nil
tech.prerequisites = {"research-speed-6"}
tech.unit = {
  count = 777,
  ingredients = {{"automation-science-pack", 1}},
  time = 77
}

data:extend({tech})
