local techs = data.raw.technology or {}

local function fail(message)
  error("MIR Plates n Circuit change-mismatch validation failed: " .. message)
end

local function recipe_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return effect
    end
  end
  return nil
end

local competitor = techs["electric-circuit-productivity"]
if not competitor then
  fail("expected mismatched competing technology to remain")
end

local competitor_effect = recipe_effect(competitor, "electronic-circuit")
if not competitor_effect or competitor_effect.change ~= 0.05 then
  fail("expected competing electronic-circuit effect with change 0.05 to remain")
end

local mir = techs["recipe-prod-research_electronic_circuit-1"]
if recipe_effect(mir, "electronic-circuit") then
  fail("MIR should not generate a duplicate electronic-circuit owner when the known competitor has a different change value")
end
