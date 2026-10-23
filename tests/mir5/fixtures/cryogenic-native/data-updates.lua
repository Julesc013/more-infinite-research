-- Reproduce a foreign ordinary-unit replacement for Space Age's named
-- cryogenic owner. The science pack is mineable from a resource, so this
-- fixture does not imply a finite recipe or research-graph source.
local pack = table.deepcopy((data.raw.item or {})["automation-science-pack"]
  or (data.raw.tool or {})["automation-science-pack"])
assert(pack, "MIR 5 cryogenic fixture requires automation science")
pack.name = "mir5-cryogenic-native-science"

local ore = table.deepcopy(assert(data.raw.resource["iron-ore"],
  "MIR 5 cryogenic fixture requires iron ore"))
ore.name = "mir5-cryogenic-native-science-resource"
ore.minable = {mining_time = 1, result = pack.name}
data:extend({pack, ore})

for _, lab in pairs(data.raw.lab or {}) do
  lab.inputs[#lab.inputs + 1] = pack.name
end

-- Retain the native recipe, its unlock and its prerequisite. Only the trigger
-- becomes an ordinary positive research unit with foreign resource science.
local owner = assert(data.raw.technology["cryogenic-science-pack"],
  "Space Age cryogenic research is required")
owner.research_trigger = nil
owner.unit = {count = 1, time = 1, ingredients = {{pack.name, 1}}}
