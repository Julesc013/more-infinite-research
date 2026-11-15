local M = {}

local WORKER = "worker-robots-speed-6"
local PREDECESSOR = "worker-robots-speed-5"
local SPACE_SCIENCE = "space-science-pack"
local CAP = "mir-max-level-worker-robots-speed"
local LAB = "mir-worker-speed-cap-ten-fast-lab"
local FIXTURE = "mir-fixture-mir5-worker-speed-cap-ten"
local STAGES = {source = {version = "0.1.0", cap = 0}, cap10 = {version = "0.2.0", cap = 10}}
local CLOSURE = {
  base = "2.0.77", ["more-infinite-research"] = "5.0.20015", ["space-exploration"] = "0.7.57",
  ["aai-containers"] = "0.3.2", ["aai-industry"] = "0.6.16", ["alien-biomes"] = "0.7.4",
  ["alien-biomes-graphics"] = "0.7.1", jetpack = "0.4.17", robot_attrition = "0.6.6",
  ["shield-projector"] = "0.2.2", ["space-exploration-graphics"] = "0.7.5",
  ["space-exploration-graphics-2"] = "0.7.2", ["space-exploration-graphics-3"] = "0.7.2",
  ["space-exploration-graphics-4"] = "0.7.2", ["space-exploration-graphics-5"] = "0.7.3",
  ["space-exploration-menu-simulations"] = "0.7.4", ["space-exploration-postprocess"] = "0.7.5",
  informatron = "0.4.0", ["aai-signal-transmission"] = "0.5.3",
}

local function fail(message) error("[mir5-worker-speed-cap-ten] " .. message) end

local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.0000001
end

local function assert_closure(stage)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown data-final stage") end
  for name, version in pairs(CLOSURE) do if mods[name] ~= version then fail("F200 SE closure differs: " .. name) end end
  for name in pairs(mods) do
    if name ~= FIXTURE and CLOSURE[name] == nil then fail("unexpected enabled mod: " .. name) end
  end
  if mods[FIXTURE] ~= expected.version then fail("fixture stage version differs") end
  return expected
end

local function assert_worker(row)
  if type(row) ~= "table" or row.name ~= WORKER or row.max_level ~= "infinite" then
    fail("SE worker-speed target is absent or finite")
  end
  if type(row.effects) ~= "table" or #row.effects ~= 1 then fail("SE worker-speed effect count differs") end
  local effect = row.effects[1]
  if type(effect) ~= "table" or effect.type ~= "worker-robot-speed" or not close(effect.modifier, 0.65) then
    fail("SE worker-speed effect differs")
  end
  local prerequisites, prerequisite_count = {}, 0
  for key, value in pairs(row.prerequisites or {}) do
    local name = type(key) == "string" and key or value
    if type(name) ~= "string" or prerequisites[name] then fail("SE worker-speed prerequisite differs") end
    prerequisites[name], prerequisite_count = true, prerequisite_count + 1
  end
  if prerequisite_count ~= 2 or prerequisites[PREDECESSOR] ~= true or prerequisites[SPACE_SCIENCE] ~= true then
    fail("SE worker-speed direct prerequisites differ")
  end
  if type(row.unit) ~= "table" or type(row.unit.time) ~= "number" or row.unit.time <= 0
      or type(row.unit.ingredients) ~= "table" or #row.unit.ingredients == 0 then
    fail("SE worker-speed research unit differs")
  end
end

local function worker_inputs(row)
  local inputs, seen = {}, {}
  for _, ingredient in ipairs(row.unit.ingredients) do
    local name = ingredient.name or ingredient[1]
    local amount = ingredient.amount or ingredient[2]
    if type(name) ~= "string" or name == "" or seen[name] or type(amount) ~= "number" or amount <= 0 then
      fail("SE worker-speed ingredient differs")
    end
    seen[name] = true
    inputs[#inputs + 1] = name
  end
  return inputs
end

function M.apply(stage)
  local expected = assert_closure(stage)
  local row = data.raw.technology and data.raw.technology[WORKER]
  local startup = settings.startup and settings.startup[CAP]
  if type(startup) ~= "table" or startup.value ~= expected.cap then fail("worker-speed cap startup differs") end
  assert_worker(row)
  local native_lab = data.raw.lab and data.raw.lab.lab
  if type(native_lab) ~= "table" then fail("native Base lab is absent") end
  -- Test apparatus only: preserve the selected technology unchanged and make
  -- its real unit contract finish in a bounded native run.
  local lab = table.deepcopy(native_lab)
  lab.name = LAB
  lab.minable = nil
  lab.energy_source = {type = "void"}
  lab.researching_speed = 14400
  lab.inputs = worker_inputs(row)
  data:extend({lab})
end

return M
