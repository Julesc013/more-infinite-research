-- Exact, reduced base-continuation contracts for the seven released
-- historical target lines.  Each selected body is constructed on demand:
-- target selection never turns a broad native-chain discovery pass into an
-- implicit feature.
local M = {}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR historical continuation contract contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function row(id, family, level, predecessor, previous, counts, effects, science, prerequisites, order)
  return {
    id=id, family=family, level=level, predecessor=predecessor, previous=previous,
    expected_predecessor_count=counts[1], expected_previous_count=counts[2],
    effects=effects, science=science, prerequisites=prerequisites, order=order,
  }
end

local function inserter(id, level, science, prerequisites, numeric)
  local result = row(id, "inserter-capacity-bonus", level, "inserter-capacity-bonus-" .. (level - 1),
    "inserter-capacity-bonus-" .. (level - 2), {600, 400}, {
      {type="inserter-stack-size-bonus", scale=0.5, absolute=true},
      {type="stack-inserter-capacity-bonus", scale=1, absolute=true},
    }, science, prerequisites, "c-o-h")
  result.numeric = numeric == true
  if result.numeric then
    result.unit_count, result.research_time = 914489, 60
  end
  return result
end

local function storage(id, level, science, prerequisites, numeric)
  local result = row(id, "worker-robots-storage", level, "worker-robots-storage-" .. (level - 1),
    "worker-robots-storage-" .. (level - 2), {450, 300}, {
      {type="worker-robot-storage", scale=1, absolute=true},
    }, science, prerequisites, "c-k-g-c")
  result.numeric = numeric == true
  if result.numeric then
    result.unit_count, result.research_time = 675, 60
  end
  return result
end

local function numeric_rows()
  local science = {
    {"alien-science-pack", 2}, {"science-pack-1", 4}, {"science-pack-2", 4}, {"science-pack-3", 3},
  }
  local inserter_row = inserter("inserter-capacity-bonus-8", 8, science, {
    "advanced-electronics", "alien-technology", "battery", "inserter-capacity-bonus-6",
    "inserter-capacity-bonus-7", "logistics",
  }, true)
  local storage_row = storage("worker-robots-storage-4", 4, {
    {"alien-science-pack", 1}, {"science-pack-1", 1}, {"science-pack-2", 1}, {"science-pack-3", 1},
  }, {
    "advanced-electronics", "alien-technology", "battery", "logistics",
    "worker-robots-storage-2", "worker-robots-storage-3",
  }, true)
  return {inserter_row, storage_row}
end

local function pre_017_rows()
  local standard_science = {
    {"high-tech-science-pack", 1}, {"production-science-pack", 1},
    {"science-pack-1", 1}, {"science-pack-2", 1}, {"science-pack-3", 1},
  }
  return {
    row("braking-force-8", "braking-force", 8, "braking-force-7", "braking-force-6", {650, 550}, {
      {type="train-braking-force-bonus", scale=1},
    }, standard_science, {
      "advanced-electronics", "advanced-electronics-2", "advanced-material-processing-2", "automation-2",
      "battery", "braking-force-6", "braking-force-7", "electric-engine", "engine", "speed-module",
    }, "b-f-g"),
    inserter("inserter-capacity-bonus-8", 8, standard_science, {
      "advanced-electronics", "advanced-electronics-2", "advanced-material-processing-2", "automation-2",
      "battery", "electric-engine", "engine", "inserter-capacity-bonus-6",
      "inserter-capacity-bonus-7", "speed-module",
    }),
    row("research-speed-7", "research-speed", 7, "research-speed-6", "research-speed-5", {500, 500}, {
      {type="laboratory-speed", scale=1},
    }, {
      {"high-tech-science-pack", 1}, {"military-science-pack", 1}, {"production-science-pack", 1},
      {"science-pack-1", 1}, {"science-pack-2", 1}, {"science-pack-3", 1},
    }, {
      "advanced-electronics", "advanced-electronics-2", "advanced-material-processing-2", "automation-2",
      "battery", "electric-engine", "engine", "military-2", "research-speed-5", "research-speed-6",
      "speed-module", "turrets",
    }, "c-m-d"),
    storage("worker-robots-storage-4", 4, standard_science, {
      "advanced-electronics", "advanced-electronics-2", "advanced-material-processing-2", "automation-2",
      "battery", "electric-engine", "engine", "speed-module", "worker-robots-storage-2",
      "worker-robots-storage-3",
    }),
  }
end

local function later_rows(include_laser)
  local standard_science = {
    {"automation-science-pack", 1}, {"chemical-science-pack", 1}, {"logistic-science-pack", 1},
    {"production-science-pack", 1}, {"utility-science-pack", 1},
  }
  local rows = {
    row("braking-force-8", "braking-force", 8, "braking-force-7", "braking-force-6", {650, 550}, {
      {type="train-braking-force-bonus", scale=1},
    }, standard_science, {
      "braking-force-6", "braking-force-7", "chemical-science-pack", "logistic-science-pack",
      "production-science-pack", "utility-science-pack",
    }, "b-f-g"),
    inserter("inserter-capacity-bonus-8", 8, standard_science, {
      "chemical-science-pack", "inserter-capacity-bonus-6", "inserter-capacity-bonus-7",
      "logistic-science-pack", "production-science-pack", "utility-science-pack",
    }),
    row("research-speed-7", "research-speed", 7, "research-speed-6", "research-speed-5", {500, 500}, {
      {type="laboratory-speed", scale=1},
    }, {
      {"automation-science-pack", 1}, {"chemical-science-pack", 1}, {"logistic-science-pack", 1},
      {"military-science-pack", 1}, {"production-science-pack", 1}, {"utility-science-pack", 1},
    }, {
      "chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack",
      "research-speed-5", "research-speed-6", "utility-science-pack",
    }, "c-m-d"),
    row("weapon-shooting-speed-7", "weapon-shooting-speed", 7, "weapon-shooting-speed-6",
      "weapon-shooting-speed-5", {600, 500}, {
        {type="gun-speed", ammo_category="bullet", scale=1},
        {type="gun-speed", ammo_category="shotgun-shell", scale=1},
      }, {
        {"automation-science-pack", 1}, {"chemical-science-pack", 1}, {"logistic-science-pack", 1},
        {"military-science-pack", 1}, {"utility-science-pack", 1},
      }, {
        "chemical-science-pack", "logistic-science-pack", "military-science-pack", "utility-science-pack",
        "weapon-shooting-speed-5", "weapon-shooting-speed-6",
      }, "e-l-f"),
    storage("worker-robots-storage-4", 4, standard_science, {
      "chemical-science-pack", "logistic-science-pack", "production-science-pack", "utility-science-pack",
      "worker-robots-storage-2", "worker-robots-storage-3",
    }),
  }
  if include_laser then
    rows[#rows + 1] = row("laser-shooting-speed-8", "laser-shooting-speed", 8,
      "laser-shooting-speed-7", "laser-shooting-speed-6", {450, 350}, {
        {type="gun-speed", ammo_category="laser", scale=1},
      }, {
        {"automation-science-pack", 1}, {"chemical-science-pack", 1}, {"logistic-science-pack", 1},
        {"military-science-pack", 1}, {"utility-science-pack", 1},
      }, {
        "chemical-science-pack", "laser-shooting-speed-6", "laser-shooting-speed-7",
        "logistic-science-pack", "military-science-pack", "utility-science-pack",
      }, "e-n-n")
  end
  return rows
end

local function numeric_target(id)
  return {
    id=id, numeric=true, rows=numeric_rows(),
    omitted={"braking-force", "research-speed", "weapon-shooting-speed", "laser-shooting-speed",
      "worker-robots-speed"},
  }
end

local function pre_017_target(id)
  return {
    id=id, rows=pre_017_rows(),
    omitted={"weapon-shooting-speed", "laser-shooting-speed", "worker-robots-speed"},
  }
end

local function later_target(id, laser)
  return {
    id=id, rows=later_rows(laser),
    hidden=false, visible_when_disabled=false,
    omitted=laser and {"worker-robots-speed"} or {"laser-shooting-speed", "worker-robots-speed"},
  }
end

function M.for_target(target)
  if target == "f013" then return numeric_target("f013") end
  if target == "f014" then return numeric_target("f014") end
  if target == "f015" then return pre_017_target("f015") end
  if target == "f016" then return pre_017_target("f016") end
  if target == "f017" then return later_target("f017", false) end
  if target == "f100" then return later_target("f100", false) end
  if target == "f110" then return later_target("f110", true) end
  error("MIR historical continuation target is not supported: " .. tostring(target), 2)
end

function M.copy_target(target)
  return copy(M.for_target(target))
end

return M
