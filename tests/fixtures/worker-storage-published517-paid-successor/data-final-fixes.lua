local tail = "mir-fixture-published517-earned-source-tail"
local active = {}
for name, version in pairs(mods) do
  active[#active + 1] = name .. "@" .. version
end
table.sort(active)
log("[MIR_ACTIVE_MODS] " .. table.concat(active, "|"))

local settings_expected = {
  {"mir-enable-worker-robots-storage", true},
  {"mir-max-level-worker-robots-storage", 10},
  {"mir-cost-base-worker-robots-storage", 200},
  {"mir-cost-linear-increment-worker-robots-storage", 0},
  {"mir-cost-growth-worker-robots-storage", 1.5},
  {"mir-research-time-worker-robots-storage", 60},
  {"mir-effect-per-level-worker-robots-storage", 1}
}
local settings_lines = {}
for _, expected in ipairs(settings_expected) do
  local setting = settings.startup[expected[1]]
  assert(setting and setting.value == expected[2], "successor setting differs: " .. expected[1])
  settings_lines[#settings_lines + 1] = expected[1] .. "=" .. type(setting.value) .. ":" .. tostring(setting.value)
end
log("[MIR_WORKER_STORAGE_SETTINGS] " .. table.concat(settings_lines, "|"))

local technologies = data.raw.technology
for _, name in ipairs({"mir-worker-storage-default-4", "mir-worker-storage-published517-4"}) do
  local prototype = technologies[name]
  local unit = prototype and prototype.unit
  local science = {}
  for _, ingredient in ipairs(unit and unit.ingredients or {}) do
    science[#science + 1] = tostring(ingredient[1]) .. ":" .. tostring(ingredient[2])
  end
  log("[MIR_PUBLISHED517_SUCCESSOR_DATA] " .. name .. "|present=" .. tostring(prototype ~= nil)
    .. "|formula=" .. tostring(unit and unit.count_formula) .. "|time=" .. tostring(unit and unit.time)
    .. "|science=" .. table.concat(science, ","))
end

-- Keep the save's unrelated fixture-owned tail after SE postprocess.
assert(technologies[tail] == nil, "successor tail already exists")
data:extend({{
  type = "technology",
  name = tail,
  icon = "__base__/graphics/technology/automation-1.png",
  icon_size = 256,
  prerequisites = {"automation-science-pack"},
  unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}},
  effects = {}
}})
