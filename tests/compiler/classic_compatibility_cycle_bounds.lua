-- Source-bound controls for Classic's bounded external prerequisite repair.
-- Full calls remain on the historical options-omitted API.

mods = {astroponics = "1.0.0", ["planet-muluna"] = "1.0.0"}
local diagnostics, logs = {}, {}
log = function(message) logs[#logs + 1] = message end
data = {raw = {technology = {}}}
function data:extend() end

package.preload["prototypes.mir.report.diagnostics_sink"] = function()
  return {compatibility_plan = function(row) diagnostics[#diagnostics + 1] = row end}
end

local schema_calls = 0
package.preload["prototypes.mir.compatibility.repairs.factorio_2_1_recipe_schema"] = function()
  return {apply = function() schema_calls = schema_calls + 1 end}
end

local assertions = 0
local function check(condition, detail)
  assert(condition, detail)
  assertions = assertions + 1
end

local cycles = require("prototypes.mir.compatibility.repairs.technology_prerequisite_cycles")
local registry = require("prototypes.mir.compatibility.repairs.registry")

local function valid_graph()
  return {
    astroponics = {name = "astroponics", prerequisites = {"space-science-pack"}},
    ["space-science-pack"] = {name = "space-science-pack", prerequisites = {"astroponics"}}
  }
end

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

-- The options-omitted Full API retains its original planned operation and
-- mutation behavior.
local legacy = valid_graph()
local planned = cycles.plan(legacy, mods)
check(#planned == 1 and planned[1].id == "muluna-astroponics-space-science-cycle",
  "legacy plan retains the exact declared Muluna/Astroponics repair")
cycles.apply_plan(planned, legacy)
check(legacy.astroponics.prerequisites == nil,
  "legacy apply removes only the declared prerequisite")

data.raw.technology = valid_graph()
local bounded_valid = cycles.apply({bounded = true})
check(bounded_valid.status.status == "complete" and #bounded_valid.operations == 1,
  "bounded Classic repair accepts the short declared reverse path")
check(data.raw.technology.astroponics.prerequisites == nil,
  "bounded Classic repair mutates the same valid short edge")
check(diagnostics[#diagnostics].status == "repaired",
  "a completed bounded repair retains the repaired diagnostic")

-- A cycle that never reaches Astroponics is a complete negative result, not a
-- budget failure and not an unsafe edge removal.
data.raw.technology = {
  astroponics = {name = "astroponics", prerequisites = {"space-science-pack"}},
  ["space-science-pack"] = {name = "space-science-pack", prerequisites = {"a"}},
  a = {name = "a", prerequisites = {"b"}},
  b = {name = "b", prerequisites = {"a"}}
}
local impossible = cycles.apply({bounded = true})
check(impossible.status.status == "complete" and #impossible.operations == 0,
  "a finite impossible cyclic reverse path is a complete no-repair result")
check(contains(data.raw.technology.astroponics.prerequisites, "space-science-pack"),
  "an impossible reverse path leaves the external prerequisite unchanged")

-- The Classic path rejects a large prerequisite vector before traversal or
-- copying, and reports a compact not-evaluated result.
local wide = {}
for index = 1, 65 do wide[index] = "wide-" .. tostring(index) end
wide[1] = "space-science-pack"
data.raw.technology = {
  astroponics = {name = "astroponics", prerequisites = wide},
  ["space-science-pack"] = {name = "space-science-pack", prerequisites = {"astroponics"}}
}
local wide_result = cycles.apply({bounded = true})
check(wide_result.status.status == "not-evaluated"
  and wide_result.status.reason == "classic_compatibility_cycle_prerequisite_shape",
  "an oversized prerequisite array is explicitly not evaluated")
check(data.raw.technology.astroponics.prerequisites == wide,
  "an oversized prerequisite array is never partially copied or mutated")
check(diagnostics[#diagnostics].status == "not-evaluated"
  and diagnostics[#diagnostics].reason == wide_result.status.reason,
  "the bounded refusal is recorded without fabricating a repair")

-- The shared traversal budget stops a long but otherwise ordinary chain.  It
-- never uses budget exhaustion as proof that the prerequisite is safe to drop.
local exhausted = {
  astroponics = {name = "astroponics", prerequisites = {"space-science-pack"}},
  ["space-science-pack"] = {name = "space-science-pack", prerequisites = {"classic-chain-1"}}
}
for index = 1, 129 do
  local next_name = index == 129 and "astroponics" or "classic-chain-" .. tostring(index + 1)
  exhausted["classic-chain-" .. tostring(index)] = {
    name = "classic-chain-" .. tostring(index), prerequisites = {next_name}
  }
end
data.raw.technology = exhausted
local exhausted_result = cycles.apply({bounded = true})
check(exhausted_result.status.status == "not-evaluated"
  and exhausted_result.status.reason == "classic_compatibility_cycle_visit_bound",
  "a long reverse path is explicitly bounded before graph-wide traversal")
check(contains(exhausted.astroponics.prerequisites, "space-science-pack"),
  "budget exhaustion leaves the external edge untouched")

-- Apply preflights the current prerequisite vector.  A graph changed after a
-- successful bounded plan cannot cause a copied or partial mutation.
local changed = valid_graph()
local plan_operations, plan_status = cycles.plan(changed, mods, {bounded = true})
check(plan_status.status == "complete" and #plan_operations == 1,
  "the preflight opposition begins with a valid bounded plan")
local changed_wide = {}
for index = 1, 65 do changed_wide[index] = "changed-" .. tostring(index) end
changed_wide[1] = "space-science-pack"
changed.astroponics.prerequisites = changed_wide
local applied, apply_status = cycles.apply_plan(plan_operations, changed, {bounded = true})
check(apply_status.status == "not-evaluated" and #applied == 0,
  "apply rejects a changed oversized array before any mutation")
check(changed.astroponics.prerequisites == changed_wide,
  "changed prerequisites survive a bounded apply refusal intact")

-- Registry forwards the bounded option to the repair, while the historical
-- options-omitted registry entry point retains its nil return contract.
data.raw.technology = valid_graph()
local registry_bounded = registry.apply({bounded = true})
check(schema_calls == 1 and registry_bounded.status.status == "complete"
  and data.raw.technology.astroponics.prerequisites == nil,
  "registry forwards the Classic bounded repair request after schema repair")
data.raw.technology = valid_graph()
check(registry.apply() == nil and schema_calls == 2,
  "options-omitted Full registry behavior remains a nil-returning entry point")
check(data.raw.technology.astroponics.prerequisites == nil,
  "options-omitted registry retains the historical repair mutation")
check(#logs > 0, "bounded refusals and valid repairs produce compact log records")

return {assertions = assertions}
