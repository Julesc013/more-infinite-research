-- Provide a playable source for the representative foreign pack so the
-- published predecessor can seed an actual save. This does not identify the
-- reporter's mod or replace the separate unresolved-source startup opponent.
local pack = "mir5-foreign-astral-insight-pack"
data:extend({{
  type="recipe", name=pack, enabled=true, energy_required=1,
  ingredients={{type="item", name="iron-plate", amount=1}},
  results={{type="item", name=pack, amount=1}}
}})
local inputs = assert(data.raw.lab.lab.inputs)
for _, name in ipairs(inputs) do if name == pack then return end end
inputs[#inputs + 1] = pack
