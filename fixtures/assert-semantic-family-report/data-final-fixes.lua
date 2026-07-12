local function fail(message) error("MIR automatic compiler report validation failed: " .. message) end
local artifact = require("__more-infinite-research__.prototypes.mir.planner.compilation_plan").snapshot()
local decisions = require("__more-infinite-research__.prototypes.mir.families.resolver").snapshot().decisions
if #decisions == 0 then fail("report mode recorded no family decisions") end
for _, row in ipairs(artifact.stream_plan.rows or {}) do
  if row.spec and row.spec.automatic_family and row.reason ~= "automatic_family_mode_report" then
    fail("automatic family row has wrong report-mode reason " .. tostring(row.reason))
  end
end
for _, technology in pairs(data.raw.technology or {}) do
  if technology.max_level == "infinite" then
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == "assemble-alpha" then
        fail("report mode attached an automatic recipe")
      end
    end
  end
end
