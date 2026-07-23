local function fail(message)
  error("MIR exact-pack family authorization validation failed: " .. message)
end

for _, technology_name in ipairs({
  "mir-auto-prod-manufacturing-assembling-machine-1",
  "mir-auto-prod-manufacturing-lab-1"
}) do
  if data.raw.technology and data.raw.technology[technology_name] then
    fail("experimental family entered the reviewed-data creation lane: " .. technology_name)
  end
end

local artifact = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_orchestrator").snapshot()
local blocked = {}
for _, row in ipairs((artifact and artifact.stream_plan and artifact.stream_plan.rows) or {}) do
  if row.stream_key == "research_auto_assembling_machine" or row.stream_key == "research_auto_lab" then
    if row.action ~= "skip" or row.reason ~= "automatic_family_not_reviewed" then
      fail("experimental family has wrong reviewed-data decision: " .. tostring(row.stream_key) .. "/" .. tostring(row.reason))
    end
    blocked[row.stream_key] = true
  end
end
if not blocked.research_auto_assembling_machine or not blocked.research_auto_lab then
  fail("generation plan omitted an experimental-family reviewed-data decision")
end

local belt = data.raw.technology and data.raw.technology["recipe-prod-research_belts-1"]
local seeded = false
for _, effect in ipairs((belt and belt.effects) or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == "pack-only-recipe" then seeded = true end
end
if not seeded then fail("exact pack candidate seed did not join the safe attachment baseline") end
