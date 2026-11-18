local M = {}

local FIXTURE = "mir-fixture-se-worker-speed-provider-admitted"
local MIR = "more-infinite-research"
local WORKER = "worker-robots-speed-10"
local PREDECESSOR = "worker-robots-speed-9"
local DEEP = "se-deep-space-science-pack-1"
local CAP = "mir-max-level-worker-robots-speed"
local LAB = "mir-fixture-se-worker-speed-provider-lab"
local CURRENT = "mir-fixture-se-worker-speed-provider-unrelated"
local QUEUED = "mir-fixture-se-worker-speed-provider-queued"
local STAGES = {
  source = {fixture = "0.1.0", mir = "5.0.20015", cap = 0},
  admission = {fixture = "0.2.0", mir = "5.0.20015", cap = 0},
  old = {fixture = "0.3.0", mir = "5.0.20015", cap = 10},
  candidate = {fixture = "0.4.0", mir = "5.0.20018", cap = 10},
}
local CLOSURE = {
  base = "2.0.77", ["space-exploration"] = "0.7.57", ["aai-containers"] = "0.3.2",
  ["aai-industry"] = "0.6.16", ["alien-biomes"] = "0.7.4", ["alien-biomes-graphics"] = "0.7.1",
  jetpack = "0.4.17", robot_attrition = "0.6.6", ["shield-projector"] = "0.2.2",
  ["space-exploration-graphics"] = "0.7.5", ["space-exploration-graphics-2"] = "0.7.2",
  ["space-exploration-graphics-3"] = "0.7.2", ["space-exploration-graphics-4"] = "0.7.2",
  ["space-exploration-graphics-5"] = "0.7.3", ["space-exploration-menu-simulations"] = "0.7.4",
  ["space-exploration-postprocess"] = "0.7.5", informatron = "0.4.0", ["aai-signal-transmission"] = "0.5.3",
}

local function fail(message) error("[se-worker-speed-provider] " .. message) end
local function close(left, right) return type(left) == "number" and math.abs(left - right) <= 0.0000001 end

local function expected(stage)
  local row = STAGES[stage]
  if row == nil then fail("unknown data stage") end
  for name, version in pairs(CLOSURE) do if mods[name] ~= version then fail("SE tuple differs: " .. name) end end
  for name in pairs(mods) do
    if name ~= FIXTURE and name ~= MIR and CLOSURE[name] == nil then fail("unexpected enabled mod: " .. name) end
  end
  if mods[FIXTURE] ~= row.fixture or mods[MIR] ~= row.mir then fail("fixture or MIR stage differs") end
  return row
end

local function worker_inputs(worker)
  if type(worker) ~= "table" or worker.name ~= WORKER or worker.max_level ~= "infinite" then fail("worker-speed target is absent or finite") end
  local direct, count = {}, 0
  for key, value in pairs(worker.prerequisites or {}) do
    local name = type(key) == "string" and key or value
    if type(name) ~= "string" or direct[name] then fail("worker-speed parent shape differs") end
    direct[name], count = true, count + 1
  end
  if count ~= 2 or direct[PREDECESSOR] ~= true or direct[DEEP] ~= true then fail("worker-speed direct parents differ") end
  local effects = worker.effects
  if type(effects) ~= "table" or #effects ~= 1 or effects[1].type ~= "worker-robot-speed" or not close(effects[1].modifier, .65) then fail("worker-speed effect differs") end
  local inputs, seen = {}, {}
  for _, ingredient in ipairs(worker.unit and worker.unit.ingredients or {}) do
    local name, amount = ingredient.name or ingredient[1], ingredient.amount or ingredient[2]
    if type(name) ~= "string" or seen[name] or type(amount) ~= "number" or amount <= 0 then fail("worker-speed science differs") end
    seen[name], inputs[#inputs + 1] = true, name
  end
  if #inputs ~= 8 then fail("worker-speed science count differs") end
  return inputs
end

local function unrelated(name)
  local row = table.deepcopy(assert(data.raw.technology.automation))
  row.name, row.localised_name = name, {"technology-name.automation"}
  row.prerequisites, row.effects = {"automation"}, {}
  row.unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}}
  return row
end

function M.apply(stage, report_active_mods)
  local row = expected(stage)
  if type(report_active_mods) ~= "function" then fail("active-mod report callback differs") end
  local tuple = {}
  for name, version in pairs(mods) do tuple[#tuple + 1] = name .. "@" .. version end
  table.sort(tuple)
  report_active_mods(table.concat(tuple, "|"))
  local setting = settings.startup and settings.startup[CAP]
  if type(setting) ~= "table" or setting.value ~= row.cap then fail("worker-speed cap differs") end
  local worker = data.raw.technology and data.raw.technology[WORKER]
  local inputs = worker_inputs(worker)
  local lab = table.deepcopy(assert(data.raw.lab.lab))
  lab.name, lab.minable, lab.energy_source, lab.energy_usage = LAB, nil, {type = "void"}, "1W"
  lab.researching_speed, lab.inputs = 14400, inputs
  data:extend({lab, unrelated(CURRENT), unrelated(QUEUED)})
end

return M
