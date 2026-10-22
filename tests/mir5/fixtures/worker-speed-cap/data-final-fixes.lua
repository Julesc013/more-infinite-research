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

local setting = data.raw["int-setting"] and data.raw["int-setting"]["mir-max-level-worker-robots-speed"]
if not setting or setting.default_value ~= 7 then
  error("[mir5-worker-speed-cap] finite worker cap default differs")
end
