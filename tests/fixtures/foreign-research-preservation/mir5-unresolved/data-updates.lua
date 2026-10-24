-- Factorio requires one lab accepting each technology's complete pack set,
-- even when the declared pack has no producer. Keep acquisition unresolved.
local pack = "mir5-foreign-astral-insight-pack"
local inputs = assert(data.raw.lab.lab.inputs, "unresolved fixture base lab inputs are absent")
for _, name in ipairs(inputs) do if name == pack then return end end
inputs[#inputs + 1] = pack
