-- This fixture supplies only its disposable lab.  It never declares a worker
-- technology, so the published11 middle selection can be Base plus MIR only.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local lab = copy(assert(data.raw.lab.lab))
lab.name = "mir-worker-uninvested-native-lab"
lab.researching_speed = 3600
lab.energy_source, lab.energy_usage = {type="void"}, "1W"
data:extend({lab})
