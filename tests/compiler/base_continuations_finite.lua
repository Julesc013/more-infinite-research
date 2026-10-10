-- Controlled regression for finite upstream continuation chains.  It runs the
-- real planner with researchability/lab admission supplied by the test so the
-- assertion remains about terminal discovery and stable prerequisite identity.
mods = {base = "2.1.21"}
settings = {startup = {}}
feature_flags = {scripted_techs = true}
log = function() end
data = {raw = {technology = {}, item = {}, recipe = {}, lab = {}}}
function data:extend(rows)
  for _, row in ipairs(rows) do
    self.raw[row.type] = self.raw[row.type] or {}
    self.raw[row.type][row.name] = row
  end
end

local assertions = 0
local function check(condition, detail)
  assert(condition, detail)
  assertions = assertions + 1
  print("OBSERVED\t" .. detail)
end

local function has(rows, name)
  for _, row in ipairs(rows or {}) do
    if row == name or (type(row) == "table" and (row.name or row[1]) == name) then return true end
  end
  return false
end

local function technology(name, count, prerequisites, max_level)
  return {
    type = "technology", name = name, enabled = true, upgrade = true,
    effects = {{type = "worker-robot-storage", modifier = 1}},
    prerequisites = prerequisites or {},
    unit = {count = count, time = 60, ingredients = {{"automation-science-pack", 1}}},
    max_level = max_level
  }
end

-- Secretas' actual shape uses separate finite definitions through level eight.
for level = 1, 8 do
  data.raw.technology["worker-robots-storage-" .. level] = technology(
    "worker-robots-storage-" .. level, 100 * (2 ^ (level - 1)),
    level == 1 and {} or {"worker-robots-storage-" .. (level - 1)})
end

local discover = require("prototypes.mir.planner.base_continuations.discover")
local levels, _, has_infinite, terminals = discover.chain("worker-robots-storage")
check(not has_infinite and levels[#levels] == 8 and terminals[8].name == "worker-robots-storage-8",
  "separate finite levels retain their real terminal prototype")

local science = require("prototypes.mir.capabilities.science_integration.science_packs")
science.technology_researchability_reason = function(name)
  check(name == "worker-robots-storage-8" or name == "worker-robots-storage-4",
    "finite continuation checks a real terminal prototype name")
  return nil
end
local qualify = require("prototypes.mir.planner.base_continuations.qualify")
qualify.is_enabled = function(key) return key == "worker-robots-storage" end
local selected_cap = nil
qualify.startup_setting = function(name)
  if name == "mir-max-level-worker-robots-storage" then return selected_cap end
  return nil
end
qualify.resolve_ingredients = function(_, unit)
  return unit.ingredients, "full", nil
end
qualify.append_end_game_prerequisite = function(prerequisites) return prerequisites end
qualify.prefer_this_mod_for_competing_techs = function() return true end

local plan = require("prototypes.mir.planner.base_continuations.plan")
local context = require("prototypes.mir.pipeline.compiler_context")
local function planned_worker_continuation()
  local operation
  context.with_active(context.new(), function()
    local planned = plan.plan_all()
    for _, candidate in ipairs(planned) do
      if candidate.technology_name == "worker-robots-storage-9" then operation = candidate end
    end
  end)
  return operation
end

local separate_operation = planned_worker_continuation()
check(separate_operation and separate_operation.base_technology_name == "worker-robots-storage-8"
  and has(separate_operation.technology.prerequisites, "worker-robots-storage-8"),
  "separate finite level-eight chain produces a level-nine continuation")

-- An upstream numeric range is represented by one prototype named at its
-- first level.  Its MIR continuation begins after max_level and depends on
-- that real prototype, never an invented intermediate name.
data.raw.technology = {
  ["worker-robots-storage-1"] = technology("worker-robots-storage-1", 100),
  ["worker-robots-storage-2"] = technology("worker-robots-storage-2", 200, {"worker-robots-storage-1"}),
  ["worker-robots-storage-3"] = technology("worker-robots-storage-3", 400, {"worker-robots-storage-2"}),
  ["worker-robots-storage-4"] = technology("worker-robots-storage-4", 800, {"worker-robots-storage-3"}, 8)
}
levels, _, has_infinite, terminals = discover.chain("worker-robots-storage")
check(not has_infinite and levels[#levels] == 4 and terminals[8].name == "worker-robots-storage-4",
  "finite numeric range retains terminal level and real anchor")

local operation = planned_worker_continuation()
check(operation ~= nil, "finite numeric range produces level-nine MIR continuation")
check(operation.base_technology_name == "worker-robots-storage-4"
  and has(operation.technology.prerequisites, "worker-robots-storage-4")
  and not has(operation.technology.prerequisites, "worker-robots-storage-8"),
  "level-nine continuation preserves the finite range's real prerequisite")

selected_cap = 8
local capped_operation = planned_worker_continuation()
check(capped_operation == nil or (capped_operation.planned_max_level == 8
    and capped_operation.technology.hidden == true),
  "configured cap remains authoritative when it is below the first finite continuation")
selected_cap = nil

data.raw.technology["worker-robots-storage-4"].max_level = "infinite"
local _, _, infinite = discover.chain("worker-robots-storage")
check(infinite, "true infinite owner remains detected")
check(planned_worker_continuation() == nil, "true infinite owner prevents a duplicate MIR continuation")

print("MIR-BASE-CONTINUATIONS-FINITE-PASS " .. assertions)
