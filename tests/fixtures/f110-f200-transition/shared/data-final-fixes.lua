local plan = require("__mir-fixture-mir5-f110-f200-transition__/catalogue")

if type(plan) ~= "table" or (plan.stage ~= "source" and plan.stage ~= "successor") then
  error("[mir5-f110-f200-transition] staged catalogue differs")
end
