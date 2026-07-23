local function fail(message) error("MIR automatic productivity preview validation failed: " .. message) end
local artifact = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_orchestrator").snapshot()
local decisions = require("__more-infinite-research__.prototypes.mir.families.resolver").snapshot().decisions
if #decisions == 0 then fail("preview action recorded no family decisions") end
for _, row in ipairs(artifact.stream_plan.rows or {}) do
  if row.spec and row.spec.automatic_family and row.reason ~= "automatic_productivity_preview_only" then
    fail("automatic family row has wrong preview-action reason " .. tostring(row.reason))
  end
end
for _, technology in pairs(data.raw.technology or {}) do
  if technology.max_level == "infinite" then
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == "assemble-alpha" then
        fail("preview action attached an automatic recipe")
      end
    end
  end
end
