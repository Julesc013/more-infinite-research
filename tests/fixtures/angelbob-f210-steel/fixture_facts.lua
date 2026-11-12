-- Finite independent facts for the exact 2.1.23 Angel/Bob rebalance closure.
-- The owner is foreign.  This fixture only introduces its own fast void lab.
local M = {}

M.fixture = "mir-fixture-mir5-angelbob-f210-steel"
M.mir = "more-infinite-research"
M.owner = "steel-plate-productivity"
M.base_version = "2.1.23"
M.mir_version = "5.0.21013"
M.rebalance_version = "1.3.2"
M.save = "mir5-native-complete"
M.deadline_ticks = 36000
M.settle_ticks = 2
M.fast_lab = "mir-fixture-mir5-angelbob-f210-steel-fast-lab"
M.fast_lab_speed = 6000
M.initial_stack = 200
M.refill_below = 100
M.refill_amount = 100
M.first_level_count = 1500
M.research_unit_energy = 3600
M.effect_change = .1
M.prerequisites = {"production-science-pack"}
M.ingredients = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
}
M.named_recipes = {"steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2"}

M.strict_closure = {
  base="2.1.23", ["elevated-rails"]="2.1.23", quality="2.1.23", recycler="2.1.23", ["space-age"]="2.1.23",
  ["angelbob-spaceage-rebalance"]="1.3.2", angelsbioprocessing="2.1.1", angelsbioprocessinggraphics="2.1.0",
  angelspetrochem="2.1.3", angelspetrochemgraphics="2.1.0", angelsrefining="2.1.2",
  angelsrefininggraphics="2.1.0", angelssmelting="2.1.1", angelssmeltinggraphics="2.1.1",
  bobassembly="3.0.1", bobelectronics="3.0.1", boblibrary="3.0.1", boblogistics="3.0.1", bobmodules="3.0.1",
  bobores="3.0.0", bobplates="3.0.2", bobpower="3.0.0", bobrevamp="3.0.0", bobtech="3.0.0",
  [M.mir]=M.mir_version, [M.fixture]="0.1.0",
}

function M.close(actual, expected)
  return type(actual) == "number" and type(expected) == "number" and math.abs(actual - expected) <= .0000001
end

function M.assert_exact_mods(active_mods, fail)
  for name, version in pairs(M.strict_closure) do
    if active_mods[name] ~= version then fail("declared closure differs: " .. name) end
  end
  for name in pairs(active_mods) do
    if M.strict_closure[name] == nil then fail("unexpected declared mod: " .. name) end
  end
end

return M
