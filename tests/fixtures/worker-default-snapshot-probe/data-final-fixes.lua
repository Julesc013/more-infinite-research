-- A separate effect-free research keeps queued/detached work orthogonal.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local source = assert(data.raw.technology["worker-robots-storage-4"])
assert(source.level == 4 and source.max_level == "infinite")
local sentinel = copy(source)
sentinel.name = "mir-fixture-worker-default-snapshot-sentinel"
sentinel.level, sentinel.max_level, sentinel.prerequisites = 1, 1, {}
sentinel.effects, sentinel.hidden, sentinel.enabled = {}, false, true
sentinel.visible_when_disabled, sentinel.upgrade = false, false
sentinel.unit.count_formula, sentinel.unit.count, sentinel.unit.time = nil, 100000, 60
data:extend({sentinel})
