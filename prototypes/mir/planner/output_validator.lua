local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generation_plan = require("prototypes.mir.planner.generation_plan")

local M = {}

local function effect_identities(technology)
  local out = {}
  for _, effect in ipairs((technology and technology.effects) or {}) do
    out[generation_plan.effect_identity(effect)] = true
  end
  return out
end

local function assert_effects(owner_name, expected_effects)
  local technology = data_raw.technology(owner_name)
  if not technology then error("GenerationPlan output technology is missing: " .. owner_name, 2) end
  local actual = effect_identities(technology)
  for _, effect in ipairs(expected_effects or {}) do
    local identity = generation_plan.effect_identity(effect)
    if identity ~= "" and not actual[identity] then
      error("GenerationPlan output effect is missing from " .. owner_name .. ": " .. identity, 2)
    end
  end
end

function M.assert_artifact(artifact)
  if not artifact or artifact.schema ~= 3 then error("GenerationPlan schema 3 artifact is required", 2) end
  local expected_recipe_owners = {}
  local checked_rows = 0
  for _, row in ipairs(artifact.rows or {}) do
    local owner_name, effects
    if row.action == "emit" then
      owner_name, effects = row.technology_name, row.fields.effects
    elseif row.action == "adopt" then
      owner_name, effects = row.adoption.owner, row.adoption.effects
    end
    if owner_name then
      assert_effects(owner_name, effects)
      checked_rows = checked_rows + 1
      for _, effect in ipairs(effects or {}) do
        if effect.type == "change-recipe-productivity" and effect.recipe then
          expected_recipe_owners[effect.recipe] = owner_name
        end
      end
    end
  end

  local actual_recipe_owners = {}
  for technology_name, technology in pairs(data_raw.prototypes("technology")) do
    if technology.max_level == "infinite" then
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "change-recipe-productivity" and effect.recipe then
          actual_recipe_owners[effect.recipe] = actual_recipe_owners[effect.recipe] or {}
          actual_recipe_owners[effect.recipe][technology_name] = true
        end
      end
    end
  end
  for recipe_name, expected_owner in pairs(expected_recipe_owners) do
    local owners, count = actual_recipe_owners[recipe_name] or {}, 0
    for _ in pairs(owners) do count = count + 1 end
    if count ~= 1 or not owners[expected_owner] then
      error("GenerationPlan final owner mismatch for recipe " .. recipe_name .. ": expected " .. expected_owner, 2)
    end
  end
  return {checked_rows = checked_rows}
end

return M
