local candidates = {
  {name = "worker-robots-speed-7", predecessor = "worker-robots-speed-6"},
  {name = "worker-robots-speed-6", predecessor = "worker-robots-speed-5"}
}

local function admitted(candidate)
  local technology = data.raw.technology and data.raw.technology[candidate.name]
  if not technology or technology.max_level ~= "infinite" then return nil end
  local effects = technology.effects
  if type(effects) ~= "table" or #effects ~= 1
      or effects[1].type ~= "worker-robot-speed" or effects[1].modifier ~= 0.65 then
    return nil
  end
  local prerequisites = technology.prerequisites
  if type(prerequisites) ~= "table" or (prerequisites[1] ~= candidate.predecessor
      and prerequisites[2] ~= candidate.predecessor) then
    return nil
  end
  return technology
end

local selected = nil
for _, candidate in ipairs(candidates) do
  if admitted(candidate) then selected = candidate; break end
end
if not selected then error("[mir5-worker-speed-cap] no admitted native worker-speed tail") end

local setting = settings.startup["mir-max-level-worker-robots-speed"]
if not setting or setting.value ~= 7 then
  error("[mir5-worker-speed-cap] finite worker startup cap differs")
end
-- An unrelated fixture-owned technology remains unresearched after recursively
-- preparing all native worker prerequisites. Its start raises a real event.
data:extend({{
  type = "technology", name = "mir5-worker-speed-cap-probe",
  icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
  prerequisites = {"automation-science-pack"},
  unit = {count = 100, time = 1, ingredients = {{"automation-science-pack", 1}}},
  effects = {}
}})
