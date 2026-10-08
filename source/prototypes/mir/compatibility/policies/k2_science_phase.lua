local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {
  -- Retain the historical 2.1.2 contract verbatim. Its frozen witnesses bind
  -- this public identity and exact version tuple.
  policy_id = "K2SciencePhasePolicyV1",
  applicability = {
    Krastorio2 = "2.1.2",
    ["Krastorio2-spaced-out"] = "2.0.13"
  },
  -- This is a distinct, exact successor admission. It deliberately is not a
  -- range: an upstream version must be separately observed and admitted.
  v3_policy_id = "K2SciencePhasePolicyV3",
  v4_policy_id = "K2SciencePhasePolicyV4",
  v5_policy_id = "K2SciencePhasePolicyV5",
  v5_applicability = {
    base = "2.1.21",
    Krastorio2 = "2.1.3",
    ["Krastorio2-spaced-out"] = "2.0.13"
  },
  v4_applicability = {
    base = "2.1.20",
    Krastorio2 = "2.1.2",
    ["Krastorio2-spaced-out"] = "2.0.13"
  },
  v3_applicability = {
    base = "2.1.20",
    Krastorio2 = "2.1.3",
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

local function matches_exact_tuple(active_mods, exact_versions)
  active_mods = active_mods or {}
  for name, version in pairs(exact_versions) do
    if active_mods[name] ~= version then return false end
  end
  return true
end

local function matching_policy(active_mods)
  if matches_exact_tuple(active_mods, M.v5_applicability) then
    return M.v5_policy_id, M.v5_applicability
  end
  -- Current-engine profiles expose base. Do not apply the historical V1
  -- tuple to a different engine merely because its two named mods match.
  if matches_exact_tuple(active_mods, M.v4_applicability) then
    return M.v4_policy_id, M.v4_applicability
  end
  if active_mods and active_mods.base ~= nil and matches_exact_tuple(active_mods, M.applicability) then
    return nil, nil
  end
  if matches_exact_tuple(active_mods, M.applicability) then
    return M.policy_id, M.applicability
  end
  if matches_exact_tuple(active_mods, M.v3_applicability) then
    return M.v3_policy_id, M.v3_applicability
  end
  return nil, nil
end

function M.applies(active_mods)
  local policy_id = matching_policy(active_mods)
  return policy_id ~= nil
end

-- This selects the existing continuation declaration only. Recipe safety,
-- useful output and ownership still require their ordinary planner gates.
function M.imersite_continuation_applies(active_mods)
  return matches_exact_tuple(active_mods, M.v3_applicability)
    or matches_exact_tuple(active_mods, M.v5_applicability)
end

function M.normalize(ingredients, active_mods)
  local original = deepcopy(ingredients or {})
  local matched_policy_id, matched_versions = matching_policy(active_mods)
  local decision = {
    -- Preserve unmatched and legacy decision identity/shape for old callers.
    policy_id = matched_policy_id or M.policy_id,
    status = "not-applicable",
    applicable = false,
    changed = false,
    exact_versions = deepcopy(matched_versions or M.applicability),
    removed_packs = {}
  }
  if not matched_policy_id then return original, decision end

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

  -- Preserve phase intent before a planner can discard ingredients. At least
  -- one selected trigger must survive lab reduction in the intended phase.
  decision.required_any_packs = {}
  local triggers = phase_two and PHASE_TWO_TRIGGERS or (phase_one and PHASE_ONE_TRIGGERS or {})
  for name in pairs(present) do
    if triggers[name] then decision.required_any_packs[#decision.required_any_packs + 1] = name end
  end
  table.sort(decision.required_any_packs)
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
