local function fail(message) error("MIR automatic compiler off validation failed: " .. message) end
local artifact = require("__more-infinite-research__.prototypes.mir.planner.compilation_plan").snapshot()
for _, row in ipairs(artifact.stream_plan.rows or {}) do
  if row.spec and row.spec.automatic_family and row.reason ~= "automatic_family_mode_off" then
    fail("automatic family row has wrong off-mode reason " .. tostring(row.reason))
  end
end
for _, technology in pairs(data.raw.technology or {}) do
  if technology.max_level == "infinite" then
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == "assemble-alpha" then
        fail("off mode attached an automatic recipe")
      end
    end
  end
end
