-- Bounded native worker-robot-speed owner admission.
-- This is selection only: it neither mutates native prototypes nor retains state.
local M = {}

local INFINITE_MAX_LEVEL = 4294967295
local CANDIDATES = {
  { name = "worker-robots-speed-7", predecessor = "worker-robots-speed-6" },
  { name = "worker-robots-speed-6", predecessor = "worker-robots-speed-5" }
}

local function sole_worker_robot_speed_effect(effects)
  local effect = effects[1]
  return effect ~= nil and effects[2] == nil
    and effect.type == "worker-robot-speed" and effect.modifier == 0.65
end

-- The captured 2.1 data tail has the immediate predecessor plus a science
-- prerequisite. Inspect only those two bounded slots; selection never scans
-- arbitrary foreign prototype collections or prerequisite lists.
local function data_has_predecessor(prerequisites, expected)
  return prerequisites[1] == expected or prerequisites[2] == expected
end

local function admits_data(technology, candidate)
  return type(technology) == "table"
    and technology.name == candidate.name
    and technology.max_level == "infinite"
    and type(technology.effects) == "table"
    and sole_worker_robot_speed_effect(technology.effects)
    and type(technology.prerequisites) == "table"
    and data_has_predecessor(technology.prerequisites, candidate.predecessor)
end

local function admits_runtime(technology, candidate)
  local prototype = technology.prototype
  local prerequisites = technology.prerequisites
  return technology.name == candidate.name
    and prototype.max_level == INFINITE_MAX_LEVEL
    and sole_worker_robot_speed_effect(prototype.effects)
    and prerequisites[candidate.predecessor] ~= nil
    and prerequisites[candidate.predecessor].name == candidate.predecessor
end

local function select(lookup, admits)
  if type(lookup) ~= "function" then return nil end
  for index = 1, 2 do
    local candidate = CANDIDATES[index]
    local called, technology = pcall(lookup, candidate.name)
    if called then
      local checked, accepted = pcall(admits, technology, candidate)
      if checked and accepted then return candidate.name end
    end
  end
  return nil
end

-- Data-stage technology tables use max_level = "infinite" and prerequisite
-- names. The lookup is called only for the two recognized tail names.
function M.data_worker_robot_speed_owner(lookup)
  return select(lookup, admits_data)
end

-- At runtime LuaTechnology exposes numeric LuaTechnologyPrototype.max_level
-- and a LuaTechnology prerequisite object map (Factorio 2.1.23 runtime API).
function M.runtime_worker_robot_speed_owner(lookup)
  return select(lookup, admits_runtime)
end

return M
