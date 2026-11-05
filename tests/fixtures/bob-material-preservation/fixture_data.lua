-- Only disposable test-owned prototypes and timing are changed here.
local M = {}
local PREFIX = "mir5-bob-material-preservation"
local KEYS = {"tin", "lead", "bronze", "gunmetal", "invar", "nitinol", "copper_tungsten"}
local RECIPES = {tin="bob-tin-plate", lead="bob-lead-plate", bronze="bob-bronze-alloy",
  gunmetal="bob-gunmetal-alloy", invar="bob-invar-alloy", nitinol="bob-nitinol-alloy",
  copper_tungsten="bob-copper-tungsten-alloy"}

function M.prototypes(stage)
  if stage ~= "readmitted" then
    data:extend{{type="recipe", name=PREFIX .. "-tin-return", enabled=false,
      ingredients={{type="item", name="bob-tin-plate", amount=1}},
      results={{type="item", name="bob-tin-ore", amount=1}}, energy_required=1}}
  end
  local lab = table.deepcopy(data.raw.lab.lab)
  lab.name = PREFIX .. "-lab"
  lab.minable, lab.next_upgrade, lab.fast_replaceable_group = nil, nil, nil
  lab.researching_speed = 60
  lab.energy_usage = "1MW"
  lab.inputs = {"automation-science-pack", "space-science-pack"}
  data:extend{lab}
end

function M.settings(stage)
  local setting = data.raw["int-setting"]["ips-max-level-research_material_tin"]
  assert(setting, "[mir5-bob-material-preservation] Tin cap setting is absent")
  setting.default_value = stage == "source" and 4 or 7
end

function M.accelerate(stage)
  for _, key in ipairs(KEYS) do
    for _, suffix in ipairs{"1", "4"} do
      local name = "recipe-prod-research_material_" .. key .. "-" .. suffix
      local tech = data.raw.technology[name]
      assert(tech and #tech.effects == 1 and tech.effects[1].type == "change-recipe-productivity"
        and tech.effects[1].change == 0.02 and tech.effects[1].recipe == RECIPES[key],
        "[mir5-bob-material-preservation] independent paid identity/effect differs: " .. name)
      if stage == "source" then
        assert(tech.enabled ~= false, "[mir5-bob-material-preservation] published source identity unavailable")
      elseif key ~= "lead" and not (stage == "readmitted" and key == "tin") then
        assert(tech.enabled == false, "[mir5-bob-material-preservation] returning route was admitted: " .. name)
      else
        assert(tech.enabled ~= false, "[mir5-bob-material-preservation] safe route was withheld: " .. name)
      end
    end
  end
  -- Fixed hundred-pack tails allow 42 actually consumed science sets.
  for _, key in ipairs{"tin", "bronze"} do
    local tech = data.raw.technology["recipe-prod-research_material_" .. key .. "-4"]
    tech.unit.count, tech.unit.count_formula, tech.unit.time = 100, nil, 1
    tech.unit.ingredients = {{"automation-science-pack", 1}, {"space-science-pack", 1}}
  end
end

return M
