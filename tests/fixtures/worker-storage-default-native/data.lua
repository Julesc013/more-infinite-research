-- Test-owned prototypes only; no existing research, science, cost or effect changes.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local lab = copy(assert(data.raw.lab.lab))
lab.name, lab.researching_speed = "mir-worker-default-native-lab", 3600
lab.energy_source, lab.energy_usage = {type="void"}, "1W"
local rows = {lab}
for _, suffix in ipairs({"current", "queued", "detached"}) do
  rows[#rows + 1] = {type="technology", name="mir-worker-default-native-" .. suffix,
    icon="__base__/graphics/technology/automation-1.png", icon_size=256,
    enabled=true, effects={}, prerequisites={}, max_level=1,
    unit={count=100000, time=60, ingredients={{"automation-science-pack",1}, {"logistic-science-pack",1},
      {"chemical-science-pack",1}, {"production-science-pack",1}, {"utility-science-pack",1}}}}
end
data:extend(rows)
