local repair = require("__more-infinite-research__.prototypes.mir.compatibility.repairs.technology_prerequisite_cycles")
local safety = require("__more-infinite-research__.prototypes.mir.emit.technology_graph_safety")

local function fail(message)
  error("MIR external technology cycle validation failed: " .. message)
end

local function inspect(graph, generated)
  return safety.inspect_reachable("root", {
    technology_lookup = function(name) return graph[name] end,
    is_generated = function(name) return generated[name] == true end
  })
end

local reported_shape = {
  root = {prerequisites = {"worker-robots-storage-7"}},
  ["worker-robots-storage-7"] = {prerequisites = {"planet-discovery-secretas"}},
  ["planet-discovery-secretas"] = {prerequisites = {"space-science-pack"}},
  ["space-science-pack"] = {prerequisites = {"muluna-alice-propellant"}},
  ["muluna-alice-propellant"] = {prerequisites = {"astroponics"}},
  astroponics = {prerequisites = {"landfill", "space-science-pack"}},
  landfill = {prerequisites = {}}
}
local unrepaired_shape = table.deepcopy(reported_shape)

local before_ok, before_error = pcall(function()
  inspect(reported_shape, {root = true})
end)
if before_ok or not string.find(tostring(before_error), "External technology prerequisite cycle", 1, true) then
  fail("reported Muluna and Astroponics graph did not reproduce the external cycle")
end

local operations = repair.plan(reported_shape, {astroponics = "1.7.3", ["planet-muluna"] = "2.3.18"})
if #operations ~= 1 or operations[1].id ~= "muluna-astroponics-space-science-cycle" then
  fail("bounded Muluna and Astroponics repair was not selected")
end
repair.apply_plan(operations, reported_shape)
local repaired = inspect(reported_shape, {root = true})
if repaired.external_cycle_count ~= 0 then fail("repaired graph retained an external cycle") end
if #reported_shape.astroponics.prerequisites ~= 1 or reported_shape.astroponics.prerequisites[1] ~= "landfill" then
  fail("repair changed more than the cyclic Astroponics prerequisite edge")
end

local unrelated = {
  astroponics = {prerequisites = {"space-science-pack"}},
  ["space-science-pack"] = {prerequisites = {}}
}
if #repair.plan(unrelated, {astroponics = "1.7.3", ["planet-muluna"] = "2.3.18"}) ~= 0 then
  fail("repair activated without a mutual prerequisite path")
end
if #repair.plan(unrepaired_shape, {astroponics = "1.7.3"}) ~= 0 then
  fail("repair activated without both named mods")
end

local generated_cycle_graph = {
  root = {prerequisites = {"external-a"}},
  ["external-a"] = {prerequisites = {"root"}}
}
local generated_ok, generated_error = pcall(function()
  inspect(generated_cycle_graph, {root = true})
end)
if generated_ok or not string.find(tostring(generated_error), "MIR generated technology prerequisite cycle", 1, true) then
  fail("cycle containing a generated technology did not remain fatal")
end

local missing_ok = pcall(function()
  inspect({root = {prerequisites = {"missing"}}}, {root = true})
end)
if missing_ok then fail("missing prerequisite did not remain fatal") end

local disabled_ok = pcall(function()
  inspect({root = {prerequisites = {"disabled"}}, disabled = {enabled = false}}, {root = true})
end)
if disabled_ok then fail("disabled prerequisite did not remain fatal") end

local deep_graph = {}
for index = 1, 4096 do
  local name = "deep-" .. tostring(index)
  deep_graph[name] = {prerequisites = index < 4096 and {"deep-" .. tostring(index + 1)} or {}}
end
deep_graph.root = {prerequisites = {"deep-1"}}
local deep_summary = inspect(deep_graph, {root = true})
if deep_summary.external_cycle_count ~= 0 then fail("acyclic deep graph reported a cycle") end
