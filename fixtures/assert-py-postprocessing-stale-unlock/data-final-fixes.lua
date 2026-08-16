local missing_recipe = "casting-gear"
local technology_name = "casting-mk02"
local expected_recipes = {"casting-valid-a", "casting-valid-b"}

if data.raw.recipe[missing_recipe] then
  error("MIR Py ordering assertion failed: casting-gear unexpectedly exists")
end

local technology = data.raw.technology[technology_name]
if not technology then
  error("MIR Py ordering assertion failed: missing casting-mk02")
end
if #technology.effects ~= #expected_recipes then
  error("MIR Py ordering assertion failed: expected two retained sibling effects, got "
    .. tostring(#technology.effects))
end
for index, recipe_name in ipairs(expected_recipes) do
  local effect = technology.effects[index]
  if not effect or effect.type ~= "unlock-recipe" or effect.recipe ~= recipe_name then
    error("MIR Py ordering assertion failed: retained sibling order changed at index "
      .. tostring(index))
  end
end

for candidate_name, candidate in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "unlock-recipe" then
      if effect.recipe == missing_recipe then
        error("MIR Py ordering assertion failed: stale casting-gear unlock survived on "
          .. tostring(candidate_name))
      end
      if not data.raw.recipe[effect.recipe] then
        error("MIR Py ordering assertion failed: missing recipe target "
          .. tostring(effect.recipe)
          .. " survived on "
          .. tostring(candidate_name))
      end
    end
  end
end

local internal_prototype = (data.raw["mod-data"] or {})["more-infinite-research-compiler-evidence-internal"]
local internal = internal_prototype and internal_prototype.data
local ledger = internal and internal.input_sanitation_ledger
if not ledger or ledger.pass ~= "input" or ledger.pruned_effect_count ~= 1
  or ledger.affected_technology_count ~= 1 then
  error("MIR Py ordering assertion failed: input sanitation did not record exactly one prune")
end

local row
for _, candidate in ipairs(ledger.technologies or {}) do
  if candidate.original_technology == technology_name then
    row = candidate
    break
  end
end
if not row or row.owner_kind ~= "external" or row.original_effect_count ~= 3
  or #row.removed_effects ~= 1 or #row.retained_effect_order ~= 2
  or row.retained_effect_order[1] ~= 1 or row.retained_effect_order[2] ~= 3 then
  error("MIR Py ordering assertion failed: sanitation ledger did not preserve exact effect order")
end

local removed = row.removed_effects[1]
if removed.type ~= "unlock-recipe" or removed.target ~= missing_recipe
  or removed.original_effect_index ~= 2
  or type(removed.removed_effect_fingerprint) ~= "string" then
  error("MIR Py ordering assertion failed: sanitation ledger did not bind casting-gear exactly")
end