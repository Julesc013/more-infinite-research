local function fail(message) error("MIR automatic productivity disabled validation failed: " .. message) end
local artifact = require("__more-infinite-research__.prototypes.mir.planner.compilation_plan").snapshot()
for _, row in ipairs(artifact.stream_plan.rows or {}) do
  if row.spec and row.spec.automatic_family and row.reason ~= "automatic_productivity_disabled" then
    fail("automatic family row has wrong disabled-action reason " .. tostring(row.reason))
  end
end
for _, technology in pairs(data.raw.technology or {}) do
  if technology.max_level == "infinite" then
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == "assemble-alpha" then
        fail("disabled action attached an automatic recipe")
      end
    end
  end
end
