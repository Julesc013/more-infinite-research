-- Native resource science is a real engine source outside MIR's finite recipe
-- fragment. The native cryogenic recipe/owner remain otherwise unchanged.
local pack = table.deepcopy((data.raw.item or {})["automation-science-pack"]
  or (data.raw.tool or {})["automation-science-pack"])
pack.name = "mir472-native-science"
local ore = table.deepcopy(data.raw.resource["iron-ore"])
ore.name = "mir472-native-science-resource"
ore.minable = {mining_time = 1, result = pack.name}
data:extend({pack, ore})
for _, lab in pairs(data.raw.lab) do
  lab.inputs[#lab.inputs + 1] = pack.name
end
local owner = data.raw.technology["cryogenic-science-pack"]
assert(owner, "Space Age cryogenic research is required")
owner.research_trigger = nil
owner.unit = {count = 1, time = 1, ingredients = {{pack.name, 1}}}
