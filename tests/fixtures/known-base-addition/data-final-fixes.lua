-- Deliberately model one late provider retiring this named public main.
-- This is a runtime preservation reproducer, not a real-provider adapter.
local main = assert(data.raw.technology["recipe-prod-research_plastic-1"], "known-Base plastic main absent")
local expected = {["plastic-bar"]=true,["mir-known-base-unpaid-plastic-bar"]=true}
assert(main.hidden ~= true and #main.effects == 2, "known-Base plastic public vector differs")
for _, effect in ipairs(main.effects) do
  assert(effect.type == "change-recipe-productivity" and effect.change == .1 and expected[effect.recipe],
    "known-Base plastic public effect differs")
  expected[effect.recipe] = nil
end
assert(next(expected) == nil, "known-Base plastic public vector incomplete")
main.effects, main.hidden, main.enabled, main.visible_when_disabled = {}, true, false, false
