local source = data.raw.technology["worker-robots-storage-3"]
  or data.raw.technology["worker-robots-storage-2"]
if not source then error("MIR Better Robots fixture could not find worker robot storage technology.") end

local external = table.deepcopy(source)
external.name = "better-worker-robots-storage-infinite"
external.max_level = "infinite"
external.level = 1
external.prerequisites = {source.name}
external.effects = {{type = "worker-robot-storage", modifier = 1}}
external.unit = table.deepcopy(source.unit)
external.unit.count = nil
external.unit.count_formula = "200 * 1.5^(L-1)"

local dependent = table.deepcopy(source)
dependent.name = "mir-fixture-base-competitor-dependent"
dependent.max_level = nil
dependent.level = nil
dependent.prerequisites = {external.name}
dependent.effects = {}
dependent.unit = table.deepcopy(source.unit)
dependent.unit.count_formula = nil
dependent.unit.count = 100
dependent.upgrade = false

data:extend({external, dependent})
