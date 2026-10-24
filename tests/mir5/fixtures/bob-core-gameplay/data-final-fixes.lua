-- Private F210 Bob-core gameplay acceleration. The fourteen named MIR rows
-- are first checked against the independent published 4.7.2 reference facts.
-- Only unit cost and time are then made small enough for a disposable real-lab
-- witness. This fixture neither changes material settings nor qualifies their
-- ordinary costs, effects, or arbitrary Bob configurations.
local families = {
  {
    key="research_material_tin", recipe="bob-tin-plate",
    early={name="recipe-prod-research_material_tin-1", order="p[research_material_tin]",
      science={"automation-science-pack"}, prerequisites={"automation-science-pack"}},
    tail={name="recipe-prod-research_material_tin-4", order="p[research_material_tin__continuation]",
      science={"automation-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "recipe-prod-research_material_tin-1", "space-science-pack"}},
  },
  {
    key="research_material_lead", recipe="bob-lead-plate",
    early={name="recipe-prod-research_material_lead-1", order="p[research_material_lead]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}},
    tail={name="recipe-prod-research_material_lead-4", order="p[research_material_lead__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_lead-1", "space-science-pack"}},
  },
  {
    key="research_material_bronze", recipe="bob-bronze-alloy",
    early={name="recipe-prod-research_material_bronze-1", order="p[research_material_bronze]",
      science={"automation-science-pack"}, prerequisites={"automation-science-pack", "bob-alloy-processing"}},
    tail={name="recipe-prod-research_material_bronze-4", order="p[research_material_bronze__continuation]",
      science={"automation-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-alloy-processing", "recipe-prod-research_material_bronze-1", "space-science-pack"}},
  },
  {
    key="research_material_gunmetal", recipe="bob-gunmetal-alloy",
    early={name="recipe-prod-research_material_gunmetal-1", order="p[research_material_gunmetal]",
      science={"automation-science-pack", "logistic-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "bob-zinc-processing"}},
    tail={name="recipe-prod-research_material_gunmetal-4", order="p[research_material_gunmetal__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-zinc-processing", "logistic-science-pack", "recipe-prod-research_material_gunmetal-1", "space-science-pack"}},
  },
  {
    key="research_material_invar", recipe="bob-invar-alloy",
    early={name="recipe-prod-research_material_invar-1", order="p[research_material_invar]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "bob-invar-processing"}},
    tail={name="recipe-prod-research_material_invar-4", order="p[research_material_invar__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-invar-processing", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_invar-1", "space-science-pack"}},
  },
  {
    key="research_material_nitinol", recipe="bob-nitinol-alloy",
    early={name="recipe-prod-research_material_nitinol-1", order="p[research_material_nitinol]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "bob-nitinol-processing"}},
    tail={name="recipe-prod-research_material_nitinol-4", order="p[research_material_nitinol__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-nitinol-processing", "chemical-science-pack", "logistic-science-pack", "production-science-pack", "recipe-prod-research_material_nitinol-1", "space-science-pack"}},
  },
  {
    key="research_material_copper_tungsten", recipe="bob-copper-tungsten-alloy",
    early={name="recipe-prod-research_material_copper_tungsten-1", order="p[research_material_copper_tungsten]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "metallurgic-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "metallurgic-science-pack", "bob-tungsten-processing"}},
    tail={name="recipe-prod-research_material_copper_tungsten-4", order="p[research_material_copper_tungsten__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "metallurgic-science-pack"},
      prerequisites={"automation-science-pack", "bob-tungsten-processing", "chemical-science-pack", "logistic-science-pack", "metallurgic-science-pack", "production-science-pack", "recipe-prod-research_material_copper_tungsten-1", "space-science-pack"}},
  },
}

local function assert_names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do
    assert(actual[index] == name, label .. " changed at " .. tostring(index))
  end
end

local function assert_stage(family, stage, finite)
  local value = assert(data.raw.technology[stage.name], stage.name .. " is absent")
  assert(value.type == "technology" and value.name == stage.name and value.order == stage.order,
    stage.name .. " identity changed")
  assert(value.level == (finite and 1 or 4) and value.upgrade == true
      and value.max_level == (finite and 3 or "infinite"), stage.name .. " progression changed")
  assert(value.enabled ~= false, stage.name .. " is disabled")
  if finite then
    assert(value.show_levels_info == nil and value.visible_when_disabled == nil,
      stage.name .. " finite presentation changed")
  else
    assert(value.show_levels_info == false and value.visible_when_disabled == true,
      stage.name .. " continuation presentation changed")
  end
  assert_names(value.prerequisites, stage.prerequisites, stage.name .. " prerequisites")
  local unit = assert(value.unit, stage.name .. " unit is absent")
  local formula = finite and "200*2^(L-1)" or "1600+200*(L-4)"
  assert(unit.count == nil and unit.count_formula == formula and unit.time == 30,
    stage.name .. " ordinary cost or time changed")
  assert(type(unit.ingredients) == "table" and #unit.ingredients == #stage.science,
    stage.name .. " science count changed")
  for index, name in ipairs(stage.science) do
    local ingredient = unit.ingredients[index]
    assert(type(ingredient) == "table" and (ingredient.name or ingredient[1]) == name
      and (ingredient.amount or ingredient[2]) == 1, stage.name .. " science changed at " .. tostring(index))
  end
  assert(type(value.effects) == "table" and #value.effects == 1, stage.name .. " effects changed")
  local effect = value.effects[1]
  assert(type(effect) == "table" and effect.type == "change-recipe-productivity"
      and effect.recipe == family.recipe and effect.change == 0.02, stage.name .. " effect changed")
  return value
end

-- Collect only after every independently authored stage has passed, so a
-- later mismatch cannot leave an earlier technology accelerated.
local rows = {}
for _, family in ipairs(families) do
  rows[#rows + 1] = assert_stage(family, family.early, true)
  rows[#rows + 1] = assert_stage(family, family.tail, false)
end
for _, value in ipairs(rows) do
  value.unit.count_formula, value.unit.count, value.unit.time = nil, 1, 1
end
