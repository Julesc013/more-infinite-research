-- Owned diagnostic lab only. Existing technologies, costs and sciences stay intact.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local lab = copy(assert(data.raw.lab.lab))
lab.name = "mir-fixture-worker-default-snapshot-lab"
lab.researching_speed = 3600 -- one science unit/tick at the unchanged60-second unit.
lab.energy_source, lab.energy_usage = {type="void"}, "1W"
data:extend({lab})
