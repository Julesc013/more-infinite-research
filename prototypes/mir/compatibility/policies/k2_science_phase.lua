local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {
  policy_id = "K2SciencePhasePolicyV1",
  applicability = {
    Krastorio2 = "2.1.2",
    ["Krastorio2-spaced-out"] = "2.0.13"
  }
}

local EARLY_PACKS = {
  ["kr-basic-tech-card"] = true,
  ["automation-science-pack"] = true,
  ["logistic-science-pack"] = true,
  ["military-science-pack"] = true,
  ["chemical-science-pack"] = true
}

local BASIC_PACK = "kr-basic-tech-card"

local PHASE_ONE_TRIGGERS = {
  ["production-science-pack"] = true,
  ["utility-science-pack"] = true
}

local PHASE_TWO_TRIGGERS = {
  ["kr-advanced-tech-card"] = true,
  ["space-science-pack"] = true,
  ["kr-matter-tech-card"] = true,
  ["kr-singularity-tech-card"] = true
}

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
end

function M.applies(active_mods)
  active_mods = active_mods or {}
  return active_mods.Krastorio2 == M.applicability.Krastorio2
    and active_mods["Krastorio2-spaced-out"] == M.applicability["Krastorio2-spaced-out"]
end

function M.normalize(ingredients, active_mods)
  local original = deepcopy(ingredients or {})
  local decision = {
    policy_id = M.policy_id,
    status = "not-applicable",
    applicable = false,
    changed = false,
    exact_versions = deepcopy(M.applicability),
    removed_packs = {}
  }
  if not M.applies(active_mods) then return original, decision end

  decision.applicable = true
  local present, phase_one, phase_two = {}, false, false
  for _, ingredient in ipairs(original) do
    local name = ingredient_name(ingredient)
    if name then
      present[name] = true
      phase_one = phase_one or PHASE_ONE_TRIGGERS[name] == true
      phase_two = phase_two or PHASE_TWO_TRIGGERS[name] == true
    end
  end

  local remove = {}
  if phase_one then remove[BASIC_PACK] = true end
  if phase_two then
    for name in pairs(EARLY_PACKS) do remove[name] = true end
  end

  local normalized, removed_seen = {}, {}
  for _, ingredient in ipairs(original) do
    local name = ingredient_name(ingredient)
    if name and remove[name] then
      if present[name] and not removed_seen[name] then
        removed_seen[name] = true
        decision.removed_packs[#decision.removed_packs + 1] = name
      end
    else
      normalized[#normalized + 1] = deepcopy(ingredient)
    end
  end
  table.sort(decision.removed_packs)

  if #normalized == 0 and #original > 0 then
    decision.status = "blocked-empty-result"
    return original, decision
  end
  decision.changed = #normalized ~= #original
  decision.status = decision.changed and "normalized" or "already-normalized"
  return normalized, decision
end

return M
